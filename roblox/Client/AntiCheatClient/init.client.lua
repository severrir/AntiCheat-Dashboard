local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"))

-- same deal as the server: if your client already boots Framework, Add this script there instead
Framework.Add(script)
Framework.Start()
