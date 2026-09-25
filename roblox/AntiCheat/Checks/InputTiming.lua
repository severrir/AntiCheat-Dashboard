local Config = require(script.Parent.Parent.Config)
local RingBuffer = require(script.Parent.Parent.Core.RingBuffer)
local TrustService = require(script.Parent.Parent.Core.TrustService)

local T = Config.Thresholds

-- humans are messy. a macro firing a remote every 100ms on the dot is not.
-- we look at the gaps between calls and flag when they're way too even
local InputTiming = { Name = "Timing", Rate = "cold" }

local SAMPLES = 48
local MIN_SAMPLES = 40
local MIN_RATE = 5

function InputTiming.Record(profile, key, now)
	local entry = profile.timing[key]
	if not entry then
		entry = { last = now, gaps = RingBuffer.new(SAMPLES) }
		profile.timing[key] = entry
		return
	end
	local gap = now - entry.last
	entry.last = now
	-- long pauses aren't part of a burst, start over
	if gap > 1 then
		entry.gaps:Clear()
		return
	end
	entry.gaps:Push(gap)
end

function InputTiming.Step(profile)
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
			local variance = math.max(sq / n - mean * mean, 0)
			local cv = if mean > 0 then math.sqrt(variance) / mean else 0

			if mean > 0 and 1 / mean >= MIN_RATE and cv < T.TimingMinCV then
				TrustService.Flag(profile, "Timing", 12, { remote = key, cv = cv, rate = 1 / mean })
			end
			gaps:Clear()
		end
	end
end

return InputTiming
