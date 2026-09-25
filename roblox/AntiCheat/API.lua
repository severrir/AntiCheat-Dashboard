--[[
	the only module your game code should require.

	local AntiCheat = require(game.ServerScriptService.AntiCheat.API)

	AntiCheat.Exempt(player, "Movement", 2)          -- before a legit teleport / knockback / dash
	AntiCheat.Exempt(player, "All", 5)

	local attack = AntiCheat.Remote.new("Attack", { Args = { "Instance:Model", "Vector3?" }, Rate = 8 })
	attack:Connect(function(player, target, dir) ... end)

	if AntiCheat.Combat.ValidateHit(player, target, { Range = 10, Cooldown = 0.5, Weapon = "Sword" }) then
		-- apply damage
	end

	AntiCheat.Stats.Record(player, "ReactionTime", 0.21, true) -- true = lower is suspicious
	AntiCheat.Flag(player, "Custom", 20, { note = "bought item with negative price" })
	AntiCheat.Flagged:Connect(function(player, check, amount, score, ctx) end)
]]

local Registry = require(script.Parent.Core.Registry)
local SignalBus = require(script.Parent.Core.SignalBus)
local TrustService = require(script.Parent.Core.TrustService)
local RemoteGuard = require(script.Parent.Checks.RemoteGuard)
local Combat = require(script.Parent.Checks.Combat)
local Statistical = require(script.Parent.Checks.Statistical)

local API = {
	Flagged = SignalBus.Flagged,
	Kicked = SignalBus.Kicked,
	Remote = { new = RemoteGuard.new },
	Combat = {
		ValidateHit = Combat.ValidateHit,
		RecordMiss = Combat.RecordMiss,
	},
	Stats = { Record = Statistical.Record },
}

local MAX_EXEMPT = 60

function API.Exempt(player, check, seconds)
	local profile = Registry.Get(player)
	if profile and type(check) == "string" and type(seconds) == "number" then
		profile:Exempt(check, math.clamp(seconds, 0, MAX_EXEMPT))
	end
end

function API.GetScore(player)
	local profile = Registry.Get(player)
	return profile and profile:Score() or 0
end

function API.Flag(player, check, severity, ctx)
	if type(check) ~= "string" or not string.match(check, "^%a+$") or #check > 24 then
		check = "Custom"
	end
	TrustService.Flag(player, check, severity, type(ctx) == "table" and ctx or nil)
end

return API
