local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Signal = require(AC.Lib.Signal)
local Framework = require(ReplicatedStorage.Shared.Framework)

local B = Config.Backend

-- the only thing that talks to supabase. batches flags, syncs every 20s, hands out what comes back
local Backend = {
	Name = "ACBackend",
	Synced = Signal.new(), -- (response)
	Online = false,
	ServerId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false),
}

local PlayerService, Behavior, Threat, Island, Commands

local pending, pendingCount = {}, 0
local kicks, acks, departed = {}, {}, {}
local since = nil
local syncing = false
local key

local function round(n, places)
	local m = 10 ^ places
	return math.floor(n * m + 0.5) / m
end

function Backend.Post(body)
	if not key then
		return nil
	end
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = B.Url,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
			["x-game-key"] = key,
		},
		Body = HttpService:JSONEncode(body),
	})
	if not ok or not res.Success then
		return nil
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	return if decoded then data else nil
end

function Backend.QueueFlag(profile, check, raw, amount, score, ctx, pos)
	local k = profile.userId .. check
	local entry = pending[k]
	if entry then
		entry.sev += amount
		entry.raw += raw
		entry.hits += 1
		entry.score = score
		if amount >= entry.top then
			entry.top = amount
			entry.ctx = ctx
			entry.pos = entry.pos or (pos and { round(pos.X, 1), round(pos.Y, 1), round(pos.Z, 1) })
		end
		return
	end
	if pendingCount >= B.MaxQueue then
		return
	end
	pendingCount += 1
	pending[k] = {
		id = tostring(profile.userId),
		check = check,
		sev = amount,
		raw = raw,
		top = amount,
		score = score,
		hits = 1,
		ctx = ctx,
		pos = pos and { round(pos.X, 1), round(pos.Y, 1), round(pos.Z, 1) },
	}
end

function Backend.QueueKick(profile, reason, score, replayId, sig)
	table.insert(kicks, {
		id = tostring(profile.userId),
		name = profile.player.Name,
		reason = reason,
		score = score,
		replay = replayId,
		sig = sig,
	})
end

function Backend.Ack(userId, active)
	table.insert(acks, { id = tostring(userId), active = active })
end

local function snapshot(profile, now)
	local fp = if Config.On("AltDetection") then Behavior.Vector(profile) else nil
	return {
		id = tostring(profile.userId),
		name = profile.player.Name,
		score = round(profile:Score(now), 1),
		peak = round(profile.peak, 1),
		fp = fp,
		age = profile.player.AccountAge,
	}
end

function Backend.NoteLeft(profile)
	if not profile.admin then
		table.insert(departed, snapshot(profile, os.clock()))
	end
end

-- returns false only when the request actually failed
function Backend.Sync()
	if syncing then
		return true
	end
	syncing = true

	local now = os.clock()
	local players = departed
	departed = {}
	for _, profile in PlayerService.List() do
		if not profile.admin then
			table.insert(players, snapshot(profile, now))
		end
	end

	local flags = {}
	for _, entry in pending do
		entry.top = nil
		table.insert(flags, entry)
	end
	local sentKicks, sentAcks = kicks, acks
	pending, pendingCount, kicks, acks = {}, 0, {}, {}

	local data = Backend.Post({
		op = "sync",
		server = Backend.ServerId,
		place = tostring(game.PlaceId),
		since = since,
		threat = Threat.Level(),
		island = Island.IsIsland(),
		players = players,
		flags = flags,
		kicks = sentKicks,
		acks = sentAcks,
		cmdAcks = Commands.TakeAcks(),
	})
	syncing = false

	if not data then
		-- a blip shouldn't lose kicks or acks. flags can go, they're capped anyway
		table.move(sentKicks, 1, #sentKicks, #kicks + 1, kicks)
		table.move(sentAcks, 1, #sentAcks, #acks + 1, acks)
		Backend.Online = false
		return false
	end

	Backend.Online = true
	if type(data.now) == "string" then
		since = data.now
	end
	Config.ApplyRemote(data.config)
	Commands.Dispatch(data.commands)
	Backend.Synced:Fire(data)
	return true
end

function Backend.CheckJoin(userId)
	return Backend.Post({ op = "join", id = tostring(userId) })
end

function Backend:Init()
	-- the experience secret store in live servers, the server-only module in studio
	-- (studio has no secrets and its debugger pauses on the error even inside pcall)
	if not RunService:IsStudio() then
		local ok, secret = pcall(HttpService.GetSecret, HttpService, B.SecretName)
		if ok then
			key = secret
		end
	end
	if not key then
		local found = AC:FindFirstChild("ServerKey")
		key = found and require(found)
	end
end

function Backend:Start()
	PlayerService = Framework.Get("ACPlayers")
	Behavior = Framework.Get("ACBehavior")
	Threat = Framework.Get("ACThreat")
	Island = Framework.Get("ACIsland")
	Commands = Framework.Get("ACCommands")

	PlayerService.Removing:Connect(Backend.NoteLeft)

	if not key then
		warn("[AntiCheat] no backend key, running offline")
		return
	end

	task.spawn(function()
		local wait = B.SyncInterval
		while true do
			wait = if Backend.Sync() then B.SyncInterval else math.min(wait * 2, B.MaxBackoff)
			task.wait(wait)
		end
	end)

	game:BindToClose(function()
		if not RunService:IsStudio() then
			Backend.Sync()
		end
	end)
end

return Backend
