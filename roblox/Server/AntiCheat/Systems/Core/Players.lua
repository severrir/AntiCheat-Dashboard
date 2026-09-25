local Players = game:GetService("Players")

local AC = script:FindFirstAncestor("AntiCheat")
local Profile = require(AC.Lib.Profile)
local Signal = require(AC.Lib.Signal)

-- one profile per player, created on join. everything else reads profiles through here
local PlayerService = {
	Name = "ACPlayers",
	Added = Signal.new(),
	Removing = Signal.new(),
}

local byPlayer = {}
local list = {}

function PlayerService.Get(player)
	return byPlayer[player]
end

function PlayerService.GetById(userId)
	local player = Players:GetPlayerByUserId(userId)
	return player and byPlayer[player]
end

-- dense array for the scheduler, swap-remove keeps it that way
function PlayerService.List()
	return list
end

-- waits a moment for the profile, join handlers can race PlayerAdded
function PlayerService.Await(player, timeout)
	local deadline = os.clock() + (timeout or 5)
	while not byPlayer[player] and player.Parent and os.clock() < deadline do
		task.wait()
	end
	return byPlayer[player]
end

local function add(player)
	if byPlayer[player] then
		return
	end
	local profile = Profile.new(player)
	byPlayer[player] = profile
	table.insert(list, profile)

	player.CharacterAdded:Connect(function(char)
		profile:BindCharacter(char)
	end)
	player.CharacterRemoving:Connect(function(char)
		if profile.char == char then
			profile:UnbindCharacter()
		end
	end)
	if player.Character then
		task.spawn(profile.BindCharacter, profile, player.Character)
	end

	PlayerService.Added:Fire(profile)
end

local function remove(player)
	local profile = byPlayer[player]
	if not profile then
		return
	end
	PlayerService.Removing:Fire(profile)
	profile:UnbindCharacter()
	byPlayer[player] = nil
	local i = table.find(list, profile)
	if i then
		list[i] = list[#list]
		list[#list] = nil
	end
end

function PlayerService:Start()
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(remove)
	for _, player in Players:GetPlayers() do
		task.spawn(add, player)
	end
end

return PlayerService
