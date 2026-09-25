local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

-- tells the server what this client sees. an exploiter can fake all of it,
-- the point is the server notices when it stops or doesn't add up
local Heartbeat = { Name = "ACClientBeat" }

function Heartbeat:Start()
	local player = Players.LocalPlayer
	local beat = Net.Event("ACBeat")
	local seq = 0
	while true do
		seq += 1
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		beat:FireServer(seq, {
			ws = hum and hum.WalkSpeed or nil,
			-- launch speed, so flipping UseJumpPower locally doesn't hide a boost
			jv = hum and (if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight)) or nil,
			g = workspace.Gravity,
			hum = if char then hum ~= nil else nil,
		})
		task.wait(5)
	end
end

return Heartbeat
