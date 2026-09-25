local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

local B = Config.Backend

-- mission control feed: where everyone is, every few seconds. also the fast lane for dashboard commands
local Pulse = { Name = "ACPulse" }

local PlayerService, Backend, Threat, Island, Commands

local function round(n)
	return math.floor(n * 10 + 0.5) / 10
end

local function beat()
	local live = Config.On("MissionControl")
	local now = os.clock()
	local players = {}
	for _, profile in PlayerService.List() do
		local entry = { id = tostring(profile.userId) }
		if live then
			entry.name = profile.player.Name
			entry.score = round(profile:Score(now))
			local root = profile.root
			if root and root.Parent then
				local p = root.Position
				local look = root.CFrame.LookVector
				entry.x, entry.y, entry.z = round(p.X), round(p.Y), round(p.Z)
				entry.yaw = round(math.atan2(-look.X, -look.Z))
			end
			entry.admin = profile.admin or nil
		end
		table.insert(players, entry)
	end

	local data = Backend.Post({
		op = "pulse",
		server = Backend.ServerId,
		place = tostring(game.PlaceId),
		threat = Threat.Level(),
		island = Island.IsIsland(),
		live = live,
		players = players,
		cmdAcks = Commands.TakeAcks(),
	})
	if data then
		Commands.Dispatch(data.commands)
	end
end

function Pulse:Start()
	PlayerService = Framework.Get("ACPlayers")
	Backend = Framework.Get("ACBackend")
	Threat = Framework.Get("ACThreat")
	Island = Framework.Get("ACIsland")
	Commands = Framework.Get("ACCommands")

	task.spawn(function()
		while true do
			task.wait(B.PulseInterval)
			-- nobody here, nothing to show
			if #PlayerService.List() > 0 and (Config.On("MissionControl") or Config.On("Spectator") or Config.On("Replays")) then
				beat()
			end
		end
	end)
end

return Pulse
