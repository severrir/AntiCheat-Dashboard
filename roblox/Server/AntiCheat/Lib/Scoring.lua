-- the math behind trust scores and the kick decision. pure, so tests can use it too

local Scoring = {}

function Scoring.decay(value, since, now, halfLife)
	if value <= 0 then
		return 0
	end
	return value * 0.5 ^ ((now - since) / math.max(halfLife, 1))
end

-- worst 1 second window of the recorded path compared to what was allowed.
-- > 1 means they really did go faster than allowed, not just lag
-- xs/zs/times/allowed are ring buffers, 1 = newest. negative allowed = right after our own snapback
function Scoring.worstWindow(times, xs, zs, allowed)
	local n = times.count
	if n < 3 then
		return 0
	end

	local function step(k)
		if allowed:Get(k) < 0 then
			return 0
		end
		local dx = xs:Get(k) - xs:Get(k + 1)
		local dz = zs:Get(k) - zs:Get(k + 1)
		return math.sqrt(dx * dx + dz * dz)
	end

	local worst, j, dist = 0, 1, 0
	for i = 1, n - 1 do
		dist += step(i)
		while times:Get(j) - times:Get(i + 1) > 1 and j < i do
			dist -= step(j)
			j += 1
		end
		local span = times:Get(j) - times:Get(i + 1)
		if span >= 0.5 then
			local limit = math.abs(allowed:Get(j)) * span * 1.15 + 6
			worst = math.max(worst, dist / limit)
		end
	end
	return worst
end

--[[
	breakdown: { {check, value}, ... } sorted biggest first
	returns "kick", "wait" (not enough agreement yet) or "scale" (replay says it was lag, halve the score)
	confirmMovement() is only called when movement is the top check
]]
function Scoring.decide(score, breakdown, T, definitive, confirmMovement)
	if score < T.KickScore or #breakdown == 0 then
		return "wait"
	end

	local proof = false
	local distinct = 0
	for _, part in breakdown do
		if definitive[part.check] and part.value >= T.KickScore * 0.5 then
			proof = true
		end
		if part.value >= T.KickScore * 0.1 then
			distinct += 1
		end
	end
	if proof then
		return "kick"
	end

	if breakdown[1].check == "Movement" then
		-- movement proves itself through replay, it doesn't need a second check
		return if confirmMovement() then "kick" else "scale"
	end
	-- anything else alone is too noisy, wait for another check to agree
	return if distinct >= T.MinCorroboratingChecks then "kick" else "wait"
end

return Scoring
