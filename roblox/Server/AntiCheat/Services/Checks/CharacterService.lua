local AC = script:FindFirstAncestor("AntiCheat")
local Check = require(AC.Classes.Check)

-- humanoid deleted or swapped, health above max, root resized, limbs gone
local CharacterService = Check.extend({
	Name = "ACCharacterService",
	Category = "Character",
	Feature = "Character",
	Rate = "hot",
})

local function countParts(char)
	local parts = 0
	for _, d in char:GetChildren() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end

-- the character is in a state we can't trust anymore, give them a fresh one
local function respawn(profile)
	profile:UnbindCharacter()
	task.defer(function()
		if profile.player.Parent then
			profile.player:LoadCharacter()
		end
	end)
end

function CharacterService:Step(profile, now)
	local char, hum, root = profile.char, profile.humanoid, profile.root
	if profile.immune or not char or not hum or not root or char.Parent == nil then
		return
	end
	if profile:IsExempt("Character", now) then
		return
	end

	-- deleting or swapping the humanoid is the classic godmode
	if hum.Parent ~= char then
		if char:FindFirstChildOfClass("Humanoid") or hum.Health > 0 then
			self:Flag(profile, 35, { kind = "HumanoidSwap" })
			respawn(profile)
		end
		return
	end
	if hum.Health <= 0 then
		return
	end

	if hum.Health > hum.MaxHealth + 0.01 then
		self:Flag(profile, 30, { kind = "Godmode", hp = hum.Health, max = hum.MaxHealth })
		hum.Health = hum.MaxHealth
		return
	end

	if root.Parent ~= char then
		self:Flag(profile, 25, { kind = "RootRemoved" })
		respawn(profile)
		return
	end

	-- avatar loading scales the root and swaps limbs, so wait before taking a baseline
	if not profile.partCount then
		if now - (profile.boundAt or now) < 5 then
			return
		end
		profile.partCount = countParts(char)
		profile.rootSize = root.Size
		profile.lastLimbCheck = now
		return
	end

	if root.Size ~= profile.rootSize then
		self:Flag(profile, 25, { kind = "RootResized" })
		root.Size = profile.rootSize
		return
	end

	-- GetChildren isn't free, every couple of seconds is plenty
	if now - profile.lastLimbCheck > 2 then
		profile.lastLimbCheck = now
		local parts = countParts(char)
		if parts < profile.partCount then
			self:Flag(profile, 15, { kind = "LimbRemoved", parts = parts, expected = profile.partCount })
			profile.partCount = parts
		end
	end
end

return CharacterService
