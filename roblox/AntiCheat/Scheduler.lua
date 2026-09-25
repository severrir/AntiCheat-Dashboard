local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Registry = require(script.Parent.Core.Registry)

local Scheduler = {}

-- instead of checking everyone every frame, owe each player N checks per second
-- and pay that debt a few players per frame. 50 players at 10hz = ~8 per frame
local function lane(rate)
	return { checks = {}, rate = rate, debt = 0, index = 1 }
end

local hot = lane(Config.HotRate)
local cold = lane(Config.ColdRate)

function Scheduler.Add(check)
	local target = if check.Rate == "cold" then cold else hot
	table.insert(target.checks, check)
end

local function run(l, list, dt, now)
	local n = #list
	if n == 0 or #l.checks == 0 then
		l.debt = 0
		return
	end
	l.debt = math.min(l.debt + dt * l.rate * n, n)
	local steps = math.floor(l.debt)
	l.debt -= steps

	for _ = 1, steps do
		if l.index > n then
			l.index = 1
		end
		local profile = list[l.index]
		l.index += 1
		if not profile.admin and not profile.kicked and profile.player.Parent then
			for _, check in l.checks do
				local ok, err = pcall(check.Step, profile, now)
				if not ok then
					warn("[AntiCheat]", check.Name, err)
				end
			end
		end
	end
end

function Scheduler.Start()
	RunService.Heartbeat:Connect(function(dt)
		local list = Registry.List()
		local now = os.clock()
		run(hot, list, dt, now)
		run(cold, list, dt, now)
	end)
end

return Scheduler
