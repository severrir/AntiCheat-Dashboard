local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)

local IslandService = { Name = "ACIslandService" }

local STORE = "AC_Island"

function IslandService:Init()
	self._isIsland = false
	self._code = nil
	self._sending = {}
end

function IslandService:IsIsland()
	return self._isIsland
end

function IslandService:_load()
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
	if not ok then
		return
	end
	local ok2, data = pcall(store.GetAsync, store, "server")
	if ok2 and type(data) == "table" then
		self._code = data.code
		if game.PrivateServerId ~= "" and data.id == game.PrivateServerId then
			self._isIsland = true
		end
	end
	if self._code or not Config.On("CheaterIsland") then
		return
	end

	local ok3, newCode, privateId = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
	if not ok3 then
		return
	end
	pcall(store.UpdateAsync, store, "server", function(old)
		if type(old) == "table" and old.code then
			self._code = old.code
			return nil
		end
		self._code = newCode
		return { code = newCode, id = privateId }
	end)
end

function IslandService:Send(player)
	if RunService:IsStudio() or self._isIsland or not self._code or not Config.On("CheaterIsland") then
		return false
	end
	self._sending[player] = true
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = self._code
		local ok = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
		if not ok and player.Parent then
			self._sending[player] = nil
			player:Kick(Config.KickMessage)
		end
	end)
	return true
end

function IslandService:Start()
	if RunService:IsStudio() then
		return
	end
	task.spawn(self._load, self)
	Config.Changed:Connect(function()
		if Config.On("CheaterIsland") and not self._code then
			task.spawn(self._load, self)
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player)
		if self._sending[player] then
			self._sending[player] = nil
			player:Kick(Config.KickMessage)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._sending[player] = nil
	end)
end

return IslandService
