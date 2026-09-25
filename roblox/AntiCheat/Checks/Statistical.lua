local Config = require(script.Parent.Parent.Config)
local Registry = require(script.Parent.Parent.Core.Registry)
local TrustService = require(script.Parent.Parent.Core.TrustService)

local T = Config.Thresholds

-- compares players against their own history instead of one global number.
-- games can feed it anything: reaction time, aim snap angle, clicks per second...
local Statistical = { Name = "Statistical", Rate = "cold" }

local MIN_BASELINE = 40
local Z_LIMIT = 4
local ACCURACY_WINDOW = 30

-- welford, so we never store samples
function Statistical.Record(player, name, value, lowerIsSuspicious)
	local profile = Registry.Get(player)
	if not profile or profile.admin or type(value) ~= "number" or value ~= value then
		return
	end
	if type(name) ~= "string" or #name > 32 then
		return
	end

	local s = profile.stats[name]
	if not s then
		profile.statCount = (profile.statCount or 0) + 1
		if profile.statCount > 32 then
			return
		end
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
				s.strikes += 1
				-- one weird sample is nothing, a streak is something. and don't learn from it
				if s.strikes >= 3 then
					s.strikes = 0
					TrustService.Flag(profile, "Statistical", 10, { stat = name, z = z, value = value, mean = s.mean })
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

function Statistical.Step(profile, now)
	local c = profile.combat
	if c.attempts >= ACCURACY_WINDOW then
		local accuracy = c.hits / c.attempts
		if accuracy > T.AccuracyCap then
			TrustService.Flag(profile, "Statistical", 12, { stat = "Accuracy", accuracy = accuracy, shots = c.attempts })
		end
		Statistical.Record(profile.player, "Accuracy", accuracy)
		c.attempts, c.hits, c.windowAt = 0, 0, now
	end
end

return Statistical
