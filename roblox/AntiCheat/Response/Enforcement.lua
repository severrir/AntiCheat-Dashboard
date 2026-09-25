local Config = require(script.Parent.Parent.Config)
local SignalBus = require(script.Parent.Parent.Core.SignalBus)
local Backend = require(script.Parent.Parent.Net.Backend)
local ForensicReplay = require(script.Parent.ForensicReplay)

local T = Config.Thresholds

local Enforcement = {}

local function reasonText(breakdown)
	local parts = {}
	for i = 1, math.min(3, #breakdown) do
		table.insert(parts, string.format("%s %d", breakdown[i].check, breakdown[i].value))
	end
	return table.concat(parts, ", ")
end

-- kick only. bans are a human decision, made from the dashboard
function Enforcement.Evaluate(profile, now)
	if profile.kicked then
		return
	end
	local score = profile:Score(now)
	if score < T.KickScore then
		return
	end

	local breakdown = profile:Breakdown(now)
	local definitive = false
	local distinct = 0
	for _, part in breakdown do
		if Config.Definitive[part.check] and part.value >= T.KickScore * 0.5 then
			definitive = true
		end
		if part.value >= T.KickScore * 0.1 then
			distinct += 1
		end
	end

	if not definitive then
		-- movement can prove itself through replay, so it doesn't need a second check
		local confirmed = ForensicReplay.Confirm(profile, breakdown, now)
		if not confirmed then
			profile:Scale(0.5, now)
			return
		end
		-- anything else alone is too noisy, wait for another check to agree
		if distinct < T.MinCorroboratingChecks and breakdown[1].check ~= "Movement" then
			return
		end
	end

	profile.kicked = true
	local reason = reasonText(breakdown)
	Backend.QueueKick(profile, reason, score)
	SignalBus.Kicked:Fire(profile.player, reason, score)
	profile.player:Kick(Config.KickMessage)

	-- get the kick to the dashboard/discord now instead of waiting for the next tick
	task.defer(Backend.Sync)
end

return Enforcement
