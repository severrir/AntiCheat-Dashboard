local Config = require(script.Parent.Parent.Config)
local Physics = require(script.Parent.Parent.Core.Physics)
local TrustService = require(script.Parent.Parent.Core.TrustService)

local T = Config.Thresholds
local State = Enum.HumanoidStateType

local Movement = { Name = "Movement", Rate = "hot" }

-- how many seconds of "standing still" you can bank for lag catch-up
local CREDIT_SECONDS = 0.6
local BUDGET_LIMIT = 12
local DOWN = Vector3.new(0, -1, 0)

local function newState(root, now)
	return {
		lastPos = root.Position,
		lastT = now,
		lastValid = root.CFrame,
		lastGrounded = root.CFrame,
		budget = 0,
		air = 0,
		snapped = false,
	}
end

local function snapBack(profile, m, target, now)
	local root = profile.root
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = target
	m.lastPos = target.Position
	m.lastT = now
	m.budget = 0
	m.air = 0
	m.snapped = true
	profile.moveViolations:Push(now)
end

local function record(profile, now, pos, allowed, snapped)
	profile.times:Push(now)
	profile.positions:Push(pos)
	profile.allowed:Push(if snapped then -allowed else allowed)
end

function Movement.Step(profile, now)
	if not profile:Alive() then
		return
	end
	local root, hum = profile.root, profile.humanoid
	local m = profile.move
	if not m then
		profile.move = newState(root, now)
		return
	end

	local pos = root.Position
	local dt = now - m.lastT

	-- vehicles, exemptions and server hiccups: just follow along
	if hum.SeatPart or profile:IsExempt("Movement", now) or dt > 1 then
		profile.move = newState(root, now)
		return
	end
	if dt <= 0 then
		return
	end

	local delta = pos - m.lastPos
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local state = hum:GetState()

	-- standing on something moving? add its speed
	local ground = Physics.Cast(pos, DOWN * (hum.HipHeight + T.FlyHeight + 3))
	local platform = 0
	if ground then
		local v = ground.Instance.AssemblyLinearVelocity
		platform = Vector3.new(v.X, 0, v.Z).Magnitude
	end

	local allowed = hum.WalkSpeed * T.SpeedMargin + 4 + platform
	local wasSnapped = m.snapped
	m.snapped = false

	-- speed + teleport share one leaky bucket, so lag spikes that catch up don't count
	m.budget = math.max(m.budget + horizontal - allowed * dt, -allowed * CREDIT_SECONDS)
	if m.budget > BUDGET_LIMIT then
		local dist = delta.Magnitude
		record(profile, now, pos, allowed, wasSnapped)
		local teleport = dist > T.TeleportDistance
		TrustService.Flag(profile, "Movement", teleport and 35 or math.clamp(m.budget, 10, 30), {
			kind = teleport and "Teleport" or "Speed",
			speed = horizontal / dt,
			allowed = allowed,
			dist = dist,
		})
		snapBack(profile, m, m.lastValid, now)
		return
	end

	-- flying: far off the ground and not falling for too long
	local climbing = state == State.Climbing or state == State.Swimming
	if not ground and not climbing then
		if delta.Y / dt > -8 then
			m.air += dt
		else
			m.air = math.max(0, m.air - dt)
		end
		if m.air > T.FlyTime then
			record(profile, now, pos, allowed, wasSnapped)
			TrustService.Flag(profile, "Movement", 25, { kind = "Fly", air = m.air, y = pos.Y })
			snapBack(profile, m, m.lastGrounded, now)
			return
		end
	else
		m.air = 0
	end

	-- noclip: something solid between last spot and this one, checked both ways
	if horizontal > 1.5 then
		local forward = Physics.Cast(m.lastPos, delta)
		if forward then
			local back = Physics.Cast(pos, -delta)
			if back and back.Instance == forward.Instance then
				record(profile, now, pos, allowed, wasSnapped)
				TrustService.Flag(profile, "Movement", 20, { kind = "Noclip", part = forward.Instance.Name })
				snapBack(profile, m, m.lastValid, now)
				return
			end
		end
	end

	record(profile, now, pos, allowed, wasSnapped)
	m.lastPos = pos
	m.lastT = now
	-- only trust spots where they weren't already running on borrowed speed,
	-- otherwise a snapback just moves them one step back
	if m.budget <= 0 then
		m.lastValid = root.CFrame
		if ground or climbing then
			m.lastGrounded = root.CFrame
		end
	end
end

return Movement
