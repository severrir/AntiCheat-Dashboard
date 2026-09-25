local Physics = require(script.Parent.Parent.Core.Physics)
local Registry = require(script.Parent.Parent.Core.Registry)
local TrustService = require(script.Parent.Parent.Core.TrustService)

-- your weapon code asks this before applying damage. never trust "i hit him" from the client
local Combat = { Name = "Combat" }

local EYE = Vector3.new(0, 1.5, 0)

local function rootOf(target)
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Player") then
		target = target.Character
	elseif target:IsA("Humanoid") then
		target = target.Parent
	end
	if target and target:IsA("Model") then
		local hum = target:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart, target
		end
	end
	return nil
end

-- opts: Range, Cooldown, Weapon, LineOfSight (default true)
function Combat.ValidateHit(attacker, victim, opts)
	opts = opts or {}
	local profile = Registry.Get(attacker)
	if not profile or profile.kicked or not profile:Alive() then
		return false
	end
	if profile.admin then
		return true
	end

	local now = os.clock()
	local c = profile.combat
	c.attempts += 1

	local weapon = opts.Weapon or "default"
	local cooldown = opts.Cooldown or 0.3
	local last = c.last[weapon]
	-- 15% slack for network jitter
	if last and now - last < cooldown * 0.85 then
		TrustService.Flag(profile, "Combat", 6, { kind = "Cooldown", weapon = weapon, gap = now - last })
		return false
	end

	local targetRoot, targetModel = rootOf(victim)
	if not targetRoot then
		return false
	end
	local origin = profile.root.Position + EYE
	local offset = targetRoot.Position - origin
	local dist = offset.Magnitude

	-- the victim moved while the packet was in flight, allow for that
	local ping = math.min(attacker:GetNetworkPing() * 2, 0.5)
	local range = (opts.Range or 12) + targetRoot.AssemblyLinearVelocity.Magnitude * ping + 3
	if dist > range then
		TrustService.Flag(profile, "Combat", math.clamp((dist - range) / 2, 5, 20), {
			kind = "Range",
			weapon = weapon,
			dist = dist,
			range = range,
		})
		return false
	end

	if opts.LineOfSight ~= false and dist > 0.5 then
		local hit = Physics.Cast(origin, offset)
		if hit and not hit.Instance:IsDescendantOf(targetModel) then
			TrustService.Flag(profile, "Combat", 8, { kind = "ThroughWall", weapon = weapon, part = hit.Instance.Name })
			return false
		end
	end

	c.hits += 1
	c.last[weapon] = now
	return true
end

-- call on misses too, otherwise accuracy stats are meaningless
function Combat.RecordMiss(attacker)
	local profile = Registry.Get(attacker)
	if profile then
		profile.combat.attempts += 1
	end
end

return Combat
