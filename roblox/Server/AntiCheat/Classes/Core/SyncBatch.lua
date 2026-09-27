local SyncBatch = {}
SyncBatch.__index = SyncBatch

local function round(n)
	return math.floor(n * 10 + 0.5) / 10
end

local function vec(pos)
	return pos and { round(pos.X), round(pos.Y), round(pos.Z) }
end

local MAX_LEDGER = 2000

local function clean(ctx)
	if type(ctx) ~= "table" then
		return nil
	end
	local out = {}
	for k, v in ctx do
		if type(v) == "number" then
			if v == v and math.abs(v) ~= math.huge then
				out[k] = v
			end
		elseif type(v) == "string" or type(v) == "boolean" then
			out[k] = v
		end
	end
	return out
end

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
	ctx = clean(ctx)
	local key = profile.userId .. check
	local entry = self.flags[key]
	if entry then
		entry.sev += amount
		entry.raw += raw
		entry.hits += 1
		entry.score = score
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

local LIMITS = {
	kicks = 100,
	acks = 500,
	departed = 150,
	reports = 50,
	shadow = 100,
	revertAcks = 50,
	ledger = 500,
}

local function take(list, limit)
	if #list <= limit then
		return list, {}
	end
	return table.move(list, 1, limit, 1, {}), table.move(list, limit + 1, #list, 1, {})
end

function SyncBatch:Drain()
	local flags = {}
	for _, entry in self.flags do
		entry.top = nil
		table.insert(flags, entry)
	end

	local ledger, count = {}, 0
	for k, entry in self.ledger do
		if count >= LIMITS.ledger then
			break
		end
		table.insert(ledger, entry)
		self.ledger[k] = nil
		count += 1
	end
	self.ledgerCount -= count

	local out = { flags = flags, ledger = ledger }
	for _, name in { "kicks", "acks", "departed", "reports", "shadow", "revertAcks" } do
		out[name], self[name] = take(self[name], LIMITS[name])
	end
	self.flags, self.flagCount = {}, 0
	return out
end

local function prepend(into, from)
	if #from > 0 then
		table.move(into, 1, #into, #from + 1)
		table.move(from, 1, #from, 1, into)
	end
end

function SyncBatch:Restore(drained)
	for _, name in { "kicks", "acks", "departed", "reports", "shadow", "revertAcks" } do
		prepend(self[name], drained[name])
	end
	for _, e in drained.ledger do
		self:AddLedger(e.id, e.kind, e.key, e.amount, e.victim, e.source, e.withheld)
	end
	for _, e in drained.flags do
		local key = e.id .. e.check
		local entry = self.flags[key]
		if entry then
			entry.sev += e.sev
			entry.raw += e.raw
			entry.hits += e.hits
		elseif self.flagCount < self.maxFlags then
			self.flagCount += 1
			e.top = e.sev
			self.flags[key] = e
		end
	end
end

return SyncBatch
