local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Check = require(AC.Classes.Check)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

local T = Config.Thresholds

-- server half of the client detector (ACHeartbeatController). anything a client says can be faked,
-- so this is a low weight hint. the useful part: if the heartbeat stops, someone killed the script
local ClientCheckService = Check.extend({
	Name = "ACClientCheckService",
	Category = "Client",
	Feature = "Client",
	Rate = "cold",
})

local JOIN_GRACE = 30

function ClientCheckService:Init()
	-- client beats every 5s, the cooldown only stops floods
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
	if seq <= c.seq or seq % 1 ~= 0 then
		self:Flag(profile, 8, { kind = "Replay", seq = seq, last = c.seq })
		return
	end
	c.seq = seq
	c.lastBeat = os.clock()

	-- a value the server just changed can still be in flight, so it has to be wrong twice in a row
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
		mismatch("LocalWalkSpeed", type(ws) == "number" and ws > hum.WalkSpeed + 0.5, { client = ws, server = hum.WalkSpeed })

		-- launch speed, so flipping UseJumpPower on the client doesn't hide a boost
		local jump = if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
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
