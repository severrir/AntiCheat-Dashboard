-- runs the real movement + scoring code against generated sessions (and any recorded ones)
-- outside roblox. prints a summary, and a BADGE: line the CI turns into the README badge.
-- luau tests/run.luau

local MovementModel = require("../Server/AntiCheat/Classes/MovementModel")
local Scoring = require("../Server/AntiCheat/Util/Scoring")
local RingBuffer = require("../Server/AntiCheat/Classes/RingBuffer")
local Sessions = require("./Sessions")
local recorded = require("./recorded")

-- same defaults as Config.lua
local T = {
	KickScore = 100,
	HalfLife = 45,
	MinCorroboratingChecks = 2,
	SpeedMargin = 1.35,
	TeleportDistance = 45,
	FlyTime = 2.5,
	FlyHeight = 12,
	WeightMovement = 1,
}
local DEFINITIVE = { Honeypot = true }
local HISTORY = 200

-- plays one session through the model exactly like the server would, snapbacks included
local function play(session)
	local first = session.samples[1]
	local s = MovementModel.new(first.x, first.y, first.z, first.t)
	local times, xs, zs, allowed = RingBuffer.new(HISTORY), RingBuffer.new(HISTORY), RingBuffer.new(HISTORY), RingBuffer.new(HISTORY)
	local violations = RingBuffer.new(8)
	local score, scoreAt = 0, first.t
	local flags, kinds = 0, {}
	local afterSnap = false
	-- when we snap them back, the cheat keeps going from the snapped spot, like a real client would
	local offX, offY, offZ = 0, 0, 0

	local env = { wall = session.wall }

	for i = 2, #session.samples do
		local p = session.samples[i]
		local x, y, z = p.x + offX, p.y + offY, p.z + offZ
		local verdict, allow = s:Step({
			t = p.t, x = x, y = y, z = z,
			walkSpeed = p.walkSpeed or session.walkSpeed or 16,
			jumpSpeed = p.jumpSpeed or 50,
			grounded = p.grounded,
			climbing = p.climbing or false,
			platform = p.platform or 0,
		}, T, env)

		times:Push(p.t)
		xs:Push(x)
		zs:Push(z)
		allowed:Push(math.max(allow, 1) * (if afterSnap then -1 else 1))
		afterSnap = verdict ~= nil

		if verdict then
			flags += 1
			kinds[verdict.kind] = (kinds[verdict.kind] or 0) + 1
			violations:Push(p.t)
			score = Scoring.decay(score, scoreAt, p.t, T.HalfLife) + verdict.severity * T.WeightMovement
			scoreAt = p.t
			-- snapbacks move the player in game, legit or not
			do
				local sx, sy, sz = s:SnapTarget()
				offX += sx - x
				offY += sy - y
				offZ += sz - z
			end

			local now = p.t
			local decision = Scoring.decide(score, { { check = "Movement", value = score } }, T, DEFINITIVE, function()
				local recent = 0
				for k = 1, violations.count do
					if now - violations:Get(k) < 10 then
						recent += 1
					end
				end
				return recent >= 3 or Scoring.worstWindow(times, xs, zs, allowed) > 1
			end)
			if decision == "kick" then
				return { kicked = true, flags = flags, kinds = kinds, at = now - first.t }
			elseif decision == "scale" then
				score *= 0.5
			end
		end
	end
	return { kicked = false, flags = flags, kinds = kinds }
end

local legit, cheats = Sessions.generate(20260926)
for _, r in recorded do
	table.insert(if r.label == "cheat" then cheats else legit, r)
end

local falseKicks, legitFlags, caught = 0, 0, 0
local missed = {}
local wrong = {}

for _, session in legit do
	local r = play(session)
	legitFlags += r.flags
	if r.kicked then
		falseKicks += 1
		table.insert(wrong, session.name)
	end
end

local byType = {}
for _, session in cheats do
	local r = play(session)
	local bucket = byType[session.kind] or { total = 0, caught = 0, secs = 0 }
	byType[session.kind] = bucket
	bucket.total += 1
	if r.kicked then
		caught += 1
		bucket.caught += 1
		bucket.secs += r.at
	else
		local parts = {}
		for k, n in r.kinds do
			table.insert(parts, k .. "=" .. n)
		end
		table.insert(missed, session.name .. " (" .. (if #parts > 0 then table.concat(parts, " ") else "no flags") .. ")")
	end
end

print(string.format("legit sessions:  %d   false kicks: %d   stray flags: %d", #legit, falseKicks, legitFlags))
print(string.format("cheat sessions:  %d   caught: %d", #cheats, caught))
for kind, b in byType do
	print(string.format("  %-10s %d/%d caught, avg %.1fs to kick", kind, b.caught, b.total, if b.caught > 0 then b.secs / b.caught else 0))
end
if #wrong > 0 then
	print("FALSE KICKS: " .. table.concat(wrong, ", "))
end
if #missed > 0 then
	print("missed: " .. table.concat(missed, ", "))
end

local color = if falseKicks == 0 and caught == #cheats then "brightgreen" elseif falseKicks == 0 then "yellow" else "red"
print(string.format(
	'BADGE:{"schemaVersion":1,"label":"anticheat tests","message":"%d/%d false kicks · %d/%d cheats caught","color":"%s"}',
	falseKicks, #legit, caught, #cheats, color
))

-- a false kick is the one thing that must never ship
if falseKicks > 0 then
	error("false kicks on legit sessions", 0)
end
