local CollectionService = game:GetService("CollectionService")

-- an invisible humanoid parked next to one suspect. nobody can see, touch or raycast it,
-- so the only way to "hit" it is a kill aura / silent aim naming it in a hit remote
local BaitDummy = {}
BaitDummy.__index = BaitDummy

local NAMES = { "Guest", "Player", "Noob", "xX_Pro_Xx", "Builder", "Robloxian" }
local OFFSET = 6

local function ghostPart(model, name, size, offset)
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

function BaitDummy.new(owner)
	local model = Instance.new("Model")
	model.Name = NAMES[math.random(#NAMES)] .. math.random(100, 9999)

	local root = ghostPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	ghostPart(model, "Torso", Vector3.new(2, 2, 1), Vector3.zero)
	ghostPart(model, "Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0))
	model.PrimaryPart = root

	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	hum.Parent = model

	-- your own npc ai can skip anything tagged ACBait
	CollectionService:AddTag(model, "ACBait")
	model:SetAttribute("ACBait", true)
	for _, d in model:GetDescendants() do
		CollectionService:AddTag(d, "ACInternal")
	end
	model.Parent = workspace

	return setmetatable({ owner = owner, model = model }, BaitDummy)
end

-- a new random spot beside them every time, just out of arm's reach
function BaitDummy:MoveNear(position)
	local angle = math.random() * math.pi * 2
	self.model:PivotTo(CFrame.new(position + Vector3.new(math.cos(angle) * OFFSET, 0, math.sin(angle) * OFFSET)))
end

function BaitDummy:Destroy()
	self.model:Destroy()
end

return BaitDummy
