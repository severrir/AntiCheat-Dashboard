local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Physics = require(AC.Lib.Physics)
local MovementModel = require(AC.Lib.MovementModel)
local Framework = require(ReplicatedStorage.Shared.Framework)

local T = Config.Thresholds
local State = Enum.HumanoidStateType
local DOWN = Vector3.new(0, -1, 0)

-- roblox side of the movement check: reads the character, asks MovementModel, snaps them back
local Movement = { Name = "ACMovement", Feature = "Movement", Rate = "hot" }

local Trust
local Vault

local env = {
	-- solid thing between two points, checked from both sides (a real wall, not a grazed corner)
	wall = function(ax, ay, az, bx, by, bz)
		local a, b = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)
		local forward = Physics.Cast(a, b - a)
		if not forward then
			return false
		end
		local back = Physics.Cast(b, a - b)
		if back and back.Instance == forward.Instance then
			return true, forward.Instance.Name
		end
		return false
	end,
}

local function snapBack(profile, s, now)
	local root = profile.root
	local rot = root.CFrame - root.Position
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(s.lx, s.ly, s.lz) * rot
	profile.moveViolations:Push(now)
end

function Movement.Step(profile, now)
	if not profile:Alive() then
		return
	end
	local root, hum = profile.root, profile.humanoid
	local pos = root.Position
	if Config.On("TrapVault") and Vault.Check(profile, pos) then
		return
	end

	-- vehicles, exemptions: just follow along
	if not profile.move or hum.SeatPart or profile:IsExempt("Movement", now) then
		profile.move = MovementModel.new(pos.X, pos.Y, pos.Z, now)
		return
	end
	if now - profile.move.lt > 1 then
		-- server hiccup, not the player's fault
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

	local s = profile.move
	local verdict, allowed = MovementModel.step(s, {
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
		-- admins are only recorded (for /acrecord test sessions), never judged
		profile.move = MovementModel.new(pos.X, pos.Y, pos.Z, now)
		profile.afterSnap = false
		return
	end

	if verdict then
		Trust.Flag(profile, "Movement", verdict.severity, {
			kind = verdict.kind,
			speed = verdict.ctx.speed,
			allowed = verdict.ctx.allowed,
			dist = verdict.ctx.dist,
			air = verdict.ctx.air,
			rise = verdict.ctx.rise,
			part = verdict.ctx.part,
		})
		snapBack(profile, s, now)
	end
end

function Movement:Start()
	Trust = Framework.Get("ACTrust")
	Vault = Framework.Get("ACVault")
	Framework.Get("ACScheduler").Add(Movement)
end

return Movement
