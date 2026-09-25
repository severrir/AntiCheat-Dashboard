-- generates realistic movement sessions: legit play full of the stuff that fools naive anticheats
-- (lag spikes, server hitches, stairs, jumps, ledges, moving platforms, ladders, sprinting)
-- and cheat sessions of every kind the movement check handles. deterministic per seed.

local Sessions = {}

local GRAVITY = 196.2
local HIP = 3 -- root height above the ground
local FLY_REACH = 12 + 2 + 3 -- how far down the server looks for ground
local WALL_Z = 300

local function rng(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(a, b)
		state = (state * 16807) % 2147483647
		local r = state / 2147483647
		if a then
			return a + r * (b - a)
		end
		return r
	end
end

-- the little world everyone runs around in
local function groundAt(x, z)
	if x > 100 and x < 160 then
		return 15 - math.abs(x - 130) * 0.5 -- a hill: up 15 studs and back down
	elseif x > 220 and x <= 260 then
		return -(x - 220) -- steep ramp down into the valley
	elseif x > 260 and x <= 262 then
		return -40
	elseif x > 262 then
		return -80 -- a pit you can only fall into
	end
	return 0
end

local function onPlatform(x, z)
	return x < -100 and x > -150
end

-- a solid wall across z = 300, the only way past it is noclip
local function wall(ax, ay, az, bx, by, bz)
	if (az < WALL_Z) ~= (bz < WALL_Z) and math.min(ay, by) < 40 then
		return true, "Wall"
	end
	return false
end

--[[
	behaviour knobs for one session:
		speedMul     cheat speed multiplier
		blink        stand still then burst
		teleportEvery / teleportDist
		flyFrom      seconds in, start hovering
		superJump    jump launch speed
		noclip       walk through the wall
]]
local function simulate(seed, knobs)
	local rand = rng(seed)
	local duration = knobs.duration or 60
	local walk = if rand() < 0.3 then 24 else 16
	local jumpSpeed = 50

	local x, z = rand(-80, 80), rand(-80, 80)
	local y = groundAt(x, z) + HIP
	local vy = 0
	local grounded = true
	local tx, tz = x, z
	local climbing = false
	local climbTop = 0

	local samples = {}
	local t = 0
	local nextSample = 0
	local freezeUntil = -1
	local frozen = nil
	local nextTeleport = knobs.teleportEvery or math.huge
	local dt = 1 / 60

	local function newTarget()
		if knobs.noclip then
			tx, tz = rand(-60, 60), WALL_Z + 100
			return
		end
		if x > 262 then
			tx, tz = rand(266, 300), rand(-100, 100) -- fell in the pit, wander around down there
			return
		end
		local roll = rand()
		if roll < 0.2 then
			tx, tz = rand(110, 150), rand(-40, 40) -- over the hill
		elseif roll < 0.27 then
			tx, tz = rand(230, 258), rand(-40, 40) -- down the ramp
		elseif roll < 0.3 then
			tx, tz = rand(266, 290), rand(-40, 40) -- walk off the edge into the pit
		elseif roll < 0.4 then
			tx, tz = rand(-145, -105), rand(-100, 100) -- onto the moving platform
		else
			tx, tz = rand(-90, 90), rand(-150, 250)
		end
	end
	newTarget()

	while t < duration do
		t += dt

		-- sprint toggles are server-set WalkSpeed changes, the model sees them in the sample
		if rand() < 0.002 then
			walk = if walk == 16 then 24 else 16
		end

		local speed = walk
		if knobs.speedMul then
			speed *= knobs.speedMul
		end
		if knobs.blink then
			local phase = t % 1.5
			speed = if phase < 1 then 0 else walk * 4
		end

		-- ladder: now and then climb straight up
		if not climbing and not knobs.flyFrom and grounded and rand() < 0.0015 then
			climbing = true
			climbTop = y + rand(10, 25)
		end

		local vx, vz = 0, 0
		local dx, dz = tx - x, tz - z
		local d = math.sqrt(dx * dx + dz * dz)
		if climbing then
			y += 10 * dt
			if y >= climbTop then
				climbing = false
			end
		else
			if d < 2 then
				newTarget()
			elseif speed > 0 then
				vx, vz = dx / d * speed, dz / d * speed
			end
			if onPlatform(x, z) and grounded then
				vz += 20
			end
			x += vx * dt
			z += vz * dt

			local g = groundAt(x, z)
			if knobs.flyFrom and t > knobs.flyFrom then
				y += (g + HIP + 25 - y) * math.min(1, dt * 3)
				grounded = false
				vy = 0
			else
				if grounded and rand() < 0.01 then
					vy = knobs.superJump or jumpSpeed
					grounded = false
				end
				if not grounded or y > g + HIP + 0.01 then
					vy -= GRAVITY * dt
					y += vy * dt
					if y <= g + HIP then
						y = g + HIP
						vy = 0
						grounded = true
					else
						grounded = false
					end
				else
					y = g + HIP
				end
			end
		end

		if t >= nextTeleport then
			local a = rand() * math.pi * 2
			local dist = rand(knobs.teleportDist or 60, 300)
			x += math.cos(a) * dist
			z += math.sin(a) * dist
			y = groundAt(x, z) + HIP
			nextTeleport = t + knobs.teleportEvery
		end

		-- client lag: the server sees nothing new for a while, then everything at once
		if not knobs.noLag and t > freezeUntil and rand() < 0.0015 * (knobs.lagMul or 1) then
			freezeUntil = t + rand(0.2, 1.1)
			frozen = { x = x, y = y, z = z, grounded = true }
		end

		if t >= nextSample then
			local seen = if t < freezeUntil then frozen else { x = x, y = y, z = z }
			local g = groundAt(seen.x, seen.z)
			table.insert(samples, {
				t = t,
				x = seen.x, y = seen.y, z = seen.z,
				walkSpeed = walk,
				jumpSpeed = jumpSpeed,
				grounded = seen.y - g <= FLY_REACH,
				climbing = climbing,
				platform = if onPlatform(seen.x, seen.z) then 20 else 0,
			})
			-- server tick jitter, and the odd hitch
			nextSample = t + (if rand() < 0.01 then rand(0.25, 0.6) else rand(0.08, 0.13))
		end
	end

	return samples
end

function Sessions.generate(seed)
	local legit, cheats = {}, {}
	for i = 1, 200 do
		-- the last 50 have a terrible connection: lag spikes 5x as often
		local bad = i > 150
		table.insert(legit, {
			name = (if bad then "badnet#" else "legit#") .. i,
			samples = simulate(seed + i * 7919, { lagMul = if bad then 5 else 1 }),
			wall = wall,
		})
	end

	local kinds = {
		{ kind = "speed", n = 10, knobs = function(r) return { speedMul = r(1.8, 3), noLag = true } end },
		{ kind = "blink", n = 5, knobs = function() return { blink = true, noLag = true } end },
		{ kind = "teleport", n = 10, knobs = function(r) return { teleportEvery = r(2, 6), teleportDist = 60, noLag = true } end },
		{ kind = "fly", n = 8, knobs = function(r) return { flyFrom = r(3, 8), noLag = true } end },
		{ kind = "superjump", n = 7, knobs = function(r) return { superJump = r(130, 200), noLag = true } end },
		{ kind = "noclip", n = 10, knobs = function() return { noclip = true, noLag = true } end },
	}
	local rand = rng(seed)
	local id = 0
	for _, k in kinds do
		for i = 1, k.n do
			id += 1
			table.insert(cheats, {
				name = k.kind .. "#" .. i,
				kind = k.kind,
				samples = simulate(seed * 31 + id * 104729, k.knobs(rand)),
				wall = wall,
			})
		end
	end
	return legit, cheats
end

return Sessions
