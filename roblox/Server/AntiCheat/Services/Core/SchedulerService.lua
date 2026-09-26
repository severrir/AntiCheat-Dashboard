local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- instead of checking everyone every frame, owe each player N checks per second
-- and pay that off a few players per frame. 50 players at 10hz = ~8 per frame
local SchedulerService = { Name = "ACSchedulerService" }

local Lane = {}
Lane.__index = Lane

function Lane.new(rate)
	return setmetatable({ checks = {}, rate = rate, debt = 0, index = 1 }, Lane)
end

function Lane:Run(list, dt, now)
	local n = #list
	if n == 0 or #self.checks == 0 then
		self.debt = 0
		return
	end
	self.debt = math.min(self.debt + dt * self.rate * n, n)
	local steps = math.floor(self.debt)
	self.debt -= steps

	for _ = 1, steps do
		if self.index > n then
			self.index = 1
		end
		local profile = list[self.index]
		self.index += 1
		if not profile.kicked and profile.player.Parent then
			for _, check in self.checks do
				if check:IsEnabled() then
					local ok, err = pcall(check.Step, check, profile, now)
					if not ok then
						warn("[AntiCheat]", check.Name, err)
					end
				end
			end
		end
	end
end

function SchedulerService:Init()
	self._hot = Lane.new(Config.HotRate)
	self._cold = Lane.new(Config.ColdRate)
end

-- any Check (see Classes/Check). Start registers them automatically
function SchedulerService:Add(check)
	local lane = if check.Rate == "cold" then self._cold else self._hot
	table.insert(lane.checks, check)
end

function SchedulerService:Start()
	local players = Framework.Get("ACPlayerService")
	RunService.Heartbeat:Connect(function(dt)
		local list = players:List()
		local now = os.clock()
		self._hot:Run(list, dt, now)
		self._cold:Run(list, dt, now)
	end)
end

return SchedulerService
