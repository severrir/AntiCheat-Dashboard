local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function findRemote()
	local deadline = os.clock() + 60
	while os.clock() < deadline do
		for _, child in ReplicatedStorage:GetChildren() do
			if child:IsA("RemoteEvent") and child:GetAttribute("ci") then
				return child
			end
		end
		task.wait(0.5)
	end
	return nil
end

local remote = findRemote()
if not remote then
	return
end

local seq = 0
while true do
	seq += 1
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	remote:FireServer(seq, {
		ws = hum and hum.WalkSpeed or nil,
		jp = hum and hum.JumpPower or nil,
		jh = hum and hum.JumpHeight or nil,
		g = workspace.Gravity,
		hum = if char then hum ~= nil else nil,
	})
	task.wait(5)
end
