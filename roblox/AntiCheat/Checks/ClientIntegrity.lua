local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Parent.Config)
local Registry = require(script.Parent.Parent.Core.Registry)
local TrustService = require(script.Parent.Parent.Core.TrustService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local T = Config.Thresholds

-- server half of the client detector. everything the client says can be faked,
-- so this is a low weight hint. the useful part: if the heartbeat stops, someone killed the script
local ClientIntegrity = { Name = "Client", Rate = "cold" }

local JOIN_GRACE = 30

local function onBeat(player, seq, report)
	local profile = Registry.Get(player)
	if not profile then
		return
	end
	local c = profile.client
	if seq <= c.seq then
		TrustService.Flag(profile, "Client", 8, { kind = "Replay", seq = seq, last = c.seq })
		return
	end
	c.seq = seq
	c.lastBeat = os.clock()

	if type(report) ~= "table" then
		return
	end

	-- a value the server just changed can still be in flight, so it has to be wrong twice in a row
	local strikes = c.strikes or {}
	c.strikes = strikes
	local function mismatch(kind, bad, ctx)
		if bad then
			strikes[kind] = (strikes[kind] or 0) + 1
			if strikes[kind] >= 2 then
				ctx.kind = kind
				TrustService.Flag(profile, "Client", 10, ctx)
			end
		else
			strikes[kind] = 0
		end
	end

	local hum = profile.humanoid
	if hum and hum.Parent and hum.Health > 0 then
		local ws = report.ws
		mismatch("LocalWalkSpeed", type(ws) == "number" and ws > hum.WalkSpeed + 0.5, { client = ws, server = hum.WalkSpeed })

		local jump = if hum.UseJumpPower then hum.JumpPower else hum.JumpHeight
		local reported = if hum.UseJumpPower then report.jp else report.jh
		mismatch("LocalJump", type(reported) == "number" and reported > jump + 0.5, { client = reported, server = jump })

		mismatch("LocalHumanoidGone", report.hum == false, {})
	end
	local g = report.g
	mismatch("LocalGravity", type(g) == "number" and g < workspace.Gravity - 1, { client = g, server = workspace.Gravity })
end

function ClientIntegrity.Init()
	-- random name each server, the client finds it by attribute
	local remote = RemoteGuard.new(string.sub(HttpService:GenerateGUID(false), 1, 8), {
		Args = { "integer", "table?" },
		-- roomy burst: after a server hitch the queued beats all land at once
		Rate = 1,
		Burst = 10,
		Parent = ReplicatedStorage,
	})
	remote.Instance:SetAttribute("ci", true)
	remote:Connect(onBeat)
end

function ClientIntegrity.Step(profile, now)
	if now - profile.joinedAt < JOIN_GRACE then
		return
	end
	if now - profile.client.lastBeat > T.HeartbeatTimeout then
		profile.client.lastBeat = now
		TrustService.Flag(profile, "Client", 12, { kind = "NoHeartbeat" })
	end
end

return ClientIntegrity
