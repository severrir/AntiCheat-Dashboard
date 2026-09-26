local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- one number per server for mission control: 0 calm, 1 watch, 2 alert, 3 under attack
local ThreatService = { Name = "ACThreatService" }

local MAX_FLAGS = 500

local function prune(list, window, now)
	while list[1] and now - list[1] > window do
		table.remove(list, 1)
	end
end

function ThreatService:Init()
	self._flags = {}
	self._kicks = {}
end

function ThreatService:NoteKick()
	table.insert(self._kicks, os.clock())
end

function ThreatService:Level()
	local now = os.clock()
	prune(self._flags, 60, now)
	prune(self._kicks, 600, now)

	local suspects = 0
	for _, profile in self._players:List() do
		if not profile.kicked and profile:Score(now) >= Config.Thresholds.KickScore * 0.5 then
			suspects += 1
		end
	end

	if #self._kicks >= 2 or suspects >= 3 then
		return 3
	elseif #self._kicks >= 1 or suspects >= 1 then
		return 2
	elseif #self._flags >= 5 then
		return 1
	end
	return 0
end

function ThreatService:Start()
	self._players = Framework.Get("ACPlayerService")
	Framework.Get("ACTrustService").Flagged:Connect(function()
		table.insert(self._flags, os.clock())
		-- a flood of flags shouldn't grow this forever
		if #self._flags > MAX_FLAGS then
			table.remove(self._flags, 1)
		end
	end)
end

return ThreatService
