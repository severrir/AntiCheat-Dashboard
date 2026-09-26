local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Check = require(AC.Classes.Check)
local MovementModel = require(AC.Classes.MovementModel)
local Physics = require(AC.Util.Physics)
local Framework = require(ReplicatedStorage.Shared.Framework)

local T = Config.Thresholds
local State = Enum.HumanoidStateType
local DOWN = Vector3.new(0, -1, 0)

-- roblox side of the movement check: reads the character, asks the player's MovementModel,
-- snaps them back. speed, teleport, blink, fly, super jump, noclip
local MovementService = Check.extend({
	Name = "ACMovementService",
	Category = "Movement",
	Feature = "Movement",
	Rate = "hot",
})

-- point buried inside a block part, not just touching it. the root is 2 studs wide,
-- so a real player's center never gets this deep into a wall
local DEEP = 0.5
local function buried(part, point)
	if not (part:IsA("Part") and part.Shape == Enum.PartType.Block) then
		return false
	end
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	return math.abs(p.X) < h.X - DEEP and math.abs(p.Y) < h.Y - DEEP and math.abs(p.Z) < h.Z - DEEP
end

local env = {
	-- solid thing between two points, checked from both sides (a real wall, not a grazed corner).
	-- a slow walk through a thin wall can land a sample inside it and rays don't hit from the
	-- inside, so ending up buried in the part we hit counts too
	wall = function(ax, ay, az, bx, by, bz)
		local a, b = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)
		local forward = Physics.Cast(a, b - a)
		if not forward then
			return false
		end
		if buried(forward.Instance, b) then
			return true, forward.Instance.Name
		end
		local back = Physics.Cast(b, a - b)
		if back and back.Instance == forward.Instance then
			return true, forward.Instance.Name
		end
		return false
	end,
}

local function snapBack(profile)
	local root = profile.root
	local x, y, z = profile.move:SnapTarget()
	local rot = root.CFrame - root.Position
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(x, y, z) * rot
end

function MovementService:OnStart()
	self._vault = Framework.Get("ACVaultService")
end

function MovementService:Step(profile, now)
	if not profile:Alive() then
		return
	end
	local root, hum = profile.root, profile.humanoid
	local pos = root.Position
	if self._vault:Catch(profile, pos) then
		return
	end
	if profile.vaultWatch and now >= profile.vaultWatch then
		profile.vaultWatch = nil
	end

	-- vehicles, exemptions, server hiccups: just follow along
	local model = profile.move
	if not model or hum.SeatPart or profile:IsExempt("Movement", now) or now - model.lt > 1 then
		profile.move = MovementModel.new(pos.X, pos.Y, pos.Z, now)
		return
	end

	local ground = Physics.Cast(pos, DOWN * (hum.HipHeight + T.FlyHeight + 3))
	local platform = 0
	if ground then
		local v = ground.Instance.AssemblyLinearVelocity
		platform = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local state = hum:GetState()
	local climbing = state == State.Climbing or state == State.Swimming

	local from = Vector3.new(model.lx, model.ly, model.lz)
	local verdict, allowed = model:Step({
		t = now,
		x = pos.X, y = pos.Y, z = pos.Z,
		walkSpeed = hum.WalkSpeed,
		jumpSpeed = if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight),
		grounded = ground ~= nil,
		climbing = climbing,
		platform = platform,
	}, T, env)

	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	-- a negative allowed marks the sample right after one of our snapbacks,
	-- so replay and forensics don't count our own yank as their movement
	local marker = if profile.afterSnap then -1 else 1
	profile.afterSnap = verdict ~= nil
	profile:Record(now, pos, yaw, math.max(allowed, 1) * marker, ground ~= nil or climbing)

	if profile.admin then
		-- admins are only recorded (for test sessions), never judged
		profile.move = MovementModel.new(pos.X, pos.Y, pos.Z, now)
		profile.afterSnap = false
		return
	end
	if not verdict then
		return
	end

	-- already on their way into the vault, it'll catch them when they land
	if profile.vaultWatch then
		return
	end
	-- the server smooths big client teleports, so a jump into the vault arrives as a few steps
	-- headed at it. hold the snapback a moment so they land and trip it. once per 10s at most,
	-- so running at the vault can't buy free time over and over
	if
		(verdict.kind == "Teleport" or verdict.kind == "Speed")
		and now - (profile.vaultWatchAt or -math.huge) > 10
		and self._vault:IsHeadingIn(from, pos)
	then
		profile.vaultWatch = now + 1.5
		profile.vaultWatchAt = now
	end

	-- counted before flagging so enforcement sees this one when it decides
	profile.moveViolations:Push(now)
	self:Flag(profile, verdict.severity, {
		kind = verdict.kind,
		speed = verdict.ctx.speed,
		allowed = verdict.ctx.allowed,
		dist = verdict.ctx.dist,
		air = verdict.ctx.air,
		rise = verdict.ctx.rise,
		part = verdict.ctx.part,
	})
	if not profile.vaultWatch then
		snapBack(profile)
	end
end

return MovementService
