local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

-- a shiny "Coin" floating way out of reach. auto farm scripts grab anything called Coin,
-- real players never get close. also wraps parts named ACCoin that you place yourself
local BaitCoin = {}
BaitCoin.__index = BaitCoin

function BaitCoin.spawnAt(position, onGrab)
	local part = Instance.new("Part")
	part.Name = "Coin"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.4, 3, 3)
	part.Color = Color3.fromRGB(255, 205, 60)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	CollectionService:AddTag(part, "ACInternal")
	part.Parent = workspace
	return BaitCoin.wrap(part, onGrab, true)
end

-- owned = we made it and should delete it later
function BaitCoin.wrap(part, onGrab, owned)
	local self = setmetatable({ part = part, owned = owned == true }, BaitCoin)
	self.connection = part.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then
			onGrab(player)
		end
	end)
	return self
end

function BaitCoin:Destroy()
	self.connection:Disconnect()
	if self.owned then
		self.part:Destroy()
	end
end

return BaitCoin
