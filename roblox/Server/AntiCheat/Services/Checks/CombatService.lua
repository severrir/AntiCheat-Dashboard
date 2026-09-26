local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Physics = require(AC.Util.Physics)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- your weapon code asks this before applying damage. never trust "i hit him" from the client
local CombatService = { Name = "ACCombatService" }

local EYE = Vector3.new(0, 1.5, 0)

local function rootOf(target)
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Player") then
		target = target.Character
	elseif target:IsA("Humanoid") or target:IsA("BasePart") then
		target = target:FindFirstAncestorOfClass("Model")
	end
	if target and target:IsA("Model") then
		local hum = target:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart, target
		end
	end
	return nil
end

function CombatService:_flag(profile, severity, ctx)
	self._trust:Flag(profile, "Combat", severity, ctx)
end

-- opts: Range, Cooldown, Weapon, LineOfSight (default true)
function CombatService:ValidateHit(attacker, victim, opts)
	opts = opts or {}
	local profile = self._players:Get(attacker)
	if not profile or profile.kicked or not profile:Alive() then
		return false
	end

	local targetRoot, targetModel = rootOf(victim)
	-- nobody can see or reach the bait. hitting it means aimbot or kill aura
	if targetModel and self._bait:IsBait(targetModel) then
		self._bait:Tripped(profile, "hit")
		return false
	end
	if profile.admin or not Config.On("Combat") then
		return targetRoot ~= nil
	end

	local now = os.clock()
	local c = profile.combat
	c.attempts += 1

	local weapon = opts.Weapon or "default"
	local cooldown = opts.Cooldown or 0.3
	local last = c.last[weapon]
	-- 15% slack for network jitter
	if last and now - last < cooldown * 0.85 then
		self:_flag(profile, 6, { kind = "Cooldown", weapon = weapon, gap = now - last })
		return false
	end

	if not targetRoot then
		return false
	end
	local origin = profile.root.Position + EYE
	local offset = targetRoot.Position - origin
	local dist = offset.Magnitude

	-- the victim kept moving while the packet was in flight
	local ping = math.min(attacker:GetNetworkPing() * 2, 0.5)
	local range = (opts.Range or 12) + targetRoot.AssemblyLinearVelocity.Magnitude * ping + 3
	if dist > range then
		self:_flag(profile, math.clamp((dist - range) / 2, 5, 20), { kind = "Range", weapon = weapon, dist = dist, range = range })
		return false
	end

	if opts.LineOfSight ~= false and dist > 0.5 then
		local hit = Physics.Cast(origin, offset)
		if hit and not hit.Instance:IsDescendantOf(targetModel) then
			self:_flag(profile, 8, { kind = "ThroughWall", weapon = weapon, part = hit.Instance.Name })
			return false
		end
	end

	c.hits += 1
	c.last[weapon] = now
	return true
end

-- call on swings that hit nothing too, otherwise accuracy stats mean nothing
function CombatService:RecordMiss(attacker)
	local profile = self._players:Get(attacker)
	if profile then
		profile.combat.attempts += 1
	end
end

function CombatService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._trust = Framework.Get("ACTrustService")
	self._bait = Framework.Get("ACBaitNpcService")
end

return CombatService
