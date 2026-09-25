--[[
	the only module your game code needs.

	local AntiCheat = require(game.ServerScriptService.AntiCheat.API)

	AntiCheat.Exempt(player, "Movement", 2)   -- before a legit teleport / knockback / dash
	AntiCheat.Exempt(player, "Character", 3)  -- before morphs or scaling
	AntiCheat.Exempt(player, "All", 5)

	-- your Net remotes are already watched (spam, bad args, macros, honeypot tokens).
	-- for hits, ask before applying damage:
	if AntiCheat.ValidateHit(player, target, { Range = 10, Cooldown = 0.5, Weapon = "Sword" }) then
		-- damage
	end
	AntiCheat.RecordMiss(player)                        -- swung at nothing

	AntiCheat.RecordStat(player, "ReactionTime", 0.21, true) -- true = lower is suspicious
	AntiCheat.Flag(player, "Custom", 20, { note = "bought item with negative price" })
	AntiCheat.OnFlagged(function(player, check, amount, score, ctx) end)
	AntiCheat.OnKicked(function(player, reason, score) end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage.Shared.Framework)

local API = {}

-- looked up on every call so this module can be required before the framework boots
local function sys(name)
	return Framework.Get(name)
end

function API.Exempt(player, check, seconds)
	local profile = sys("ACPlayers").Get(player)
	if profile and type(check) == "string" and type(seconds) == "number" then
		profile:Exempt(check, math.clamp(seconds, 0, 60))
	end
end

function API.GetScore(player)
	local profile = sys("ACPlayers").Get(player)
	return if profile then profile:Score() else 0
end

function API.Flag(player, check, severity, ctx)
	if type(check) ~= "string" or not string.match(check, "^%a+$") or #check > 24 then
		check = "Custom"
	end
	sys("ACTrust").Flag(player, check, severity, if type(ctx) == "table" then ctx else nil)
end

function API.ValidateHit(attacker, victim, opts)
	return sys("ACCombat").ValidateHit(attacker, victim, opts)
end

function API.RecordMiss(attacker)
	sys("ACCombat").RecordMiss(attacker)
end

function API.RecordStat(player, name, value, lowerIsSuspicious)
	sys("ACStatistical").Record(player, name, value, lowerIsSuspicious)
end

function API.OnFlagged(fn)
	return sys("ACTrust").Flagged:Connect(fn)
end

function API.OnKicked(fn)
	return sys("ACEnforcement").Kicked:Connect(fn)
end

function API.IsBait(model)
	return sys("ACBaitNPC").IsBait(model)
end

return API
