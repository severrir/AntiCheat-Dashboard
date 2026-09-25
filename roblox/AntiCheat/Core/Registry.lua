local Players = game:GetService("Players")

local PlayerProfile = require(script.Parent.PlayerProfile)
local Signal = require(script.Parent.Signal)

local Registry = {
	Added = Signal.new(),
	Removing = Signal.new(),
}

local byPlayer = {}
local list = {}

function Registry.Get(player)
	return byPlayer[player]
end

-- array for the scheduler. swap-remove keeps it dense
function Registry.List()
	return list
end

local function add(player)
	if byPlayer[player] then
		return
	end
	local profile = PlayerProfile.new(player)
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

	Registry.Added:Fire(profile)
end

local function remove(player)
	local profile = byPlayer[player]
	if not profile then
		return
	end
	Registry.Removing:Fire(profile)
	profile:UnbindCharacter()
	byPlayer[player] = nil
	local i = table.find(list, profile)
	if i then
		list[i] = list[#list]
		list[#list] = nil
	end
end

function Registry.Init()
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(remove)
	for _, player in Players:GetPlayers() do
		task.spawn(add, player)
	end
end

return Registry
