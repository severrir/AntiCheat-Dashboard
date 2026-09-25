local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- instead of checking everyone every frame, owe each player N checks per second
-- and pay that off a few players per frame. 50 players at 10hz = ~8 per frame
local Scheduler = { Name = "ACScheduler" }

local hot = { checks = {}, rate = Config.HotRate, debt = 0, index = 1 }
local cold = { checks = {}, rate = Config.ColdRate, debt = 0, index = 1 }

-- a check is { Name, Feature, Rate = "hot" | "cold", Step = function(profile, now) }
function Scheduler.Add(check)
	table.insert(if check.Rate == "cold" then cold.checks else hot.checks, check)
end

local function run(lane, list, dt, now)
	local n = #list
	if n == 0 or #lane.checks == 0 then
		lane.debt = 0
		return
	end
	lane.debt = math.min(lane.debt + dt * lane.rate * n, n)
	local steps = math.floor(lane.debt)
	lane.debt -= steps

	for _ = 1, steps do
		if lane.index > n then
			lane.index = 1
		end
		local profile = list[lane.index]
		lane.index += 1
		if not profile.kicked and profile.player.Parent then
			for _, check in lane.checks do
				if Config.On(check.Feature or check.Name) then
					local ok, err = pcall(check.Step, profile, now)
					if not ok then
						warn("[AntiCheat]", check.Name, err)
					end
				end
			end
		end
	end
end

function Scheduler:Start()
	local PlayerService = Framework.Get("ACPlayers")
	RunService.Heartbeat:Connect(function(dt)
		local list = PlayerService.List()
		local now = os.clock()
		run(hot, list, dt, now)
		run(cold, list, dt, now)
	end)
end

return Scheduler
