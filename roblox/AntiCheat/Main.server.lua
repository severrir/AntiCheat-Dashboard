local root = script.Parent

local Registry = require(root.Core.Registry)
local Backend = require(root.Net.Backend)
local Bans = require(root.Response.Bans)
local Scheduler = require(root.Scheduler)

Registry.Init()
Bans.Init()

-- drop a module in Checks/ with Init and/or Step and it's picked up automatically
for _, module in root.Checks:GetChildren() do
	if module:IsA("ModuleScript") then
		local check = require(module)
		if check.Init then
			check.Init()
		end
		if check.Step then
			Scheduler.Add(check)
		end
	end
end

Registry.Removing:Connect(Backend.NoteLeft)

Scheduler.Start()
Backend.Start()
