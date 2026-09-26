local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Signal = require(AC.Classes.Core.Signal)
local Framework = require(ReplicatedStorage.Shared.Framework)

local T = Config.Thresholds

local TrustService = {
	Name = "ACTrustService",
	Flagged = Signal.new(),
}

local function detailOf(ctx)
	if type(ctx) ~= "table" then
		return nil
	end
	if type(ctx.speed) == "number" and type(ctx.allowed) == "number" and ctx.allowed > 0 then
		local ratio = ctx.speed / ctx.allowed
		if ratio >= 10 then
			return "x10+"
		end
		return string.format("x%.1f", math.floor(ratio * 2) / 2)
	end
	if type(ctx.client) == "number" then
		return string.format("=%d", math.floor(ctx.client / 5) * 5)
	end
	if type(ctx.remote) == "string" then
		return ctx.remote
	end
	return nil
end

function TrustService:Flag(target, check, severity, ctx)
	local profile = if typeof(target) == "Instance" then self._players:Get(target) else target
	if not profile or profile.immune or profile.kicked then
		return
	end
	local now = os.clock()
	if profile:IsExempt(check, now) then
		return
	end
	if type(severity) ~= "number" or severity ~= severity or severity <= 0 then
		return
	end

	local raw = math.min(severity, 500)
	local amount = raw * (T["Weight" .. check] or 1)
	if amount <= 0 then
		return
	end
	local score = profile:AddScore(check, amount, now)
	local kind = if type(ctx) == "table" then ctx.kind else nil
	profile:Event(now, check, kind, detailOf(ctx))

	self.Flagged:Fire(profile.player, check, amount, score, ctx)
	self._backend:QueueFlag(profile, check, raw, amount, score, ctx, profile:Position())
	self._enforcement:Evaluate(profile, now)
end

function TrustService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._backend = Framework.Get("ACBackendService")
	self._enforcement = Framework.Get("ACEnforcementService")
end

return TrustService
