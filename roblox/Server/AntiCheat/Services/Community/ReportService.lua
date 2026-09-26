local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

-- players reporting players. a report never kicks anyone by itself: it records the last 20s of
-- the reported player as a replay, lands in their case file on the dashboard, and a reported
-- player gets the bait npc sooner. reports count more from people who've been right before
-- (the backend tracks that) and less from brand new accounts or people who look suspicious themselves.
-- the client half is ACReportController
local ReportService = { Name = "ACReportService" }

local PER_TARGET = 300 -- one report per reporter per target every 5 minutes
local BURST = 5 -- at most this many reports per reporter...
local BURST_WINDOW = 600 -- ...every 10 minutes
local CAPTURE_EVERY = 60 -- one evidence replay per target per minute is plenty

function ReportService:Init()
	self._recent = {} -- reporter userId -> { times = {}, targets = { [targetId] = t } }
	self._captured = {} -- target userId -> os.clock()
	self.Send = Net.Event({ name = "ACReport", cooldown = 2 }):Expect("number", "string", "string")
	self.State = Net.Event("ACReportState")
end

local function allowedReason(reason)
	return table.find(Config.ReportReasons, reason) ~= nil
end

-- how much this report should count, 0..1. the backend multiplies in the reporter's track record
function ReportService:_weight(reporter, now)
	local w = 1
	if reporter:Score(now) >= Config.Thresholds.KickScore * 0.5 then
		-- cheaters love reporting whoever just beat them
		w *= 0.25
	end
	if reporter.player.AccountAge < 3 then
		w *= 0.5
	end
	if now - reporter.joinedAt < 60 then
		w *= 0.5
	end
	return w
end

function ReportService:_limited(reporterId, targetId, now)
	local r = self._recent[reporterId]
	if not r then
		r = { times = {}, targets = {} }
		self._recent[reporterId] = r
	end
	local last = r.targets[targetId]
	if last and now - last < PER_TARGET then
		return "You already reported them. We're on it."
	end
	local fresh = {}
	for _, t in r.times do
		if now - t < BURST_WINDOW then
			table.insert(fresh, t)
		end
	end
	r.times = fresh
	if #fresh >= BURST then
		return "That's a lot of reports. Try again in a few minutes."
	end
	table.insert(fresh, now)
	r.targets[targetId] = now
	return nil
end

local function filtered(text, fromUserId)
	text = string.sub(string.gsub(text, "%c", " "), 1, 100)
	if text == "" then
		return ""
	end
	-- staff read this outside the game, it still goes through roblox's filter like any player text
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, fromUserId):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else ""
end

-- returns ok, message for the reporter. also what your own report ui should call
function ReportService:Report(reporterPlayer, target, reason, note)
	if not Config.On("Reports") then
		return false, "Reports are switched off right now."
	end
	local reporter = self._players:Get(reporterPlayer)
	local targetPlayer = if typeof(target) == "Instance" then target else Players:GetPlayerByUserId(tonumber(target) or 0)
	local victim = targetPlayer and self._players:Get(targetPlayer)
	if not reporter or not victim then
		return false, "That player isn't in this server anymore."
	end
	if victim == reporter then
		return false, "You can't report yourself."
	end
	if type(reason) ~= "string" or not allowedReason(reason) then
		return false, "Pick a reason."
	end
	local now = os.clock()
	local limited = self:_limited(reporter.userId, victim.userId, now)
	if limited then
		return false, limited
	end

	local w = self:_weight(reporter, now)
	-- a reported player gets watched harder: the bait npc shows up for them sooner
	victim.reportWeight += w

	local report = {
		target = tostring(victim.userId),
		reporter = tostring(reporter.userId),
		reason = reason,
		w = math.floor(w * 100) / 100,
		score = math.floor(victim:Score(now) * 10) / 10,
		name = victim.player.Name,
		by = reporter.player.Name,
	}
	local recording
	local last = self._captured[victim.userId]
	if Config.On("Replays") and (not last or now - last > CAPTURE_EVERY) then
		self._captured[victim.userId] = now
		recording = self._recorder:Capture(victim, "capture", string.format("reported for %s by %s", reason, reporter.player.Name))
	end

	self._backend:Track(function()
		report.note = if type(note) == "string" then filtered(note, reporter.userId) else ""
		report.replay = self._recorder:Upload(recording)
		self._backend:QueueReport(report)
	end)
	return true, "Thanks! Staff will look at what they were doing."
end

function ReportService:_config(player)
	self.State:Fire(player, {
		enabled = Config.On("Reports") and Config.ReportButton,
		reasons = Config.ReportReasons,
	})
end

function ReportService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._backend = Framework.Get("ACBackendService")
	self._recorder = Framework.Get("ACRecorderService")

	self.Send:Listen(function(player, targetId, reason, note)
		local ok, message = self:Report(player, targetId, reason, note)
		self.State:Fire(player, { result = { ok = ok, message = message } })
	end)

	-- "a player you reported got banned", shown when they next join
	Framework.Get("ACBanService").JoinChecked:Connect(function(player, res)
		local thanks = tonumber(res.thanks) or 0
		if thanks > 0 then
			self.State:Fire(player, {
				thanks = thanks,
				message = if thanks == 1
					then "A player you reported was banned. Thanks for helping keep the game fair!"
					else string.format("%d players you reported were banned. Thanks for helping keep the game fair!", thanks),
			})
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_config(player)
	end)
	for _, player in Players:GetPlayers() do
		self:_config(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self._recent[player.UserId] = nil
	end)
	-- the button appears and disappears with the dashboard toggle
	Config.Changed:Connect(function()
		for _, player in Players:GetPlayers() do
			self:_config(player)
		end
	end)
end

return ReportService
