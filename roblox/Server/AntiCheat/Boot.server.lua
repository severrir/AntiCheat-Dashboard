local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"))

-- if your game already boots Framework itself, delete this script and add this line to your
-- own server boot before Framework.Start():
--   Framework.AddDeep(game.ServerScriptService.AntiCheat.Services)
Framework.AddDeep(script.Parent.Services)
Framework.Start()
