local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Check = require(AC.Classes.Check)
local Framework = require(ReplicatedStorage.Shared.Framework)

local T = Config.Thresholds

-- compares players against their own history instead of one global number.
-- games can feed it anything through the API: reaction time, aim snap angle, clicks per second...
local StatsService = Check.extend({
	Name = "ACStatsService",
	Category = "Statistical",
	Feature = "Statistical",
	Rate = "cold",
})

local MIN_BASELINE = 40
local Z_LIMIT = 4
local ACCURACY_WINDOW = 30
local MAX_STATS = 32

function StatsService:OnStart()
	self._players = Framework.Get("ACPlayerService")
end

-- welford, so no samples are stored
function StatsService:Record(player, name, value, lowerIsSuspicious)
	if not self:IsEnabled() then
		return
	end
	local profile = self._players:Get(player)
	if not profile or profile.admin or type(value) ~= "number" or value ~= value then
		return
	end
	if type(name) ~= "string" or #name > 32 then
		return
	end

	local s = profile.stats[name]
	if not s then
		if profile.statCount >= MAX_STATS then
			return
		end
		profile.statCount += 1
		s = { n = 0, mean = 0, m2 = 0, strikes = 0 }
		profile.stats[name] = s
	end

	if s.n >= MIN_BASELINE then
		local sd = math.sqrt(s.m2 / (s.n - 1))
		if sd > 1e-6 then
			local z = (value - s.mean) / sd
			if lowerIsSuspicious then
				z = -z
			end
			if z > Z_LIMIT then
				-- one weird sample is nothing, a streak is something. and don't learn from it
				s.strikes += 1
				if s.strikes >= 3 then
					s.strikes = 0
					self:Flag(profile, 10, { kind = "Outlier", stat = name, z = z, value = value, mean = s.mean })
				end
				return
			end
		end
	end
	s.strikes = math.max(0, s.strikes - 1)

	s.n += 1
	local d = value - s.mean
	s.mean += d / s.n
	s.m2 += d * (value - s.mean)
end

function StatsService:Step(profile)
	local c = profile.combat
	if c.attempts >= ACCURACY_WINDOW then
		local accuracy = c.hits / c.attempts
		if accuracy > T.AccuracyCap then
			self:Flag(profile, 12, { kind = "Accuracy", accuracy = accuracy, shots = c.attempts })
		end
		self:Record(profile.player, "Accuracy", accuracy)
		c.attempts, c.hits = 0, 0
	end
end

return StatsService
