local TrustService = require(script.Parent.Parent.Core.TrustService)

local Character = { Name = "Character", Rate = "hot" }

local function respawn(profile)
	-- the character is in a state we can't trust anymore, give them a fresh one
	profile:UnbindCharacter()
	task.defer(function()
		if profile.player.Parent then
			profile.player:LoadCharacter()
		end
	end)
end

function Character.Step(profile, now)
	local char, hum, root = profile.char, profile.humanoid, profile.root
	if not char or not hum or not root then
		return
	end
	if char.Parent == nil then
		return
	end
	if profile:IsExempt("Character", now) then
		return
	end

	-- deleting or swapping the humanoid is the classic godmode
	if hum.Parent ~= char then
		if char:FindFirstChildOfClass("Humanoid") or hum.Health > 0 then
			TrustService.Flag(profile, "Character", 35, { kind = "HumanoidSwap" })
			respawn(profile)
		end
		return
	end
	if hum.Health <= 0 then
		return
	end

	if hum.Health > hum.MaxHealth + 0.01 then
		TrustService.Flag(profile, "Character", 30, { kind = "Godmode", hp = hum.Health, max = hum.MaxHealth })
		hum.Health = hum.MaxHealth
		return
	end

	if root.Parent ~= char then
		TrustService.Flag(profile, "Character", 25, { kind = "RootRemoved" })
		respawn(profile)
		return
	end

	if profile.rootSize and root.Size ~= profile.rootSize then
		TrustService.Flag(profile, "Character", 25, { kind = "RootResized" })
		root.Size = profile.rootSize
		return
	end

	-- only check limbs every so often, GetChildren isn't free
	if now - (profile.lastLimbCheck or 0) > 2 then
		profile.lastLimbCheck = now
		local parts = 0
		for _, d in char:GetChildren() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		if profile.partCount and parts < profile.partCount then
			TrustService.Flag(profile, "Character", 15, { kind = "LimbRemoved", parts = parts, expected = profile.partCount })
			profile.partCount = parts
		end
	end
end

return Character
