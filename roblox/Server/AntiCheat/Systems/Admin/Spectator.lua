local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

-- invisible spectator for admins: /spectate, F8, or "spectate" on the dashboard (which even
-- teleports you into the right server). your character is hidden, the camera follows the suspect
local Spectator = { Name = "ACSpectator" }

local HIDE_AT = CFrame.new(-6000, 400, 6000)
local LIST_SIZE = 10

local PlayerService, Recorder
local AdminEvent, StateEvent
local watching = {} -- admin -> { target = userId }

local function isAdmin(player)
	return Config.Admins[player.UserId] == true
end

local function suspects()
	local now = os.clock()
	local list = {}
	for _, profile in PlayerService.List() do
		if not profile.admin then
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

local function push(admin, note)
	local w = watching[admin]
	StateEvent:Fire(admin, {
		active = w ~= nil,
		target = w and w.target or 0,
		kick = Config.Thresholds.KickScore,
		list = suspects(),
		note = note or "",
	})
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

function Spectator.Begin(admin, targetId)
	if not isAdmin(admin) or not Config.On("Spectator") then
		return
	end
	if not targetId or targetId == 0 then
		local first = suspects()[1]
		targetId = first and first.id or 0
	end
	watching[admin] = { target = targetId }
	hide(admin)
	push(admin)
end

function Spectator.Stop(admin)
	if watching[admin] then
		watching[admin] = nil
		admin:LoadCharacter()
	end
	push(admin)
end

local function cycle(admin, dir)
	local w = watching[admin]
	if not w then
		return
	end
	local list = suspects()
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
	push(admin)
end

local function onAction(admin, action, targetId)
	if not isAdmin(admin) then
		return
	end
	if action == "spectate" then
		Spectator.Begin(admin, targetId)
	elseif action == "next" then
		cycle(admin, 1)
	elseif action == "prev" then
		cycle(admin, -1)
	elseif action == "stop" then
		Spectator.Stop(admin)
	elseif action == "list" then
		push(admin)
	elseif action == "record" then
		-- saves your own last 20s as a known-legit session for the test suite
		local profile = PlayerService.Get(admin)
		local snap = profile and Recorder.Snapshot(profile, "session", "recorded by " .. admin.Name)
		push(admin, "saving...")
		local id = Recorder.Upload(snap)
		push(admin, if id then "saved session #" .. id else "nothing recorded yet, walk around first")
	end
end

local function onJoin(player)
	if not isAdmin(player) then
		return
	end
	-- lets the client build the admin panel. everything it sends is still checked here
	AdminEvent:Fire(player, { spectator = Config.On("Spectator") })

	local data = player:GetJoinData()
	local teleport = data and data.TeleportData
	local target = type(teleport) == "table" and tonumber(teleport.acSpectate)
	if target then
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		task.wait(1)
		Spectator.Begin(player, target)
	end
end

function Spectator:Start()
	PlayerService = Framework.Get("ACPlayers")
	Recorder = Framework.Get("ACRecorder")

	AdminEvent = Net.Event("ACAdmin")
	StateEvent = Net.Event("ACSpectateState")
	Net.Event({ name = "ACAdminAction", cooldown = 0.2 }):Expect("string", "number"):Listen(onAction)

	-- keep a spectating admin hidden across respawns
	local function track(player)
		player.CharacterAdded:Connect(function()
			if watching[player] then
				task.defer(hide, player)
			end
		end)
		onJoin(player)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		task.spawn(track, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		watching[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for admin in watching do
				push(admin)
			end
		end
	end)
end

return Spectator
