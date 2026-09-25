local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- invisible dummies parked right next to players who are already looking suspicious.
-- no human can see, touch or shoot them. kill aura and silent aim pick the nearest humanoid
-- and send it straight to your hit remote, so ValidateHit sees them target something nobody can see.
-- tagged "ACBait": if your own NPC AI scans workspace for humanoids, skip that tag
local BaitNPC = { Name = "ACBaitNPC", Feature = "BaitNPC", Rate = "cold" }

local SUSPECT = 0.25 -- share of the kick score before a player gets a bait
local OFFSET = 6

local Honeypot, PlayerService
local baits = {} -- profile -> model
local owners = {} -- model -> profile

local NAMES = { "Guest", "Player", "Noob", "xX_Pro_Xx", "Builder", "Robloxian" }

local function makeBait()
	local model = Instance.new("Model")
	model.Name = NAMES[math.random(#NAMES)] .. math.random(100, 9999)

	local function part(name, size, offset)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Transparency = 1
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Massless = true
		p.Anchored = true
		p.CFrame = CFrame.new(offset)
		p.Parent = model
		return p
	end

	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	part("Torso", Vector3.new(2, 2, 1), Vector3.zero)
	part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0))
	model.PrimaryPart = root

	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0
	hum.Parent = model

	CollectionService:AddTag(model, "ACBait")
	model:SetAttribute("ACBait", true)
	for _, d in model:GetDescendants() do
		CollectionService:AddTag(d, "ACInternal")
	end

	-- only one thing counts: a remote naming this model as the target (through ValidateHit).
	-- explosions, stray bullets and sword swings pass right through, it can't be touched or raycast,
	-- so a legit player can never trip it by accident
	hum.MaxHealth = math.huge
	hum.Health = math.huge

	model.Parent = workspace
	return model
end

function BaitNPC.IsBait(model)
	return typeof(model) == "Instance" and owners[model] ~= nil
end

function BaitNPC.Tripped(profile, model, how)
	if profile and Config.On("BaitNPC") then
		Honeypot.Trip(profile, "BaitNPC:" .. how)
	end
end

local function release(profile)
	local model = baits[profile]
	if model then
		baits[profile] = nil
		owners[model] = nil
		model:Destroy()
	end
end

function BaitNPC.Step(profile, now)
	local root = profile.root
	local suspicious = profile:Score(now) >= Config.Thresholds.KickScore * SUSPECT
	if profile.admin or not suspicious or not root or not root.Parent then
		release(profile)
		return
	end
	local model = baits[profile]
	if not model then
		model = makeBait()
		baits[profile] = model
		owners[model] = profile
	end
	-- a new random spot beside them every step, just out of arm's reach
	local angle = math.random() * math.pi * 2
	local pos = root.Position + Vector3.new(math.cos(angle) * OFFSET, 0, math.sin(angle) * OFFSET)
	model:PivotTo(CFrame.new(pos))
end

function BaitNPC:Start()
	Honeypot = Framework.Get("ACHoneypot")
	PlayerService = Framework.Get("ACPlayers")
	Framework.Get("ACScheduler").Add(BaitNPC)
	PlayerService.Removing:Connect(release)
	Config.Changed:Connect(function()
		if not Config.On("BaitNPC") then
			for profile in baits do
				release(profile)
			end
		end
	end)
end

return BaitNPC
