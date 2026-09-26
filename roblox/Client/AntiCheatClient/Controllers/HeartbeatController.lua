local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local HeartbeatController = { Name = "ACHeartbeatController" }

local INTERVAL = 5

function HeartbeatController:Init()
	self._beat = Net.Event("ACBeat")
	self._seq = 0
end

function HeartbeatController:_report()
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {
		ws = hum and hum.WalkSpeed or nil,
		jv = hum and (if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight)) or nil,
		g = workspace.Gravity,
		hum = if char then hum ~= nil else nil,
	}
end

function HeartbeatController:Start()
	while true do
		self._seq += 1
		self._beat:FireServer(self._seq, self:_report())
		task.wait(INTERVAL)
	end
end

return HeartbeatController
