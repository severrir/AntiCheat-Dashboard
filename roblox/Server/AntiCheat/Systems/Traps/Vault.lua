local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- a sealed room nobody can reach without noclip or teleporting. being inside it is proof.
-- one is built automatically far from everything, and any part named ACVault becomes another one
local Vault = { Name = "ACVault", Feature = "TrapVault", Rate = "hot" }

local WALL = 4

local Honeypot
local zones = {}
local built = nil

local function build()
	if built then
		return
	end
	local v = Config.Vault
	local model = Instance.new("Model")
	model.Name = "Terrain_Cache"
	local half = v.Size / 2
	local faces = {
		{ Vector3.new(0, half.Y + WALL / 2, 0), Vector3.new(v.Size.X + WALL * 2, WALL, v.Size.Z + WALL * 2) },
		{ Vector3.new(0, -half.Y - WALL / 2, 0), Vector3.new(v.Size.X + WALL * 2, WALL, v.Size.Z + WALL * 2) },
		{ Vector3.new(half.X + WALL / 2, 0, 0), Vector3.new(WALL, v.Size.Y, v.Size.Z + WALL * 2) },
		{ Vector3.new(-half.X - WALL / 2, 0, 0), Vector3.new(WALL, v.Size.Y, v.Size.Z + WALL * 2) },
		{ Vector3.new(0, 0, half.Z + WALL / 2), Vector3.new(v.Size.X, v.Size.Y, WALL) },
		{ Vector3.new(0, 0, -half.Z - WALL / 2), Vector3.new(v.Size.X, v.Size.Y, WALL) },
	}
	for _, f in faces do
		local wall = Instance.new("Part")
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CastShadow = false
		wall.Size = f[2]
		wall.CFrame = CFrame.new(v.Position + f[1])
		CollectionService:AddTag(wall, "ACInternal")
		wall.Parent = model
	end
	model.Parent = workspace
	built = model
end

local function rebuildZones()
	table.clear(zones)
	if built then
		table.insert(zones, { cf = CFrame.new(Config.Vault.Position), half = Config.Vault.Size / 2 })
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ACVault" then
			table.insert(zones, { cf = d.CFrame, half = d.Size / 2 })
		end
	end
end

local function apply()
	if Config.On("TrapVault") then
		build()
	elseif built then
		built:Destroy()
		built = nil
	end
	rebuildZones()
end

function Vault.Step(profile)
	local root = profile.root
	if not root or not root.Parent then
		return
	end
	local pos = root.Position
	for _, zone in zones do
		local p = zone.cf:PointToObjectSpace(pos)
		local h = zone.half
		if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z then
			Honeypot.Trip(profile, "TrapVault")
			return
		end
	end
end

function Vault:Start()
	Honeypot = Framework.Get("ACHoneypot")
	Framework.Get("ACScheduler").Add(Vault)
	apply()
	Config.Changed:Connect(apply)
end

return Vault
