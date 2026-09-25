local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- one number per server for mission control: 0 calm, 1 watch, 2 alert, 3 red
local Threat = { Name = "ACThreat" }

local PlayerService
local flagTimes = {}
local kickTimes = {}

local function prune(list, window, now)
	while list[1] and now - list[1] > window do
		table.remove(list, 1)
	end
end

function Threat.NoteKick()
	table.insert(kickTimes, os.clock())
end

function Threat.Level()
	local now = os.clock()
	prune(flagTimes, 60, now)
	prune(kickTimes, 600, now)

	local suspects = 0
	for _, profile in PlayerService.List() do
		if not profile.kicked and profile:Score(now) >= Config.Thresholds.KickScore * 0.5 then
			suspects += 1
		end
	end

	if #kickTimes >= 2 or suspects >= 3 then
		return 3
	elseif #kickTimes >= 1 or suspects >= 1 then
		return 2
	elseif #flagTimes >= 5 then
		return 1
	end
	return 0
end

function Threat:Start()
	PlayerService = Framework.Get("ACPlayers")
	Framework.Get("ACTrust").Flagged:Connect(function()
		table.insert(flagTimes, os.clock())
		-- a flood of flags shouldn't grow this forever
		if #flagTimes > 500 then
			table.remove(flagTimes, 1)
		end
	end)
end

return Threat
