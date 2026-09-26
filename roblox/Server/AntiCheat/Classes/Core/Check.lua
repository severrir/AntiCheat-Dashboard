local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script:FindFirstAncestor("AntiCheat").Settings.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

local Check = {}
Check.__index = Check

function Check.extend(def)
	assert(def.Name, "a check needs a Name")
	def.Category = def.Category or def.Feature
	def.Rate = def.Rate or "hot"
	def.__index = def
	return setmetatable(def, Check)
end

function Check:Start()
	self.Trust = Framework.Get("ACTrustService")
	Framework.Get("ACSchedulerService"):Add(self)
	if self.OnStart then
		self:OnStart()
	end
end

function Check:IsEnabled()
	return Config.On(self.Feature or self.Category)
end

function Check:Flag(profile, severity, ctx)
	self.Trust:Flag(profile, self.Category, severity, ctx)
end

function Check:Step(_profile, _now)
	error(`[AntiCheat] {self.Name} is missing Step`)
end

return Check
