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

local MAX_LEDGER = 2000

function SyncBatch.new(maxFlags)
	return setmetatable({
		maxFlags = maxFlags,
		flags = {},
		flagCount = 0,
		kicks = {},
		acks = {},
		departed = {},
		reports = {},
		shadow = {},
		revertAcks = {},
		ledger = {},
		ledgerCount = 0,
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

function SyncBatch:AddReport(report)
	table.insert(self.reports, report)
end

function SyncBatch:AddShadow(userId, on, why, name, by)
	table.insert(self.shadow, { id = tostring(userId), on = on, why = why, name = name, by = by })
end

function SyncBatch:AddRevertAck(id, ok, result)
	table.insert(self.revertAcks, { id = id, ok = ok, result = result })
end

-- gains merge per player + what + where from, so a coin farm is one row per sync, not thousands
function SyncBatch:AddLedger(userId, kind, key, amount, victim, source, withheld)
	local k = table.concat({ userId, kind, key, victim or "", source or "", if withheld then "w" else "" }, "|")
	local entry = self.ledger[k]
	if entry then
		entry.amount += amount
		return
	end
	if self.ledgerCount >= MAX_LEDGER then
		return
	end
	self.ledgerCount += 1
	self.ledger[k] = {
		id = tostring(userId),
		kind = kind,
		key = key,
		amount = amount,
		victim = if victim then tostring(victim) else nil,
		source = source,
		withheld = withheld or nil,
	}
end

-- hands everything over and starts empty
function SyncBatch:Drain()
	local flags = {}
	for _, entry in self.flags do
		entry.top = nil
		table.insert(flags, entry)
	end
	local ledger = {}
	for _, entry in self.ledger do
		table.insert(ledger, entry)
	end
	local out = {
		flags = flags,
		kicks = self.kicks,
		acks = self.acks,
		departed = self.departed,
		reports = self.reports,
		shadow = self.shadow,
		revertAcks = self.revertAcks,
		ledger = ledger,
	}
	self.flags, self.flagCount, self.kicks, self.acks, self.departed = {}, 0, {}, {}, {}
	self.reports, self.shadow, self.revertAcks, self.ledger, self.ledgerCount = {}, {}, {}, {}, 0
	return out
end

local function append(into, from)
	table.move(from, 1, #from, #into + 1, into)
end

-- a failed request shouldn't lose anything a human or an undo depends on. flags can go, they're capped anyway
function SyncBatch:Restore(drained)
	append(self.kicks, drained.kicks)
	append(self.acks, drained.acks)
	append(self.reports, drained.reports)
	append(self.shadow, drained.shadow)
	append(self.revertAcks, drained.revertAcks)
	for _, e in drained.ledger do
		self:AddLedger(e.id, e.kind, e.key, e.amount, e.victim, e.source, e.withheld)
	end
end

return SyncBatch
