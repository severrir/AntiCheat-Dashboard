local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Recording = require(AC.Classes.Recording)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- turns the last 20s of a player's history into a Recording the dashboard can play back in 3D
local RecorderService = { Name = "ACRecorderService" }

-- synchronous on purpose: grab everything before the player object goes away
function RecorderService:Capture(profile, kind, reason)
	return Recording.capture(profile, kind, reason, {
		server = self._backend.ServerId,
		mapVersion = self._map:Version(),
		kickScore = Config.Thresholds.KickScore,
	})
end

-- yields. returns the replay id or nil
function RecorderService:Upload(recording)
	if not recording then
		return nil
	end
	local data = self._backend:Post(recording:ToPayload())
	return data and tonumber(data.id)
end

function RecorderService:Start()
	self._backend = Framework.Get("ACBackendService")
	self._map = Framework.Get("ACMapExportService")
end

return RecorderService
