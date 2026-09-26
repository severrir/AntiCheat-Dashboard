local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Check = require(AC.Classes.Check)
local TrapZone = require(AC.Classes.TrapZone)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- a sealed room nobody can reach without noclip or teleporting. being inside it is proof.
-- one is built automatically far from everything, and any part named ACVault becomes another one
local VaultService = Check.extend({
	Name = "ACVaultService",
	Category = "Honeypot",
	Feature = "TrapVault",
	Rate = "hot",
})

local WALL = 4

function VaultService:Init()
	self._zones = {}
	self._model = nil
end

function VaultService:_build()
	if self._model then
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
	self._model = model
end

function VaultService:_apply()
	if self:IsEnabled() then
		self:_build()
	elseif self._model then
		self._model:Destroy()
		self._model = nil
	end

	local zones = {}
	if self._model then
		table.insert(zones, TrapZone.new(CFrame.new(Config.Vault.Position), Config.Vault.Size))
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "ACVault" then
			table.insert(zones, TrapZone.fromPart(d))
		end
	end
	self._zones = zones
end

-- MovementService calls this with the raw position before it snaps anyone back,
-- otherwise a teleport straight in gets undone before we ever look
function VaultService:Catch(profile, pos)
	if not self:IsEnabled() then
		return false
	end
	for _, zone in self._zones do
		if zone:Contains(pos) then
			self._honeypot:Trip(profile, "TrapVault")
			return true
		end
	end
	return false
end

function VaultService:IsHeadingIn(from, to)
	if not self:IsEnabled() then
		return false
	end
	for _, zone in self._zones do
		if zone:IsHeadingInto(from, to) then
			return true
		end
	end
	return false
end

-- covers anyone movement isn't judging right now (exempt, seated, movement switched off)
function VaultService:Step(profile)
	local root = profile.root
	if root and root.Parent then
		self:Catch(profile, root.Position)
	end
end

function VaultService:OnStart()
	self._honeypot = Framework.Get("ACHoneypotService")
	self:_apply()
	Config.Changed:Connect(function()
		self:_apply()
	end)
end

return VaultService
