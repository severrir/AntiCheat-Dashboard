local ForensicReplay = {}

-- walk back through the recorded path and find the worst 1 second window.
-- if the player never actually went faster than allowed, the flags were probably lag
local function worstWindow(profile)
	local times, positions, allowed = profile.times, profile.positions, profile.allowed
	local n = times.count
	if n < 3 then
		return 0
	end

	local worst = 0
	local j = 1
	local dist = 0
	-- negative allowed = sample right after we snapped them back, that jump is ours so it counts as 0
	local function step(k)
		if allowed:Get(k) < 0 then
			return 0
		end
		local a, b = positions:Get(k), positions:Get(k + 1)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end

	for i = 1, n - 1 do
		-- i is newer, i + 1 is older
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

function ForensicReplay.Confirm(profile, breakdown, now)
	local top = breakdown[1]
	if not top or top.check ~= "Movement" then
		return true
	end

	-- several separate movement violations in the last 10s is enough on its own
	local recent = 0
	for i = 1, profile.moveViolations.count do
		if now - profile.moveViolations:Get(i) < 10 then
			recent += 1
		end
	end
	if recent >= 3 then
		return true
	end

	return worstWindow(profile) > 1
end

return ForensicReplay
