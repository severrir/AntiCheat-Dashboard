local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Signal = require(AC.Classes.Signal)
local SyncBatch = require(AC.Classes.SyncBatch)
local Framework = require(ReplicatedStorage.Shared.Framework)

local B = Config.Backend

-- the only thing that talks to supabase. batches flags, syncs every 20s, hands out what comes back
local BackendService = {
	Name = "ACBackendService",
	Synced = Signal.new(), -- (response)
	Online = false,
	ServerId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false),
}

local function round(n)
	return math.floor(n * 10 + 0.5) / 10
end

function BackendService:Init()
	self._batch = SyncBatch.new(B.MaxQueue)
	self._since = nil
	self._syncing = false
	self._inflight = 0

	-- the experience secret store in live servers, the server-only module in studio
	-- (studio has no secrets and its debugger pauses on the error even inside pcall)
	if not RunService:IsStudio() then
		local ok, secret = pcall(HttpService.GetSecret, HttpService, B.SecretName)
		if ok then
			self._key = secret
		end
	end
	if not self._key then
		local found = AC:FindFirstChild("ServerKey")
		self._key = found and require(found)
	end
end

-- yields. nil on any failure
function BackendService:Post(body)
	if not self._key then
		return nil
	end
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = B.Url,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
			["x-game-key"] = self._key,
		},
		Body = HttpService:JSONEncode(body),
	})
	if not ok or not res.Success then
		return nil
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	return if decoded then data else nil
end

-- runs fn in its own thread and keeps the server alive for it on shutdown. kick uploads go
-- through here, otherwise kicking the last player closes the server before the kick is sent
function BackendService:Track(fn)
	self._inflight += 1
	task.spawn(function()
		local ok, err = pcall(fn)
		self._inflight -= 1
		if not ok then
			warn("[AntiCheat] " .. tostring(err))
		end
	end)
end

function BackendService:QueueFlag(profile, check, raw, amount, score, ctx, pos)
	self._batch:AddFlag(profile, check, raw, amount, score, ctx, pos)
end

function BackendService:QueueKick(profile, reason, score, replayId, sig)
	self._batch:AddKick({
		id = tostring(profile.userId),
		name = profile.player.Name,
		reason = reason,
		score = score,
		replay = replayId,
		sig = sig,
	})
end

function BackendService:Ack(userId, active)
	self._batch:AddAck(userId, active)
end

function BackendService:CheckJoin(userId)
	return self:Post({ op = "join", id = tostring(userId) })
end

function BackendService:_snapshot(profile, now)
	return {
		id = tostring(profile.userId),
		name = profile.player.Name,
		score = round(profile:Score(now)),
		peak = round(profile.peak),
		fp = if Config.On("AltDetection") then self._behavior:Fingerprint(profile) else nil,
		age = profile.player.AccountAge,
	}
end

-- returns false only when the request actually failed
function BackendService:Sync()
	if self._syncing then
		return true
	end
	self._syncing = true

	local now = os.clock()
	local batch = self._batch:Drain()
	local players = batch.departed
	for _, profile in self._players:List() do
		if not profile.admin then
			table.insert(players, self:_snapshot(profile, now))
		end
	end

	local data = self:Post({
		op = "sync",
		server = self.ServerId,
		place = tostring(game.PlaceId),
		since = self._since,
		threat = self._threat:Level(),
		island = self._island:IsIsland(),
		players = players,
		flags = batch.flags,
		kicks = batch.kicks,
		acks = batch.acks,
		cmdAcks = self._commands:TakeAcks(),
	})
	self._syncing = false

	if not data then
		self._batch:Restore(batch)
		self.Online = false
		return false
	end

	self.Online = true
	if type(data.now) == "string" then
		self._since = data.now
	end
	Config.ApplyRemote(data.config)
	self._commands:Dispatch(data.commands)
	self.Synced:Fire(data)
	return true
end

function BackendService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._behavior = Framework.Get("ACBehaviorService")
	self._threat = Framework.Get("ACThreatService")
	self._island = Framework.Get("ACIslandService")
	self._commands = Framework.Get("ACCommandService")

	self._players.Removing:Connect(function(profile)
		if not profile.admin then
			self._batch:AddDeparted(self:_snapshot(profile, os.clock()))
		end
	end)

	if not self._key then
		warn("[AntiCheat] no backend key, running offline")
		return
	end

	task.spawn(function()
		local wait = B.SyncInterval
		while true do
			wait = if self:Sync() then B.SyncInterval else math.min(wait * 2, B.MaxBackoff)
			task.wait(wait)
		end
	end)

	game:BindToClose(function()
		-- studio stop shouldn't hang for long
		local deadline = os.clock() + (if RunService:IsStudio() then 5 else 25)
		while (self._inflight > 0 or self._syncing) and os.clock() < deadline do
			task.wait(0.1)
		end
		self:Sync()
	end)
end

return BackendService
