local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

-- invisible spectator for admins: /spectate, F8, or "spectate" on the dashboard (which even
-- teleports you into the right server). your character is hidden, the camera follows the suspect.
-- the client side is ACSpectatorController
local SpectatorService = { Name = "ACSpectatorService" }

local HIDE_AT = CFrame.new(-6000, 400, 6000)
local LIST_SIZE = 10

local function isAdmin(player)
	return Config.Admins[player.UserId] == true
end

local function hide(admin)
	local char = admin.Character
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Decal") then
			d.Transparency = 1
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end
	char:PivotTo(HIDE_AT)
end

function SpectatorService:Init()
	self._watching = {} -- admin -> { target = userId }
	self.Admin = Net.Event("ACAdmin")
	self.State = Net.Event("ACSpectateState")
	self.Action = Net.Event({ name = "ACAdminAction", cooldown = 0.2 }):Expect("string", "number")
end

function SpectatorService:_suspects()
	local now = os.clock()
	local list = {}
	for _, profile in self._players:List() do
		if not profile.immune then
			local top = profile:Breakdown(now)[1]
			table.insert(list, {
				id = profile.userId,
				name = profile.player.Name,
				score = math.floor(profile:Score(now) * 10) / 10,
				top = top and top.check or "",
			})
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	for i = #list, LIST_SIZE + 1, -1 do
		list[i] = nil
	end
	return list
end

function SpectatorService:_push(admin, note)
	local w = self._watching[admin]
	self.State:Fire(admin, {
		active = w ~= nil,
		target = w and w.target or 0,
		kick = Config.Thresholds.KickScore,
		list = self:_suspects(),
		note = note or "",
	})
end

function SpectatorService:Begin(admin, targetId)
	if not isAdmin(admin) or not Config.On("Spectator") then
		return
	end
	if not targetId or targetId == 0 then
		local first = self:_suspects()[1]
		targetId = first and first.id or 0
	end
	self._watching[admin] = { target = targetId }
	hide(admin)
	self:_push(admin)
end

function SpectatorService:Stop(admin)
	if self._watching[admin] then
		self._watching[admin] = nil
		admin:LoadCharacter()
	end
	self:_push(admin)
end

function SpectatorService:_cycle(admin, dir)
	local w = self._watching[admin]
	if not w then
		return
	end
	local list = self:_suspects()
	if #list == 0 then
		return
	end
	local index = 0
	for i, s in list do
		if s.id == w.target then
			index = i
		end
	end
	index = (index - 1 + dir) % #list + 1
	w.target = list[index].id
	self:_push(admin)
end

-- saves the admin's own last 20s as a known-legit session for the test suite
function SpectatorService:_record(admin)
	local profile = self._players:Get(admin)
	local recording = profile and self._recorder:Capture(profile, "session", "recorded by " .. admin.Name)
	self:_push(admin, "saving...")
	local id = self._recorder:Upload(recording)
	self:_push(admin, if id then "saved session #" .. id else "nothing recorded yet, walk around first")
end

function SpectatorService:_onAction(admin, action, targetId)
	if not isAdmin(admin) then
		return
	end
	if action == "spectate" then
		self:Begin(admin, targetId)
	elseif action == "next" then
		self:_cycle(admin, 1)
	elseif action == "prev" then
		self:_cycle(admin, -1)
	elseif action == "stop" then
		self:Stop(admin)
	elseif action == "list" then
		self:_push(admin)
	elseif action == "record" then
		self:_record(admin)
	end
end

function SpectatorService:_onJoin(player)
	if not isAdmin(player) then
		return
	end
	-- keep a spectating admin hidden across respawns
	player.CharacterAdded:Connect(function()
		if self._watching[player] then
			task.defer(hide, player)
		end
	end)
	-- lets the client build the admin panel. everything it sends is still checked here
	self.Admin:Fire(player, { spectator = Config.On("Spectator") })

	-- came in through the dashboard's spectate button from another server
	local data = player:GetJoinData()
	local teleport = data and data.TeleportData
	local target = type(teleport) == "table" and tonumber(teleport.acSpectate)
	if target then
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		task.wait(1)
		self:Begin(player, target)
	end
end

function SpectatorService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._recorder = Framework.Get("ACRecorderService")

	self.Action:Listen(function(admin, action, targetId)
		self:_onAction(admin, action, targetId)
	end)
	Players.PlayerAdded:Connect(function(player)
		self:_onJoin(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._onJoin, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self._watching[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for admin in self._watching do
				self:_push(admin)
			end
		end
	end)
end

return SpectatorService
