local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage.Shared.Framework)

-- how someone plays, boiled down to 8 numbers. used to spot a banned player's new account.
-- reads the movement history the movement check already records, so it costs almost nothing
local Behavior = { Name = "ACBehavior", Feature = "AltDetection", Rate = "cold" }

local MIN_SAMPLES = 600 -- a minute of play before we trust the numbers
local MOVING = 2 -- studs/s

local function fresh()
	return {
		lastT = 0,
		samples = 0, moving = 0, air = 0,
		ratioSum = 0, jumps = 0, turns = 0, stopGo = 0,
		straightSum = 0, straightN = 0,
		time = 0, wasMoving = false, wasGrounded = true,
		windowPath = 0, windowStart = nil, windowTime = 0,
	}
end

function Behavior.Step(profile)
	local b = profile.behavior
	if not b then
		b = fresh()
		profile.behavior = b
	end

	-- walk the samples recorded since last time, oldest first
	local times = profile.times
	local newest = 0
	for i = 1, times.count do
		if times:Get(i) <= b.lastT then
			break
		end
		newest = i
	end
	if newest < 2 then
		return
	end

	for i = newest, 2, -1 do
		local dt = times:Get(i - 1) - times:Get(i)
		if dt > 0 and dt < 1 then
			local dx = profile.xs:Get(i - 1) - profile.xs:Get(i)
			local dz = profile.zs:Get(i - 1) - profile.zs:Get(i)
			local dist = math.sqrt(dx * dx + dz * dz)
			local speed = dist / dt
			local allowed = math.abs(profile.allowed:Get(i - 1))
			local walk = math.max((allowed - 4) / 1.35, 1)
			local grounded = profile.grounds:Get(i - 1) == 1
			local moving = speed > MOVING

			b.samples += 1
			b.time += dt
			if moving then
				b.moving += 1
				b.ratioSum += speed / walk
			end
			if not grounded then
				b.air += 1
			end
			if b.wasGrounded and not grounded then
				b.jumps += 1
			end
			if moving ~= b.wasMoving then
				b.stopGo += 1
			end
			local dyaw = math.abs(profile.yaws:Get(i - 1) - profile.yaws:Get(i))
			if dyaw > math.pi then
				dyaw = 2 * math.pi - dyaw
			end
			b.turns += dyaw

			-- straightness over 2s windows: how far you got vs how far you walked
			if not b.windowStart then
				b.windowStart = { profile.xs:Get(i), profile.zs:Get(i) }
			end
			b.windowPath += dist
			b.windowTime += dt
			if b.windowTime >= 2 then
				if b.windowPath > 4 then
					local ex = profile.xs:Get(i - 1) - b.windowStart[1]
					local ez = profile.zs:Get(i - 1) - b.windowStart[2]
					b.straightSum += math.sqrt(ex * ex + ez * ez) / b.windowPath
					b.straightN += 1
				end
				b.windowStart, b.windowPath, b.windowTime = nil, 0, 0
			end

			b.wasMoving, b.wasGrounded = moving, grounded
		end
	end
	b.lastT = times:Get(1)
end

-- nil until there's enough play to be meaningful
function Behavior.Vector(profile)
	local b = profile.behavior
	if not b or b.samples < MIN_SAMPLES or b.time <= 0 then
		return nil
	end
	local minutes = b.time / 60
	local function r(n)
		return math.floor(n * 1000 + 0.5) / 1000
	end
	return {
		r(if b.moving > 0 then b.ratioSum / b.moving else 0), -- how close to full speed they walk
		r(b.moving / b.samples), -- how much of the time they're moving
		r(b.air / b.samples), -- how much of the time they're airborne
		r(b.jumps / minutes), -- jumps per minute
		r(b.turns / b.time), -- how fast they turn, rad/s
		r(if b.straightN > 0 then b.straightSum / b.straightN else 0), -- straight lines vs wandering
		r(b.stopGo / minutes), -- start/stop rhythm
		r(profile.netCalls / minutes), -- remote calls per minute
	}
end

function Behavior:Start()
	Framework.Get("ACScheduler").Add(Behavior)
end

return Behavior
