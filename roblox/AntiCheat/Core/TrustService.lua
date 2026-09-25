local Config = require(script.Parent.Parent.Config)
local Registry = require(script.Parent.Registry)
local SignalBus = require(script.Parent.SignalBus)
local Backend = require(script.Parent.Parent.Net.Backend)
local Enforcement = require(script.Parent.Parent.Response.Enforcement)

local T = Config.Thresholds

local TrustService = {}

-- every check reports through here. checks never kick anyone themselves
function TrustService.Flag(target, check, severity, ctx)
	local profile = typeof(target) == "Instance" and Registry.Get(target) or target
	if not profile or profile.admin or profile.kicked then
		return
	end
	local now = os.clock()
	if profile:IsExempt(check, now) then
		return
	end
	if type(severity) ~= "number" or severity ~= severity or severity <= 0 then
		return
	end

	local amount = math.min(severity, 500) * (T["Weight" .. check] or 1)
	if amount <= 0 then
		return
	end
	local score = profile:AddScore(check, amount, now)

	SignalBus.Flagged:Fire(profile.player, check, amount, score, ctx)
	Backend.QueueFlag(profile, check, amount, score, ctx)
	Enforcement.Evaluate(profile, now)
end

return TrustService
