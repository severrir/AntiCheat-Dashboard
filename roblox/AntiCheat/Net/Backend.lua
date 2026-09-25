local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Config)
local Registry = require(script.Parent.Parent.Core.Registry)
local Signal = require(script.Parent.Parent.Core.Signal)

local B = Config.Backend

local Backend = {
	Synced = Signal.new(), -- (response)
	Online = false,
}

local serverId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
local pending = {}
local pendingCount = 0
local kicks = {}
local acks = {}
local departed = {}
local since = nil
local syncing = false

-- prefer the experience secret store, fall back to the server-only module for studio
-- (studio has no secrets and its debugger pauses on the error even inside pcall, so skip it there)
local key
do
	if not RunService:IsStudio() then
		local ok, secret = pcall(HttpService.GetSecret, HttpService, B.SecretName)
		if ok then
			key = secret
		end
	end
	if not key then
		local found = script.Parent.Parent:FindFirstChild("ServerKey")
		key = found and require(found)
	end
end

local function post(body)
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
	if not ok then
		return nil, res
	end
	if not res.Success then
		return nil, res.StatusCode
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	return decoded and data or nil
end

function Backend.QueueFlag(profile, check, amount, score, ctx)
	local k = profile.userId .. check
	local entry = pending[k]
	if entry then
		entry.sev += amount
		entry.hits += 1
		entry.score = score
		if amount >= entry.top then
			entry.top = amount
			entry.ctx = ctx
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
		top = amount,
		score = score,
		hits = 1,
		ctx = ctx,
	}
end

function Backend.QueueKick(profile, reason, score)
	table.insert(kicks, {
		id = tostring(profile.userId),
		name = profile.player.Name,
		reason = reason,
		score = score,
	})
end

function Backend.Ack(userId, active)
	table.insert(acks, { id = tostring(userId), active = active })
end

local function snapshot(profile, now)
	return {
		id = tostring(profile.userId),
		name = profile.player.Name,
		score = math.floor(profile:Score(now) * 10) / 10,
		peak = math.floor(profile.peak * 10) / 10,
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
	for _, profile in Registry.List() do
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

	local data = post({
		op = "sync",
		server = serverId,
		since = since,
		players = players,
		flags = flags,
		kicks = sentKicks,
		acks = sentAcks,
	})
	syncing = false

	if not data then
		-- put things back so a blip doesn't lose kicks/acks. flags can go, they're capped anyway
		for _, k in sentKicks do
			table.insert(kicks, k)
		end
		for _, a in sentAcks do
			table.insert(acks, a)
		end
		Backend.Online = false
		return false
	end

	Backend.Online = true
	if type(data.now) == "string" then
		since = data.now
	end
	Config.ApplyRemote(data.config)
	Backend.Synced:Fire(data)
	return true
end

function Backend.CheckJoin(userId)
	return post({ op = "join", id = tostring(userId) })
end

function Backend.Start()
	if not key then
		warn("[AntiCheat] no backend key, running offline")
		return
	end
	task.spawn(function()
		local wait = B.SyncInterval
		while true do
			if Backend.Sync() then
				wait = B.SyncInterval
			else
				wait = math.min(wait * 2, B.MaxBackoff)
			end
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
