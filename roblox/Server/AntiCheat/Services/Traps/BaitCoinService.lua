local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local BaitCoin = require(AC.Classes.BaitCoin)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- a few coins floating way above the map where nobody can get. auto farm scripts and
-- teleporters grab anything named Coin, legit players never get close
local BaitCoinService = { Name = "ACBaitCoinService" }

local COUNT = 3
local HEIGHT = 150

function BaitCoinService:Init()
	self._coins = {}
	self._active = nil
end

function BaitCoinService:_clear()
	for _, coin in self._coins do
		coin:Destroy()
	end
	table.clear(self._coins)
end

function BaitCoinService:_spawn()
	local onGrab = function(player)
		if Config.On("BaitCoin") then
			self._honeypot:Trip(player, "BaitCoin")
		end
	end

	local bounds = self._map:Bounds()
	local minV = if bounds then bounds.min else Vector3.new(-200, 0, -200)
	local maxV = if bounds then bounds.max else Vector3.new(200, 50, 200)
	for _ = 1, COUNT do
		local x = minV.X + math.random() * (maxV.X - minV.X)
		local z = minV.Z + math.random() * (maxV.Z - minV.Z)
		table.insert(self._coins, BaitCoin.spawnAt(Vector3.new(x, maxV.Y + HEIGHT, z), onGrab))
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ACCoin" then
			table.insert(self._coins, BaitCoin.wrap(d, onGrab, false))
		end
	end
end

function BaitCoinService:_refresh()
	local on = Config.On("BaitCoin")
	if on == self._active then
		return
	end
	self._active = on
	self:_clear()
	if on then
		self:_spawn()
	end
end

function BaitCoinService:Start()
	self._honeypot = Framework.Get("ACHoneypotService")
	self._map = Framework.Get("ACMapExportService")

	-- wait for the map bounds so the coins know where "above the map" is
	task.delay(8, function()
		self:_refresh()
	end)
	Config.Changed:Connect(function()
		self:_refresh()
	end)
end

return BaitCoinService
