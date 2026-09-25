local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)

-- cheater island: instead of a kick, cheaters get sent to one private server full of other cheaters.
-- off by default, flip it in the dashboard. needs a published game, studio just kicks like normal
local Island = { Name = "ACIsland" }

local STORE = "AC_Island"

local isIsland = false
local code = nil
local sending = {}

function Island.IsIsland()
	return isIsland
end

local function load()
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
	if not ok then
		return
	end
	local ok2, data = pcall(store.GetAsync, store, "server")
	if ok2 and type(data) == "table" then
		code = data.code
		if game.PrivateServerId ~= "" and data.id == game.PrivateServerId then
			isIsland = true
		end
	end
	if code or not Config.On("CheaterIsland") then
		return
	end

	-- first time: reserve the island and remember it for every server
	local ok3, newCode, privateId = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
	if not ok3 then
		return
	end
	pcall(store.UpdateAsync, store, "server", function(old)
		if type(old) == "table" and old.code then
			code = old.code
			return nil
		end
		code = newCode
		return { code = newCode, id = privateId }
	end)
end

-- returns right away. true means we're handling it (teleport started), false means kick them
function Island.Send(player)
	if RunService:IsStudio() or isIsland or not code or not Config.On("CheaterIsland") then
		return false
	end
	sending[player] = true
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		local ok = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
		if not ok and player.Parent then
			sending[player] = nil
			player:Kick(Config.KickMessage)
		end
	end)
	return true
end

function Island:Start()
	if RunService:IsStudio() then
		return
	end
	task.spawn(load)
	-- if the island got switched on later, reserve it then
	Config.Changed:Connect(function()
		if Config.On("CheaterIsland") and not code then
			task.spawn(load)
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player)
		if sending[player] then
			sending[player] = nil
			player:Kick(Config.KickMessage)
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		sending[player] = nil
	end)
end

return Island
