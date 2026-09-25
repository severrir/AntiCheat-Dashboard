local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"))

-- if your game already boots Framework itself, delete this script and put this line in your
-- own boot before Framework.Start():
--   Framework.AddDeep(game.ServerScriptService.AntiCheat.Systems)
Framework.AddDeep(script.Parent.Systems)
Framework.Start()
