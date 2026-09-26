local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

local T = Config.Thresholds

-- plugs into Net.Middleware / Net.OnReject so every remote in the game is watched without
-- touching game code: spam past the cooldown, wrong argument types, macro timing,
-- honeypot tokens sent back
local NetGuardService = { Name = "ACNetGuardService" }

local SPAM_PER_SECOND = 10
local MAX_TABLE_SCAN = 32

function NetGuardService:_scan(player, value, depth)
	local kind = type(value)
	if kind == "string" then
		return self._honeypot:Scan(player, value)
	elseif kind == "table" and depth < 2 then
		local n = 0
		for _, v in value do
			n += 1
			if n > MAX_TABLE_SCAN then
				break
			end
			if self:_scan(player, v, depth + 1) then
				return true
			end
		end
	end
	return false
end

function NetGuardService:_middleware(player, name, ...)
	if not Config.On("NetGuard") then
		return true
	end
	local profile = self._players:Get(player)
	if not profile then
		return true
	end
	profile.netCalls += 1
	if Config.On("Timing") then
		self._timing:Record(profile, name, os.clock())
	end
	for i = 1, select("#", ...) do
		if self:_scan(player, (select(i, ...)), 0) then
			return false
		end
	end
	return true
end

function NetGuardService:_onReject(player, name, reason)
	if not Config.On("NetGuard") then
		return
	end
	local profile = self._players:Get(player)
	if not profile then
		return
	end
	if reason == "types" then
		self._trust:Flag(profile, "Remote", 5, { kind = "BadArgs", remote = name })
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
		self._trust:Flag(profile, "Remote", 8, { kind = "Spam", remote = name })
	end
end

function NetGuardService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._trust = Framework.Get("ACTrustService")
	self._timing = Framework.Get("ACTimingService")
	self._honeypot = Framework.Get("ACHoneypotService")

	-- your game might already use the hooks, chain onto them instead of replacing
	local prevMiddleware, prevReject = Net.Middleware, Net.OnReject
	if prevMiddleware or prevReject then
		warn("[AntiCheat] Net hooks were already set, NetGuard is chaining onto them")
	end
	Net.Middleware = function(player, name, ...)
		if prevMiddleware and prevMiddleware(player, name, ...) == false then
			return false
		end
		return self:_middleware(player, name, ...)
	end
	Net.OnReject = function(player, name, reason)
		if prevReject then
			prevReject(player, name, reason)
		end
		self:_onReject(player, name, reason)
	end
end

return NetGuardService
