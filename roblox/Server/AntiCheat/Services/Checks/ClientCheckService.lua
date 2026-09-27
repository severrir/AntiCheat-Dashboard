local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Check = require(AC.Classes.Core.Check)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

local T = Config.Thresholds

local ClientCheckService = Check.extend({
	Name = "ACClientCheckService",
	Category = "Client",
	Feature = "Client",
	Rate = "cold",
})

local JOIN_GRACE = 30

function ClientCheckService:Init()
	self.Beat = Net.Event({ name = "ACBeat", cooldown = 1 }):Expect("number", "table")
end

function ClientCheckService:OnStart()
	self._players = Framework.Get("ACPlayerService")
	self.Beat:Listen(function(player, seq, report)
		self:_onBeat(player, seq, report)
	end)
end

function ClientCheckService:_onBeat(player, seq, report)
	local profile = self._players:Get(player)
	if not profile or not self:IsEnabled() then
		return
	end
	local c = profile.client
	if seq ~= seq or math.abs(seq) == math.huge then
		self:Flag(profile, 8, { kind = "Replay" })
		return
	end
	for _, key in { "ws", "jv", "g" } do
		local v = report[key]
		if type(v) == "number" and (v ~= v or math.abs(v) == math.huge) then
			report[key] = nil
		end
	end
	if seq <= c.seq or seq % 1 ~= 0 then
		self:Flag(profile, 8, { kind = "Replay", seq = seq, last = c.seq })
		return
	end
	c.seq = seq
	c.lastBeat = os.clock()

	local strikes = c.strikes
	local function mismatch(kind, bad, ctx)
		if bad then
			strikes[kind] = (strikes[kind] or 0) + 1
			if strikes[kind] >= 2 then
				ctx.kind = kind
				self:Flag(profile, 10, ctx)
			end
		else
			strikes[kind] = 0
		end
	end

	local hum = profile.humanoid
	if hum and hum.Parent and hum.Health > 0 then
		local ws = report.ws
		local speed = math.max(hum.WalkSpeed, profile:Allowed("Speed") or 0, profile:Allowed("Fly") or 0)
		mismatch("LocalWalkSpeed", type(ws) == "number" and ws > speed + 0.5, { client = ws, server = speed })

		local jump = if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
		jump = math.max(jump, profile:Allowed("Jump") or 0)
		local reported = report.jv
		mismatch("LocalJump", type(reported) == "number" and reported > jump + 1, { client = reported, server = jump })

		mismatch("LocalHumanoidGone", report.hum == false, {})
	end
	local g = report.g
	mismatch("LocalGravity", type(g) == "number" and g < workspace.Gravity - 1, { client = g, server = workspace.Gravity })
end

function ClientCheckService:Step(profile, now)
	if now - profile.joinedAt < JOIN_GRACE then
		return
	end
	if now - profile.client.lastBeat > T.HeartbeatTimeout then
		profile.client.lastBeat = now
		self:Flag(profile, 12, { kind = "NoHeartbeat" })
	end
end

return ClientCheckService
