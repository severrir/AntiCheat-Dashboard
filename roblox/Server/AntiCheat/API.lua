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

	-- shadow mode: suspects stay in, hits stop landing and earnings are held
	AntiCheat.IsShadowed(player)
	AntiCheat.Shadow(player, true)                      -- or false to lift it

	-- what players gain, so a ban can undo it. ask before giving:
	coins += AntiCheat.Grant(player, "Coins", 100, "quest")  -- 0 while shadowed
	if AntiCheat.GrantItem(player, "Golden Sword", "shop") then giveSword() end
	AntiCheat.RecordKill(killer, victim)
	AntiCheat.Transfer(fromPlayer, toPlayer, "Coins", 250)      -- trades, steals. item: amount = nil
	AntiCheat.OnRevert(function(userId, summary) return takeBack(userId, summary) end) -- your DataStore code

	-- player reports, if you'd rather use your own report ui (set Config.ReportButton = false)
	local ok, message = AntiCheat.Report(reporter, targetPlayer, "Flying", "optional note")

	inside your own Framework services you can also just Framework.Get("ACCombatService") etc.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage.Shared.Framework)

local API = {}

-- looked up on every call so this module can be required before the framework boots
local function service(name)
	return Framework.Get(name)
end

function API.Exempt(player, check, seconds)
	local profile = service("ACPlayerService"):Get(player)
	if profile and type(check) == "string" and type(seconds) == "number" then
		profile:Exempt(check, math.clamp(seconds, 0, 60))
	end
end

function API.GetScore(player)
	local profile = service("ACPlayerService"):Get(player)
	return if profile then profile:Score() else 0
end

function API.Flag(player, check, severity, ctx)
	if type(check) ~= "string" or not string.match(check, "^%a+$") or #check > 24 then
		check = "Custom"
	end
	service("ACTrustService"):Flag(player, check, severity, if type(ctx) == "table" then ctx else nil)
end

function API.ValidateHit(attacker, victim, opts)
	return service("ACCombatService"):ValidateHit(attacker, victim, opts)
end

function API.RecordMiss(attacker)
	service("ACCombatService"):RecordMiss(attacker)
end

function API.RecordStat(player, name, value, lowerIsSuspicious)
	service("ACStatsService"):Record(player, name, value, lowerIsSuspicious)
end

function API.OnFlagged(fn)
	return service("ACTrustService").Flagged:Connect(fn)
end

function API.OnKicked(fn)
	return service("ACEnforcementService").Kicked:Connect(fn)
end

function API.IsShadowed(player)
	return service("ACShadowService"):IsShadowed(player)
end

function API.Shadow(player, on)
	local profile = service("ACPlayerService"):Get(player)
	if not profile then
		return
	end
	if on == false then
		service("ACShadowService"):Clear(profile)
	else
		service("ACShadowService"):Set(profile, "staff", "from game code")
	end
end

function API.Grant(player, key, amount, source)
	return service("ACLedgerService"):Grant(player, key, amount, source)
end

function API.GrantItem(player, item, source)
	return service("ACLedgerService"):GrantItem(player, item, source)
end

function API.RecordKill(killer, victim)
	service("ACLedgerService"):RecordKill(killer, victim)
end

function API.Transfer(from, to, what, amount)
	service("ACLedgerService"):Transfer(from, to, what, amount)
end

function API.OnRevert(fn)
	service("ACRevertService"):OnRevert(fn)
end

function API.Report(reporter, target, reason, note)
	return service("ACReportService"):Report(reporter, target, reason, note)
end

-- true for the invisible bait dummies, skip them in your own npc / targeting code
function API.IsBait(model)
	return service("ACBaitNpcService"):IsBait(model)
end

return API
