local Config = require(script.Parent.Parent.Config)
local RingBuffer = require(script.Parent.RingBuffer)
local Physics = require(script.Parent.Physics)

local T = Config.Thresholds
local HISTORY = 64

local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile

function PlayerProfile.new(player)
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

		-- movement replay history, used by the movement check and forensic replay
		times = RingBuffer.new(HISTORY),
		positions = RingBuffer.new(HISTORY, Vector3.zero),
		allowed = RingBuffer.new(HISTORY),
		moveViolations = RingBuffer.new(8),

		char = nil,
		root = nil,
		humanoid = nil,
		move = nil,

		buckets = {},
		timing = {},
		stats = {},
		combat = { attempts = 0, hits = 0, windowAt = now, last = {} },
		client = { lastBeat = now, seq = 0 },
	}, PlayerProfile)
end

local function decay(value, since, now)
	if value <= 0 then
		return 0
	end
	return value * 0.5 ^ ((now - since) / math.max(T.HalfLife, 1))
end

function PlayerProfile:Score(now)
	return decay(self.score, self.scoreAt, now or os.clock())
end

function PlayerProfile:AddScore(check, amount, now)
	self.score = self:Score(now) + amount
	self.scoreAt = now
	if self.score > self.peak then
		self.peak = self.score
	end

	local entry = self.byCheck[check]
	if entry then
		entry.value = decay(entry.value, entry.at, now) + amount
		entry.at = now
	else
		self.byCheck[check] = { value = amount, at = now }
	end
	return self.score
end

-- how much each check is currently contributing, after decay
function PlayerProfile:Breakdown(now)
	local out = {}
	for check, entry in self.byCheck do
		local v = decay(entry.value, entry.at, now)
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
		entry.value = decay(entry.value, entry.at, now) * factor
		entry.at = now
	end
end

function PlayerProfile:IsExempt(check, now)
	local all = self.exempt.All
	local one = self.exempt[check]
	now = now or os.clock()
	return (all ~= nil and all > now) or (one ~= nil and one > now)
end

function PlayerProfile:Exempt(check, seconds)
	local untilTime = os.clock() + seconds
	local current = self.exempt[check]
	if not current or current < untilTime then
		self.exempt[check] = untilTime
	end
end

function PlayerProfile:BindCharacter(char)
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

	local parts = 0
	for _, d in char:GetChildren() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	self.partCount = parts
	self.rootSize = self.root and self.root.Size

	self.move = nil
	self.times:Clear()
	self.positions:Clear()
	self.allowed:Clear()
	-- spawning can teleport you, give it a second
	self:Exempt("Movement", 1.5)
end

function PlayerProfile:UnbindCharacter()
	if self.char then
		Physics.Untrack(self.char)
	end
	self.char, self.root, self.humanoid, self.move = nil, nil, nil, nil
end

function PlayerProfile:Alive()
	local hum = self.humanoid
	return self.root ~= nil and self.root.Parent ~= nil and hum ~= nil and hum.Parent ~= nil and hum.Health > 0
end

return PlayerProfile
