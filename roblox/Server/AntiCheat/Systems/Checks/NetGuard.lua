local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

local T = Config.Thresholds

-- plugs into Net so every remote in the game is watched without touching game code:
-- spam past the cooldown, wrong argument types, macro timing, honeypot tokens sent back
local NetGuard = { Name = "ACNetGuard" }

local SPAM_PER_SECOND = 10
local MAX_TABLE_SCAN = 32

local PlayerService, Trust, Timing, Honeypot

local function scan(player, value, depth)
	local kind = type(value)
	if kind == "string" then
		return Honeypot.Scan(player, value)
	elseif kind == "table" and depth < 2 then
		local n = 0
		for _, v in value do
			n += 1
			if n > MAX_TABLE_SCAN then
				break
			end
			if scan(player, v, depth + 1) then
				return true
			end
		end
	end
	return false
end

local function middleware(player, name, ...)
	if not Config.On("NetGuard") then
		return true
	end
	local profile = PlayerService.Get(player)
	if not profile then
		return true
	end
	profile.netCalls += 1
	if Config.On("Timing") then
		Timing.Record(profile, name, os.clock())
	end
	for i = 1, select("#", ...) do
		if scan(player, (select(i, ...)), 0) then
			return false
		end
	end
	return true
end

local function onReject(player, name, reason)
	if not Config.On("NetGuard") then
		return
	end
	local profile = PlayerService.Get(player)
	if not profile then
		return
	end
	if reason == "types" then
		Trust.Flag(profile, "Remote", 5, { kind = "BadArgs", remote = name })
		return
	end
	-- a few calls inside the cooldown is just someone clicking fast. a flood isn't
	local now = os.clock()
	local r = profile.rejects
	if now - r.at > 1 then
		r.count, r.at = 0, now
	end
	r.count += 1
	if r.count > SPAM_PER_SECOND * T.RemoteBurstMultiplier then
		r.count = 0
		Trust.Flag(profile, "Remote", 8, { kind = "Spam", remote = name })
	end
end

function NetGuard:Start()
	PlayerService = Framework.Get("ACPlayers")
	Trust = Framework.Get("ACTrust")
	Timing = Framework.Get("ACTiming")
	Honeypot = Framework.Get("ACHoneypot")

	if Net.Middleware or Net.OnReject then
		warn("[AntiCheat] something else already set Net hooks, NetGuard is chaining onto them")
	end
	local prevMiddleware, prevReject = Net.Middleware, Net.OnReject
	Net.Middleware = function(player, name, ...)
		if prevMiddleware and prevMiddleware(player, name, ...) == false then
			return false
		end
		return middleware(player, name, ...)
	end
	Net.OnReject = function(player, name, reason)
		if prevReject then
			prevReject(player, name, reason)
		end
		onReject(player, name, reason)
	end
end

return NetGuard
