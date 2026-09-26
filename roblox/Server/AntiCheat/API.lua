local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage.Shared.Framework)

local API = {}

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

function API.IsBait(model)
	return service("ACBaitNpcService"):IsBait(model)
end

return API
