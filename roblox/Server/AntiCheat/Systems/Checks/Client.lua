local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

local T = Config.Thresholds

-- server half of the client detector. anything a client says can be faked, so this is a
-- low weight hint. the useful part: if the heartbeat stops, someone killed the script
local Client = { Name = "ACClient", Feature = "Client", Rate = "cold" }

local JOIN_GRACE = 30

local PlayerService, Trust

local function onBeat(player, seq, report)
	local profile = PlayerService.Get(player)
	if not profile or not Config.On("Client") then
		return
	end
	local c = profile.client
	if seq <= c.seq or seq % 1 ~= 0 then
		Trust.Flag(profile, "Client", 8, { kind = "Replay", seq = seq, last = c.seq })
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
				Trust.Flag(profile, "Client", 10, ctx)
			end
		else
			strikes[kind] = 0
		end
	end

	local hum = profile.humanoid
	if hum and hum.Parent and hum.Health > 0 then
		local ws = report.ws
		mismatch("LocalWalkSpeed", type(ws) == "number" and ws > hum.WalkSpeed + 0.5, { client = ws, server = hum.WalkSpeed })

		local jump = if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
		local reported = report.jv
		mismatch("LocalJump", type(reported) == "number" and reported > jump + 1, { client = reported, server = jump })

		mismatch("LocalHumanoidGone", report.hum == false, {})
	end
	local g = report.g
	mismatch("LocalGravity", type(g) == "number" and g < workspace.Gravity - 1, { client = g, server = workspace.Gravity })
end

function Client.Step(profile, now)
	if now - profile.joinedAt < JOIN_GRACE then
		return
	end
	if now - profile.client.lastBeat > T.HeartbeatTimeout then
		profile.client.lastBeat = now
		Trust.Flag(profile, "Client", 12, { kind = "NoHeartbeat" })
	end
end

function Client:Start()
	PlayerService = Framework.Get("ACPlayers")
	Trust = Framework.Get("ACTrust")
	Framework.Get("ACScheduler").Add(Client)

	-- client beats every 5s, the cooldown only stops floods
	Net.Event({ name = "ACBeat", cooldown = 1 }):Expect("number", "table"):Listen(onBeat)
end

return Client
