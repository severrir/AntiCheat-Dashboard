local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- shiny coins floating way above the map where nobody can get. auto farm scripts and
-- teleporters grab anything named Coin, legit players never get close.
-- parts named ACCoin in workspace become extra bait coins
local BaitCoin = { Name = "ACBaitCoin" }

local COUNT = 3
local HEIGHT = 150

local Honeypot, PlayerService, MapExport
local spawned = {}
local connections = {}

local function onTouched(hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	local player = char and Players:GetPlayerFromCharacter(char)
	if player and Config.On("BaitCoin") then
		Honeypot.Trip(PlayerService.Get(player), "BaitCoin")
	end
end

local function watch(part)
	table.insert(connections, part.Touched:Connect(onTouched))
end

local function spawnCoins()
	local bounds = MapExport.Bounds()
	local minV = if bounds then bounds.min else Vector3.new(-200, 0, -200)
	local maxV = if bounds then bounds.max else Vector3.new(200, 50, 200)
	for _ = 1, COUNT do
		local coin = Instance.new("Part")
		coin.Name = "Coin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.4, 3, 3)
		coin.Color = Color3.fromRGB(255, 205, 60)
		coin.Material = Enum.Material.Neon
		coin.Anchored = true
		coin.CanCollide = false
		coin.CastShadow = false
		local x = minV.X + math.random() * (maxV.X - minV.X)
		local z = minV.Z + math.random() * (maxV.Z - minV.Z)
		coin.CFrame = CFrame.new(x, maxV.Y + HEIGHT, z) * CFrame.Angles(0, 0, math.rad(90))
		CollectionService:AddTag(coin, "ACInternal")
		coin.Parent = workspace
		watch(coin)
		table.insert(spawned, coin)
	end
end

local function clear()
	for _, c in connections do
		c:Disconnect()
	end
	for _, coin in spawned do
		coin:Destroy()
	end
	table.clear(connections)
	table.clear(spawned)
end

local function apply()
	clear()
	if not Config.On("BaitCoin") then
		return
	end
	spawnCoins()
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ACCoin" then
			watch(d)
		end
	end
end

function BaitCoin:Start()
	Honeypot = Framework.Get("ACHoneypot")
	PlayerService = Framework.Get("ACPlayers")
	MapExport = Framework.Get("ACMapExport")

	local lastState = nil
	local function refresh()
		local on = Config.On("BaitCoin")
		if on ~= lastState then
			lastState = on
			apply()
		end
	end
	-- wait for the map bounds so the coins know where "above the map" is
	task.delay(8, refresh)
	Config.Changed:Connect(refresh)
end

return BaitCoin
