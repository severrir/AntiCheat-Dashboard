-- how someone plays, boiled down to 8 numbers. used to spot a banned player's new account.
-- reads the movement history the movement check already records, so it costs almost nothing
local PlayStyle = {}
PlayStyle.__index = PlayStyle

local MIN_SAMPLES = 600 -- a minute of play before we trust the numbers
local MOVING = 2 -- studs/s

function PlayStyle.new()
	return setmetatable({
		lastT = 0,
		samples = 0, moving = 0, air = 0,
		ratioSum = 0, jumps = 0, turns = 0, stopGo = 0,
		straightSum = 0, straightN = 0,
		time = 0, wasMoving = false, wasGrounded = true,
		windowPath = 0, windowStart = nil, windowTime = 0,
	}, PlayStyle)
end

-- walks the samples recorded since last time, oldest first
function PlayStyle:Consume(profile)
	local times = profile.times
	local newest = 0
	for i = 1, times.count do
		if times:Get(i) <= self.lastT then
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
			self:_sample(profile, i, dt)
		end
	end
	self.lastT = times:Get(1)
end

function PlayStyle:_sample(profile, i, dt)
	local dx = profile.xs:Get(i - 1) - profile.xs:Get(i)
	local dz = profile.zs:Get(i - 1) - profile.zs:Get(i)
	local dist = math.sqrt(dx * dx + dz * dz)
	local speed = dist / dt
	local allowed = math.abs(profile.allowed:Get(i - 1))
	local walk = math.max((allowed - 4) / 1.35, 1)
	local grounded = profile.grounds:Get(i - 1) == 1
	local moving = speed > MOVING

	self.samples += 1
	self.time += dt
	if moving then
		self.moving += 1
		self.ratioSum += speed / walk
	end
	if not grounded then
		self.air += 1
	end
	if self.wasGrounded and not grounded then
		self.jumps += 1
	end
	if moving ~= self.wasMoving then
		self.stopGo += 1
	end
	local dyaw = math.abs(profile.yaws:Get(i - 1) - profile.yaws:Get(i))
	if dyaw > math.pi then
		dyaw = 2 * math.pi - dyaw
	end
	self.turns += dyaw

	-- straightness over 2s windows: how far you got vs how far you walked
	if not self.windowStart then
		self.windowStart = { profile.xs:Get(i), profile.zs:Get(i) }
	end
	self.windowPath += dist
	self.windowTime += dt
	if self.windowTime >= 2 then
		if self.windowPath > 4 then
			local ex = profile.xs:Get(i - 1) - self.windowStart[1]
			local ez = profile.zs:Get(i - 1) - self.windowStart[2]
			self.straightSum += math.sqrt(ex * ex + ez * ez) / self.windowPath
			self.straightN += 1
		end
		self.windowStart, self.windowPath, self.windowTime = nil, 0, 0
	end

	self.wasMoving, self.wasGrounded = moving, grounded
end

-- nil until there's enough play to be meaningful
function PlayStyle:Vector(netCalls)
	if self.samples < MIN_SAMPLES or self.time <= 0 then
		return nil
	end
	local minutes = self.time / 60
	local function r(n)
		return math.floor(n * 1000 + 0.5) / 1000
	end
	return {
		r(if self.moving > 0 then self.ratioSum / self.moving else 0), -- how close to full speed they walk
		r(self.moving / self.samples), -- how much of the time they're moving
		r(self.air / self.samples), -- how much of the time they're airborne
		r(self.jumps / minutes), -- jumps per minute
		r(self.turns / self.time), -- how fast they turn, rad/s
		r(if self.straightN > 0 then self.straightSum / self.straightN else 0), -- straight lines vs wandering
		r(self.stopGo / minutes), -- start/stop rhythm
		r(netCalls / minutes), -- remote calls per minute
	}
end

return PlayStyle
