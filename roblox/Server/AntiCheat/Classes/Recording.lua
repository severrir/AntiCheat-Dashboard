-- the last 20s of one player's movement plus what fired, frozen at one moment.
-- captured synchronously (the player may be gone a frame later), uploaded whenever
local Recording = {}
Recording.__index = Recording

local function r1(n)
	return math.floor(n * 10 + 0.5) / 10
end
local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

-- context: { server, mapVersion, kickScore }
function Recording.capture(profile, kind, reason, context)
	local n = profile.times.count
	if n == 0 then
		return nil
	end
	local tEnd = profile.times:Get(1)

	-- oldest first. [t, x, y, z, yaw, snapped, grounded]
	local samples = table.create(n)
	for i = n, 1, -1 do
		local allowed = profile.allowed:Get(i)
		table.insert(samples, {
			r2(profile.times:Get(i) - tEnd),
			r1(profile.xs:Get(i)),
			r1(profile.ys:Get(i)),
			r1(profile.zs:Get(i)),
			r2(profile.yaws:Get(i)),
			if allowed < 0 then 1 else 0,
			profile.grounds:Get(i),
		})
	end

	local tStart = profile.times:Get(n)
	local events = {}
	for i = profile.events.count, 1, -1 do
		local e = profile.events:Get(i)
		if e.t >= tStart - 0.5 then
			table.insert(events, { r2(e.t - tEnd), e.check, e.kind, e.detail })
		end
	end

	local hum = profile.humanoid
	return setmetatable({
		userId = profile.userId,
		kind = kind,
		reason = reason or "",
		context = context,
		meta = {
			name = profile.player.Name,
			walkSpeed = hum and hum.WalkSpeed or 16,
			score = r1(profile:Score()),
			kickScore = context.kickScore,
		},
		samples = samples,
		events = events,
	}, Recording)
end

function Recording:ToPayload()
	return {
		op = "replay",
		user = tostring(self.userId),
		server = self.context.server,
		place = tostring(game.PlaceId),
		mapVersion = self.context.mapVersion,
		kind = self.kind,
		reason = self.reason,
		meta = self.meta,
		samples = self.samples,
		events = self.events,
	}
end

return Recording
