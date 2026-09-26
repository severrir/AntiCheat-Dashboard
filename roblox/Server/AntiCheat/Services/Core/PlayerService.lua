local Players = game:GetService("Players")

local AC = script:FindFirstAncestor("AntiCheat")
local PlayerProfile = require(AC.Classes.PlayerProfile)
local Signal = require(AC.Classes.Signal)

-- one PlayerProfile per player, created on join. every other service reads profiles through here
local PlayerService = {
	Name = "ACPlayerService",
	Added = Signal.new(), -- (profile)
	Removing = Signal.new(), -- (profile)
}

function PlayerService:Init()
	self._byPlayer = {}
	self._list = {}
end

function PlayerService:Get(player)
	return self._byPlayer[player]
end

function PlayerService:GetById(userId)
	local player = Players:GetPlayerByUserId(userId)
	return player and self._byPlayer[player]
end

-- dense array for the scheduler, swap-remove keeps it that way
function PlayerService:List()
	return self._list
end

-- waits a moment for the profile, join handlers can race PlayerAdded
function PlayerService:Await(player, timeout)
	local deadline = os.clock() + (timeout or 5)
	while not self._byPlayer[player] and player.Parent and os.clock() < deadline do
		task.wait()
	end
	return self._byPlayer[player]
end

function PlayerService:_add(player)
	if self._byPlayer[player] then
		return
	end
	local profile = PlayerProfile.new(player)
	self._byPlayer[player] = profile
	table.insert(self._list, profile)

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

	self.Added:Fire(profile)
end

function PlayerService:_remove(player)
	local profile = self._byPlayer[player]
	if not profile then
		return
	end
	self.Removing:Fire(profile)
	profile:UnbindCharacter()
	self._byPlayer[player] = nil
	local list = self._list
	local i = table.find(list, profile)
	if i then
		list[i] = list[#list]
		list[#list] = nil
	end
end

function PlayerService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_add(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_remove(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._add, self, player)
	end
end

return PlayerService
