local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Scoring = require(AC.Util.Scoring)
local Signal = require(AC.Classes.Signal)
local Framework = require(ReplicatedStorage.Shared.Framework)

local T = Config.Thresholds

-- decides when enough is enough. kicks only, bans are a human decision from the dashboard
local EnforcementService = {
	Name = "ACEnforcementService",
	Kicked = Signal.new(), -- (player, reason, score)
}

local function reasonText(breakdown)
	local parts = {}
	for i = 1, math.min(3, #breakdown) do
		table.insert(parts, string.format("%s %d", breakdown[i].check, breakdown[i].value))
	end
	return table.concat(parts, ", ")
end

-- the "which exploit tool was this" fingerprint: the distinct things they tripped
local function signature(profile)
	local seen, out = {}, {}
	for i = 1, profile.events.count do
		local e = profile.events:Get(i)
		local key = e.check .. ":" .. e.kind .. (if e.detail then " " .. e.detail else "")
		if not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	table.sort(out)
	return table.move(out, 1, math.min(#out, 12), 1, {})
end

-- movement proves itself: 3 violations in 10s, or the recorded path really was too fast
local function movementConfirmed(profile, now)
	local recent = 0
	for i = 1, profile.moveViolations.count do
		if now - profile.moveViolations:Get(i) < 10 then
			recent += 1
		end
	end
	return recent >= 3 or Scoring.worstWindow(profile.times, profile.xs, profile.zs, profile.allowed) > 1
end

function EnforcementService:Evaluate(profile, now)
	if profile.kicked then
		return
	end
	local score = profile:Score(now)
	if score < T.KickScore then
		return
	end
	local breakdown = profile:Breakdown(now)
	local decision = Scoring.decide(score, breakdown, T, Config.Definitive, function()
		return movementConfirmed(profile, now)
	end)
	if decision == "scale" then
		profile:Scale(0.5, now)
	elseif decision == "kick" then
		self:_punish(profile, breakdown, score)
	end
end

function EnforcementService:_punish(profile, breakdown, score)
	profile.kicked = true
	local player = profile.player
	local reason = reasonText(breakdown)
	local sig = signature(profile)
	self._threat:NoteKick()

	-- on the island nobody gets kicked, they just keep playing with each other
	if self._island:IsIsland() then
		return
	end

	-- grab the replay before they're gone, upload it after
	local recording = if Config.On("Replays") then self._recorder:Capture(profile, "kick", reason) else nil

	if not (Config.On("CheaterIsland") and self._island:Send(player)) then
		player:Kick(Config.KickMessage)
	end
	self.Kicked:Fire(player, reason, score)

	self._backend:Track(function()
		local replayId = self._recorder:Upload(recording)
		self._backend:QueueKick(profile, reason, score, replayId, sig)
		self._backend:Sync()
	end)
end

function EnforcementService:Start()
	self._backend = Framework.Get("ACBackendService")
	self._recorder = Framework.Get("ACRecorderService")
	self._island = Framework.Get("ACIslandService")
	self._threat = Framework.Get("ACThreatService")
end

return EnforcementService
