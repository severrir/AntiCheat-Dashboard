local Config = require(script.Parent.Parent.Config)
local RingBuffer = require(script.Parent.RingBuffer)
local Physics = require(script.Parent.Physics)
local Scoring = require(script.Parent.Scoring)

local T = Config.Thresholds
local HISTORY = Config.HistorySeconds * Config.HotRate

local Profile = {}
Profile.__index = Profile

function Profile.new(player)
	local now = os.clock()
	return setmetatable({
		player = player,
		userId = player.UserId,
		admin = Config.Admins[player.UserId] == true,
		joinedAt = now,
		kicked = false,

		score = 0,
		scoreAt = now,
		peak = 0,
		byCheck = {},
		exempt = {},

		-- movement history, feeds forensic replay, 3D replays and behaviour fingerprints
		times = RingBuffer.new(HISTORY),
		xs = RingBuffer.new(HISTORY),
		ys = RingBuffer.new(HISTORY),
		zs = RingBuffer.new(HISTORY),
		yaws = RingBuffer.new(HISTORY),
		allowed = RingBuffer.new(HISTORY),
		grounds = RingBuffer.new(HISTORY),
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
	}, Profile)
end

function Profile:Score(now)
	return Scoring.decay(self.score, self.scoreAt, now or os.clock(), T.HalfLife)
end

function Profile:AddScore(check, amount, now)
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

-- trust carried over from earlier sessions. not tied to any check, so it can't
-- satisfy the "two checks must agree" rule on its own, it just gets them there sooner
function Profile:Carry(score)
	if score > 0 then
		self.score += score
		self.peak = math.max(self.peak, self.score)
	end
end

-- what each check is contributing right now, biggest first
function Profile:Breakdown(now)
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

function Profile:Scale(factor, now)
	self.score = self:Score(now) * factor
	self.scoreAt = now
	for _, entry in self.byCheck do
		entry.value = Scoring.decay(entry.value, entry.at, now, T.HalfLife) * factor
		entry.at = now
	end
end

function Profile:IsExempt(check, now)
	now = now or os.clock()
	local all, one = self.exempt.All, self.exempt[check]
	return (all ~= nil and all > now) or (one ~= nil and one > now)
end

function Profile:Exempt(check, seconds)
	local untilTime = os.clock() + seconds
	local current = self.exempt[check]
	if not current or current < untilTime then
		self.exempt[check] = untilTime
	end
end

function Profile:Record(now, pos, yaw, allowed, grounded)
	self.times:Push(now)
	self.xs:Push(pos.X)
	self.ys:Push(pos.Y)
	self.zs:Push(pos.Z)
	self.yaws:Push(yaw)
	self.allowed:Push(allowed)
	self.grounds:Push(if grounded then 1 else 0)
end

-- detail feeds the cheat tool fingerprint, e.g. "Speed x2.5"
function Profile:Event(now, check, kind, detail)
	self.events:Push({ t = now, check = check, kind = kind or check, detail = detail })
end

function Profile:Position()
	local root = self.root
	return root and root.Parent and root.Position
end

function Profile:BindCharacter(char)
	if self.char then
		Physics.Untrack(self.char)
	end
	self.char = char
	self.humanoid, self.root = nil, nil
	local humanoid = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	-- respawned while we were waiting, the newer call handles it
	if self.char ~= char or not humanoid or not root then
		return
	end
	self.humanoid, self.root = humanoid, root
	Physics.Track(char)

	-- the character check takes its baseline later, once the avatar has finished loading
	self.boundAt = os.clock()
	self.partCount = nil
	self.rootSize = nil
	self.move = nil
	-- spawning can teleport you
	self:Exempt("Movement", 1.5)
end

function Profile:UnbindCharacter()
	if self.char then
		Physics.Untrack(self.char)
	end
	self.char, self.root, self.humanoid, self.move = nil, nil, nil, nil
end

function Profile:Alive()
	local hum = self.humanoid
	return self.root ~= nil and self.root.Parent ~= nil and hum ~= nil and hum.Parent ~= nil and hum.Health > 0
end

return Profile
