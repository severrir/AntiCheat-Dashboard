local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"))

Framework.AddDeep(script.Parent.Services)
Framework.Start()
