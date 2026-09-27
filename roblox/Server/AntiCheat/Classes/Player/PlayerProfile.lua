local RunService = game:GetService("RunService")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local RingBuffer = require(AC.Classes.Core.RingBuffer)
local Rig = require(AC.Classes.Player.Rig)
local Physics = require(AC.Util.Physics)
local Scoring = require(AC.Util.Scoring)

local T = Config.Thresholds
local HISTORY = Config.HistorySeconds * Config.HotRate

local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile

function PlayerProfile.new(player)
	local now = os.clock()
	return setmetatable({
		player = player,
		userId = player.UserId,
		admin = Config.Admins[player.UserId] == true,
		immune = Config.Admins[player.UserId] == true and not (RunService:IsStudio() and Config.CheckAdminsInStudio),
		joinedAt = now,
		kicked = false,
		shadow = nil,
		shadowCleared = false,
		reportWeight = 0,
		reportAt = now,

		score = 0,
		scoreAt = now,
		peak = 0,
		byCheck = {},
		exempt = {},
		allow = {},
		teleports = {},

		times = RingBuffer.new(HISTORY),
		xs = RingBuffer.new(HISTORY),
		ys = RingBuffer.new(HISTORY),
		zs = RingBuffer.new(HISTORY),
		yaws = RingBuffer.new(HISTORY),
		allowed = RingBuffer.new(HISTORY),
		grounds = RingBuffer.new(HISTORY),
		poses = RingBuffer.new(HISTORY, false),
		rig = nil,
		events = RingBuffer.new(64, false),
		netCalls = 0,
		moveViolations = RingBuffer.new(8),

		char = nil,
		root = nil,
		humanoid = nil,
		move = nil,

		timing = {},
		stats = {},
		statCount = 0,
		rejects = { count = 0, at = now },
		combat = { attempts = 0, hits = 0, last = {} },
		client = { lastBeat = now, seq = 0, strikes = {} },
		behavior = nil,
	}, PlayerProfile)
end

function PlayerProfile:Score(now)
	return Scoring.decay(self.score, self.scoreAt, now or os.clock(), T.HalfLife)
end

function PlayerProfile:AddScore(check, amount, now)
	self.score = self:Score(now) + amount
	self.scoreAt = now
	if self.score > self.peak then
		self.peak = self.score
	end

	local entry = self.byCheck[check]
	if entry then
		entry.value = Scoring.decay(entry.value, entry.at, now, T.HalfLife) + amount
		entry.at = now
	else
		self.byCheck[check] = { value = amount, at = now }
	end
	return self.score
end

function PlayerProfile:Carry(score)
	if score > 0 then
		self.score += score
		self.peak = math.max(self.peak, self.score)
	end
end

function PlayerProfile:Breakdown(now)
	local out = {}
	for check, entry in self.byCheck do
		local v = Scoring.decay(entry.value, entry.at, now, T.HalfLife)
		if v > 0.5 then
			table.insert(out, { check = check, value = v })
		end
	end
	table.sort(out, function(a, b)
		return a.value > b.value
	end)
	return out
end

function PlayerProfile:Scale(factor, now)
	self.score = self:Score(now) * factor
	self.scoreAt = now
	for _, entry in self.byCheck do
		entry.value = Scoring.decay(entry.value, entry.at, now, T.HalfLife) * factor
		entry.at = now
	end
end

function PlayerProfile:IsExempt(check, now)
	now = now or os.clock()
	local all, one = self.exempt.All, self.exempt[check]
	return (all ~= nil and all > now) or (one ~= nil and one > now)
end

function PlayerProfile:Exempt(check, seconds)
	local untilTime = os.clock() + seconds
	local current = self.exempt[check]
	if not current or current < untilTime then
		self.exempt[check] = untilTime
	end
end

function PlayerProfile:ReportWeight(now)
	return Scoring.decay(self.reportWeight, self.reportAt, now or os.clock(), 300)
end

function PlayerProfile:AddReport(weight, now)
	now = now or os.clock()
	self.reportWeight = self:ReportWeight(now) + weight
	self.reportAt = now
end

function PlayerProfile:Allow(kind, value, seconds)
	local list = self.allow[kind]
	if not list then
		list = {}
		self.allow[kind] = list
	end
	local entry = { value = value, untilTime = os.clock() + seconds }
	if #list >= 32 then
		table.remove(list, 1)
	end
	table.insert(list, entry)
	return function()
		local i = table.find(list, entry)
		if i then
			table.remove(list, i)
		end
	end
end

function PlayerProfile:Allowed(kind, now)
	local list = self.allow[kind]
	if not list then
		return nil
	end
	now = now or os.clock()
	local best
	for i = #list, 1, -1 do
		local entry = list[i]
		if entry.untilTime <= now then
			table.remove(list, i)
		elseif best == nil or entry.value > best then
			best = entry.value
		end
	end
	return best
end

function PlayerProfile:ExpectTeleport(pos, radius, seconds)
	local entry = { pos = pos, radius = radius, untilTime = os.clock() + seconds }
	table.insert(self.teleports, entry)
	return function()
		local i = table.find(self.teleports, entry)
		if i then
			table.remove(self.teleports, i)
		end
	end
end

function PlayerProfile:TakeTeleport(pos, now, keepMisses)
	local list = self.teleports
	local closest, miss
	for i = #list, 1, -1 do
		local entry = list[i]
		if entry.untilTime <= now then
			table.remove(list, i)
		else
			local d = (entry.pos - pos).Magnitude
			if d <= entry.radius then
				table.remove(list, i)
				return true, 0
			end
			if not miss or d < miss then
				closest, miss = i, d
			end
		end
	end
	if closest and not keepMisses then
		table.remove(list, closest)
	end
	return false, miss
end

function PlayerProfile:Record(now, pos, yaw, allowed, grounded)
	self.times:Push(now)
	self.xs:Push(pos.X)
	self.ys:Push(pos.Y)
	self.zs:Push(pos.Z)
	self.yaws:Push(yaw)
	self.allowed:Push(allowed)
	self.grounds:Push(if grounded then 1 else 0)
	self.poses:Push(if self.rig and Config.RecordPoses then self.rig:Pose() else false)
end

function PlayerProfile:Event(now, check, kind, detail)
	self.events:Push({ t = now, check = check, kind = kind or check, detail = detail })
end

function PlayerProfile:Position()
	local root = self.root
	return root and root.Parent and root.Position
end

function PlayerProfile:BindCharacter(char)
	if self.char then
		Physics.Untrack(self.char)
	end
	self.char = char
	self.humanoid, self.root = nil, nil
	local humanoid = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if self.char ~= char or not humanoid or not root then
		return
	end
	self.humanoid, self.root = humanoid, root
	Physics.Track(char)

	self.boundAt = os.clock()
	self.partCount = nil
	self.rootSize = nil
	self.move = nil
	self:Exempt("Movement", 1.5)

	self.rig = nil
	task.spawn(function()
		local player = self.player
		local deadline = os.clock() + 10
		while not player:HasAppearanceLoaded() and os.clock() < deadline and self.char == char do
			task.wait(0.25)
		end
		if self.char == char and root.Parent then
			local ok, rig = pcall(Rig.fromCharacter, char, root)
			if ok then
				self.rig = rig
			end
		end
	end)
end

function PlayerProfile:UnbindCharacter()
	if self.char then
		Physics.Untrack(self.char)
	end
	self.char, self.root, self.humanoid, self.move = nil, nil, nil, nil
	self.rig = nil
end

function PlayerProfile:Alive()
	local hum = self.humanoid
	return self.root ~= nil and self.root.Parent ~= nil and hum ~= nil and hum.Parent ~= nil and hum.Health > 0
end

return PlayerProfile
