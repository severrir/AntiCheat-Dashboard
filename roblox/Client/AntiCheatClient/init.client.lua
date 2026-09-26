local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"))

-- same deal as the server: if your client already boots Framework, add
-- Framework.AddDeep(<this script>.Controllers) to your own boot instead
Framework.AddDeep(script.Controllers)
Framework.Start()
