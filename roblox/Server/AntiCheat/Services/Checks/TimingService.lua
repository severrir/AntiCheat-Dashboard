local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Check = require(AC.Classes.Core.Check)
local RingBuffer = require(AC.Classes.Core.RingBuffer)

local T = Config.Thresholds

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
