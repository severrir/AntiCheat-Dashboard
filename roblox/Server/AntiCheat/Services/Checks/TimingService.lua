local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Check = require(AC.Classes.Check)
local RingBuffer = require(AC.Classes.RingBuffer)

local T = Config.Thresholds

-- humans are messy. a macro firing a remote every 100ms on the dot is not.
-- looks at the gaps between calls to each Net remote and flags when they're way too even
local TimingService = Check.extend({
	Name = "ACTimingService",
	Category = "Timing",
	Feature = "Timing",
	Rate = "cold",
})

local SAMPLES = 48
local MIN_SAMPLES = 40
local MIN_RATE = 5
local MAX_KEYS = 64

-- NetGuardService calls this for every remote call that got through
function TimingService:Record(profile, key, now)
	local entry = profile.timing[key]
	if not entry then
		profile.timingKeys = (profile.timingKeys or 0) + 1
		if profile.timingKeys > MAX_KEYS then
			return
		end
		profile.timing[key] = { last = now, gaps = RingBuffer.new(SAMPLES) }
		return
	end
	local gap = now - entry.last
	entry.last = now
	-- a long pause isn't part of the same burst
	if gap > 1 then
		entry.gaps:Clear()
		return
	end
	entry.gaps:Push(gap)
end

function TimingService:Step(profile)
	for key, entry in profile.timing do
		local gaps = entry.gaps
		local n = gaps.count
		if n >= MIN_SAMPLES then
			local sum, sq = 0, 0
			for i = 1, n do
				local g = gaps:Get(i)
				sum += g
				sq += g * g
			end
			local mean = sum / n
			local cv = if mean > 0 then math.sqrt(math.max(sq / n - mean * mean, 0)) / mean else 0
			if mean > 0 and 1 / mean >= MIN_RATE and cv < T.TimingMinCV then
				self:Flag(profile, 12, { kind = "Macro", remote = key, cv = cv, rate = 1 / mean })
			end
			gaps:Clear()
		end
	end
end

return TimingService
