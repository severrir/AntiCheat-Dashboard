-- pure movement rules. no roblox apis in here on purpose, so the test suite can run it
-- outside roblox against recorded and generated sessions

local MovementModel = {}

-- how many seconds of "standing still" you can bank for lag catch-up
MovementModel.CREDIT_SECONDS = 0.6
MovementModel.BUDGET_LIMIT = 12
-- blink rhythm: bursts decay by half every 5s, more than 6 "in the air" at once is a pattern
MovementModel.BURST_HALF_LIFE = 5
MovementModel.BURST_LIMIT = 6

local sqrt, max, clamp = math.sqrt, math.max, math.clamp

function MovementModel.new(x, y, z, t)
	return {
		lx = x, ly = y, lz = z, lt = t,
		vx = x, vy = y, vz = z,
		gx = x, gy = y, gz = z,
		budget = 0,
		air = 0,
		snapped = false,
	}
end

local function moveTo(s, x, y, z, t)
	s.lx, s.ly, s.lz, s.lt = x, y, z, t
end

--[[
	sample fields:
		t, x, y, z        where the character is now
		walkSpeed         server side WalkSpeed
		jumpSpeed         launch speed a normal jump gives
		grounded          something solid under them within FlyHeight
		climbing          ladder / swimming
		platform          horizontal speed of whatever they stand on
	env.wall(ax, ay, az, bx, by, bz) -> hit, name   solid thing between two points, both ways

	returns verdict (or nil), allowed speed
	verdict = { kind, severity, snap = "valid" | "grounded", ctx }
]]
function MovementModel.step(s, i, T, env)
	local dt = i.t - s.lt
	if dt <= 0 then
		return nil, 0
	end

	local dx, dy, dz = i.x - s.lx, i.y - s.ly, i.z - s.lz
	local horizontal = sqrt(dx * dx + dz * dz)
	local allowed = i.walkSpeed * T.SpeedMargin + 4 + (i.platform or 0)
	s.snapped = false

	local verdict

	-- speed + teleport share one leaky bucket, so lag spikes that catch up don't count
	s.budget = max(s.budget + horizontal - allowed * dt, -allowed * MovementModel.CREDIT_SECONDS)
	if s.budget > MovementModel.BUDGET_LIMIT then
		local dist = sqrt(dx * dx + dy * dy + dz * dz)
		local teleport = dist > T.TeleportDistance
		verdict = {
			kind = if teleport then "Teleport" else "Speed",
			severity = if teleport then 35 else clamp(s.budget, 10, 30),
			snap = "valid",
			ctx = { speed = horizontal / dt, allowed = allowed, dist = dist },
		}
	end

	-- blink: short bursts way over the limit, again and again. the average can stay under the
	-- speed limit, but one burst is lag and a steady rhythm of them isn't
	s.bursts = (s.bursts or 0) * 0.5 ^ (dt / MovementModel.BURST_HALF_LIFE)
	if horizontal / dt > allowed * 2 and horizontal > 4 then
		s.bursts += 1
	end
	if not verdict and s.bursts > MovementModel.BURST_LIMIT then
		verdict = { kind = "Blink", severity = 15, snap = "valid", ctx = { bursts = s.bursts, speed = horizontal / dt, allowed = allowed } }
		s.bursts = 0
	end

	-- super jump: going up way faster than a jump can
	local rise = dy / dt
	if not verdict and not i.climbing and rise > i.jumpSpeed * 1.4 + 8 then
		verdict = { kind = "SuperJump", severity = 15, snap = "grounded", ctx = { rise = rise, max = i.jumpSpeed } }
	end

	-- flying: far off the ground and not falling for too long
	if not verdict then
		if not i.grounded and not i.climbing then
			if rise > -8 then
				s.air += dt
			else
				s.air = max(0, s.air - dt)
			end
			if s.air > T.FlyTime then
				verdict = { kind = "Fly", severity = 25, snap = "grounded", ctx = { air = s.air, y = i.y } }
			end
		else
			s.air = 0
		end
	end

	-- noclip: something solid between the last spot and this one
	-- any real movement gets checked, a slow noclip walk is still a noclip
	if not verdict and horizontal > 0.3 and env and env.wall then
		local hit, name = env.wall(s.lx, s.ly, s.lz, i.x, i.y, i.z)
		if hit then
			verdict = { kind = "Noclip", severity = 20, snap = "valid", ctx = { part = name or "?" } }
		end
	end

	if verdict then
		if verdict.snap == "grounded" then
			moveTo(s, s.gx, s.gy, s.gz, i.t)
		else
			moveTo(s, s.vx, s.vy, s.vz, i.t)
		end
		s.budget = 0
		s.air = 0
		s.snapped = true
		return verdict, allowed
	end

	moveTo(s, i.x, i.y, i.z, i.t)
	-- only trust spots where they weren't running on borrowed speed,
	-- otherwise a snapback just moves them one step back
	if s.budget <= 0 then
		s.vx, s.vy, s.vz = i.x, i.y, i.z
		if i.grounded or i.climbing then
			s.gx, s.gy, s.gz = i.x, i.y, i.z
		end
	end
	return nil, allowed
end

return MovementModel
