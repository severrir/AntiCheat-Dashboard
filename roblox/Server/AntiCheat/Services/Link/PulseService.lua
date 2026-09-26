local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

local B = Config.Backend

-- mission control feed: where everyone is, every few seconds. also the fast lane for dashboard commands
local PulseService = { Name = "ACPulseService" }

local function round(n)
	return math.floor(n * 10 + 0.5) / 10
end

function PulseService:_entry(profile, live, now)
	local entry = { id = tostring(profile.userId) }
	if not live then
		return entry
	end
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
	return entry
end

function PulseService:Beat()
	local live = Config.On("MissionControl")
	local now = os.clock()
	local players = {}
	for _, profile in self._players:List() do
		table.insert(players, self:_entry(profile, live, now))
	end

	local data = self._backend:Post({
		op = "pulse",
		server = self._backend.ServerId,
		place = tostring(game.PlaceId),
		threat = self._threat:Level(),
		island = self._island:IsIsland(),
		live = live,
		players = players,
		cmdAcks = self._commands:TakeAcks(),
	})
	if data then
		self._commands:Dispatch(data.commands)
	end
end

function PulseService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._backend = Framework.Get("ACBackendService")
	self._threat = Framework.Get("ACThreatService")
	self._island = Framework.Get("ACIslandService")
	self._commands = Framework.Get("ACCommandService")

	task.spawn(function()
		while true do
			task.wait(B.PulseInterval)
			-- nobody here, nothing to show
			local wanted = Config.On("MissionControl") or Config.On("Spectator") or Config.On("Replays")
			if #self._players:List() > 0 and wanted then
				self:Beat()
			end
		end
	end)
end

return PulseService
