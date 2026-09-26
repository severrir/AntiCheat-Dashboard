local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Recording = require(AC.Classes.Player.Recording)
local Framework = require(ReplicatedStorage.Shared.Framework)

local RecorderService = { Name = "ACRecorderService" }

function RecorderService:Capture(profile, kind, reason)
	return Recording.capture(profile, kind, reason, {
		server = self._backend.ServerId,
		mapVersion = self._map:Version(),
		kickScore = Config.Thresholds.KickScore,
	})
end

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
