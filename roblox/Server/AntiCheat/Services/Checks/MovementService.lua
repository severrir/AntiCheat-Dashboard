local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Check = require(AC.Classes.Core.Check)
local MovementModel = require(AC.Classes.Player.MovementModel)
local Physics = require(AC.Util.Physics)
local Framework = require(ReplicatedStorage.Shared.Framework)

local T = Config.Thresholds
local State = Enum.HumanoidStateType
local DOWN = Vector3.new(0, -1, 0)

local MovementService = Check.extend({
	Name = "ACMovementService",
	Category = "Movement",
	Feature = "Movement",
	Rate = "hot",
})

local DEEP = 0.1
local function buried(part, point)
	if not (part:IsA("Part") and part.Shape == Enum.PartType.Block) then
		return false
	end
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	return math.abs(p.X) < h.X - DEEP and math.abs(p.Y) < h.Y - DEEP and math.abs(p.Z) < h.Z - DEEP
end

local env = {
	wall = function(ax, ay, az, bx, by, bz)
		local a, b = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)
		local forward = Physics.Cast(a, b - a)
		if forward and buried(forward.Instance, b) then
			return true, forward.Instance.Name
		end
		local back = Physics.Cast(b, a - b)
		if not back then
			return false
		end
		if forward and back.Instance == forward.Instance then
			return true, forward.Instance.Name
		end
		if not forward and buried(back.Instance, a) then
			return true, back.Instance.Name
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

	local model = profile.move
	if not model or hum.SeatPart or profile:IsExempt("Movement", now) or now - model.lt > 1 then
		profile.move = MovementModel.new(pos.X, pos.Y, pos.Z, now)
		profile.afterSnap = true
		return
	end

	if #profile.teleports > 0 and profile:TakeTeleport(pos, now, true) then
		profile.move = MovementModel.new(pos.X, pos.Y, pos.Z, now)
		profile.afterSnap = true
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
	local jumpSpeed = if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
	local flySpeed = profile:Allowed("Fly", now)
	local flying = flySpeed ~= nil
	local verdict, allowed = model:Step({
		t = now,
		x = pos.X, y = pos.Y, z = pos.Z,
		walkSpeed = math.max(hum.WalkSpeed, profile:Allowed("Speed", now) or 0, flySpeed or 0),
		jumpSpeed = math.max(jumpSpeed, profile:Allowed("Jump", now) or 0),
		grounded = ground ~= nil,
		climbing = climbing,
		platform = platform,
		flying = flying,
		flySpeed = if flying and flySpeed > 0 then flySpeed else nil,
	}, T, env)

	local missed
	if verdict and verdict.kind ~= "Fly" and #profile.teleports > 0 then
		local _, miss = profile:TakeTeleport(pos, now)
		missed = miss
	end

	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local marker = if profile.afterSnap then -1 else 1
	profile.afterSnap = verdict ~= nil
	profile:Record(now, pos, yaw, math.max(allowed, 1) * marker, ground ~= nil or climbing)

	if profile.immune then
		profile.move = MovementModel.new(pos.X, pos.Y, pos.Z, now)
		profile.afterSnap = false
		return
	end
	if not verdict then
		return
	end

	if profile.vaultWatch then
		return
	end
	if
		(verdict.kind == "Teleport" or verdict.kind == "Speed")
		and now - (profile.vaultWatchAt or -math.huge) > 10
		and self._vault:IsHeadingIn(from, pos)
	then
		profile.vaultWatch = now + 1.5
		profile.vaultWatchAt = now
	end

	profile.moveViolations:Push(now)
	self:Flag(profile, verdict.severity, {
		kind = verdict.kind,
		speed = verdict.ctx.speed,
		allowed = verdict.ctx.allowed,
		dist = verdict.ctx.dist,
		air = verdict.ctx.air,
		rise = verdict.ctx.rise,
		part = verdict.ctx.part,
		missed = missed,
	})
	if not profile.vaultWatch then
		snapBack(profile)
	end
end

return MovementService
