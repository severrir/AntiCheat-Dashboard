local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- turns the last 20s of a player's history into a replay the dashboard can play back in 3D
local Recorder = { Name = "ACRecorder" }

local Backend, MapExport

local function r1(n)
	return math.floor(n * 10 + 0.5) / 10
end
local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

-- synchronous on purpose: grab everything before the player object goes away
function Recorder.Snapshot(profile, kind, reason)
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
	return {
		op = "replay",
		user = tostring(profile.userId),
		server = Backend.ServerId,
		place = tostring(game.PlaceId),
		mapVersion = MapExport.Version(),
		kind = kind,
		reason = reason or "",
		meta = {
			name = profile.player.Name,
			walkSpeed = hum and hum.WalkSpeed or 16,
			score = r1(profile:Score()),
			kickScore = Config.Thresholds.KickScore,
		},
		samples = samples,
		events = events,
	}
end

-- yields. returns the replay id or nil
function Recorder.Upload(snapshot)
	if not snapshot then
		return nil
	end
	local data = Backend.Post(snapshot)
	return data and tonumber(data.id)
end

function Recorder:Start()
	Backend = Framework.Get("ACBackend")
	MapExport = Framework.Get("ACMapExport")
end

return Recorder
