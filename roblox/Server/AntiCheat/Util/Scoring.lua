local Scoring = {}

function Scoring.decay(value, since, now, halfLife)
	if value <= 0 then
		return 0
	end
	return value * 0.5 ^ ((now - since) / math.max(halfLife, 1))
end

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
		return if confirmMovement() then "kick" else "scale"
	end
	return if distinct >= T.MinCorroboratingChecks then "kick" else "wait"
end

return Scoring
