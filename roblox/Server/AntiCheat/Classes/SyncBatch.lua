-- everything waiting to go to the backend on the next sync. flags merge per player+check
-- so a speed hacker spamming 100 flags a second is still one row
local SyncBatch = {}
SyncBatch.__index = SyncBatch

local function round(n)
	return math.floor(n * 10 + 0.5) / 10
end

local function vec(pos)
	return pos and { round(pos.X), round(pos.Y), round(pos.Z) }
end

function SyncBatch.new(maxFlags)
	return setmetatable({
		maxFlags = maxFlags,
		flags = {},
		flagCount = 0,
		kicks = {},
		acks = {},
		departed = {},
	}, SyncBatch)
end

function SyncBatch:AddFlag(profile, check, raw, amount, score, ctx, pos)
	local key = profile.userId .. check
	local entry = self.flags[key]
	if entry then
		entry.sev += amount
		entry.raw += raw
		entry.hits += 1
		entry.score = score
		-- keep the context of the worst hit, that's the one worth reading
		if amount >= entry.top then
			entry.top = amount
			entry.ctx = ctx
			entry.pos = entry.pos or vec(pos)
		end
		return
	end
	if self.flagCount >= self.maxFlags then
		return
	end
	self.flagCount += 1
	self.flags[key] = {
		id = tostring(profile.userId),
		check = check,
		sev = amount,
		raw = raw,
		top = amount,
		score = score,
		hits = 1,
		ctx = ctx,
		pos = vec(pos),
	}
end

function SyncBatch:AddKick(kick)
	table.insert(self.kicks, kick)
end

function SyncBatch:AddAck(userId, active)
	table.insert(self.acks, { id = tostring(userId), active = active })
end

function SyncBatch:AddDeparted(snapshot)
	table.insert(self.departed, snapshot)
end

-- hands everything over and starts empty
function SyncBatch:Drain()
	local flags = {}
	for _, entry in self.flags do
		entry.top = nil
		table.insert(flags, entry)
	end
	local out = { flags = flags, kicks = self.kicks, acks = self.acks, departed = self.departed }
	self.flags, self.flagCount, self.kicks, self.acks, self.departed = {}, 0, {}, {}, {}
	return out
end

-- a failed request shouldn't lose kicks or ban acks. flags can go, they're capped anyway
function SyncBatch:Restore(drained)
	table.move(drained.kicks, 1, #drained.kicks, #self.kicks + 1, self.kicks)
	table.move(drained.acks, 1, #drained.acks, #self.acks + 1, self.acks)
end

return SyncBatch
