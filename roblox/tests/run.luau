local MovementModel = require("../Server/AntiCheat/Classes/Player/MovementModel")
local Scoring = require("../Server/AntiCheat/Util/Scoring")
local RingBuffer = require("../Server/AntiCheat/Classes/Core/RingBuffer")
local SyncBatch = require("../Server/AntiCheat/Classes/Core/SyncBatch")
local Sessions = require("./Sessions")
local recorded = require("./recorded")

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

local function play(session)
	local first = session.samples[1]
	local s = MovementModel.new(first.x, first.y, first.z, first.t)
	local times, xs, zs, allowed = RingBuffer.new(HISTORY), RingBuffer.new(HISTORY), RingBuffer.new(HISTORY), RingBuffer.new(HISTORY)
	local violations = RingBuffer.new(8)
	local score, scoreAt = 0, first.t
	local flags, kinds = 0, {}
	local afterSnap = false
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

do
	local b = SyncBatch.new(10)
	for _ = 1, 50 do
		b:AddLedger(1, "currency", "Coins", 10, nil, "farm", false)
	end
	b:AddLedger(1, "currency", "Coins", 5, 2, "transfer", false)
	b:AddLedger(1, "kill", "kill", 1, 2, "", false)
	b:AddReport({ target = "2", reporter = "3", reason = "Flying" })
	local drained = b:Drain()
	assert(#drained.ledger == 3, "ledger rows should merge per player, kind, key, victim and source")
	local coins = 0
	for _, e in drained.ledger do
		if e.kind == "currency" and e.victim == nil then
			coins = e.amount
		end
	end
	assert(coins == 500, "farmed coins should add up, got " .. coins)
	b:AddLedger(1, "currency", "Coins", 10, nil, "farm", false)
	b:Restore(drained)
	local again = b:Drain()
	local total = 0
	for _, e in again.ledger do
		if e.kind == "currency" and e.victim == nil then
			total = e.amount
		end
	end
	assert(total == 510, "restored ledger should merge with new gains, got " .. total)
	assert(#again.reports == 1, "a failed sync must keep its reports")
	print("ledger batching: ok")
end

do
	local b = SyncBatch.new(400)
	for i = 1, 150 do
		b:AddKick({ id = tostring(i) })
	end
	b:AddDeparted({ id = "9" })
	b:AddFlag({ userId = 5 }, "Movement", 10, 10, 10, { speed = math.huge, kind = "Speed" })
	local first = b:Drain()
	assert(#first.kicks == 100, "a sync should send at most 100 kicks")
	assert(first.flags[1].ctx.speed == nil and first.flags[1].ctx.kind == "Speed", "infinite numbers must not reach the json")
	b:Restore(first)
	local second = b:Drain()
	assert(#second.kicks == 100 and second.kicks[1].id == "1", "restored kicks go back to the front of the queue")
	assert(#second.departed == 1 and #second.flags == 1, "a failed sync must keep departed players and flags")
	assert(#b:Drain().kicks == 50, "the rest of the kicks wait for the next sync")
	print("sync limits: ok")
end

do
	local function run(extra, rise, forward, seconds)
		local m = MovementModel.new(0, 10, 0, 0)
		local kinds = {}
		local x, y, t = 0, 10, 0
		while t < seconds do
			t += 0.1
			x += forward * 0.1
			y += rise * 0.1
			local input = { t = t, x = x, y = y, z = 0, walkSpeed = 16, jumpSpeed = 50, grounded = false, climbing = false }
			for k, v in extra do
				input[k] = v
			end
			local verdict = m:Step(input, T)
			if verdict then
				kinds[verdict.kind] = true
				x, y = m:SnapTarget()
			end
		end
		return kinds
	end

	assert(run({}, 0, 16, 5).Fly, "hovering without permission should be flagged as Fly")
	assert(next(run({ flying = true }, 0, 16, 5)) == nil, "AllowFly should let a player hover")
	assert(next(run({ flying = true, flySpeed = 40, walkSpeed = 40 }, 30, 40, 5)) == nil, "AllowFly with a speed should allow flying at that speed")
	assert(run({ flying = true, flySpeed = 40, walkSpeed = 40 }, 0, 90, 5).Speed, "flying faster than the allowed speed should be flagged")
	assert(next(run({ walkSpeed = 60, grounded = true }, 0, 60, 5)) == nil, "AllowSpeed should raise the speed limit")
	assert(run({ grounded = true }, 0, 60, 5).Speed, "the same speed without permission should be flagged")
	assert(next(run({ jumpSpeed = 120, grounded = true }, 100, 0, 0.3)) == nil, "AllowJump should allow a higher jump")
	assert(run({ grounded = true }, 100, 0, 0.3).SuperJump, "the same jump without permission should be flagged")
	print("movement permissions: ok")
end

local color = if falseKicks == 0 and caught == #cheats then "brightgreen" elseif falseKicks == 0 then "yellow" else "red"
print(string.format(
	'BADGE:{"schemaVersion":1,"label":"anticheat tests","message":"%d/%d false kicks · %d/%d cheats caught","color":"%s"}',
	falseKicks, #legit, caught, #cheats, color
))

if falseKicks > 0 then
	error("false kicks on legit sessions", 0)
end
