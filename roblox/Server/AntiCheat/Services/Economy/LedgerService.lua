local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

local LedgerService = { Name = "ACLedgerService" }

local function userIdOf(who)
	if typeof(who) == "Instance" and who:IsA("Player") then
		return who.UserId
	end
	return if type(who) == "number" and who > 0 then math.floor(who) else nil
end

local function cleanKey(key)
	return if type(key) == "string" and key ~= "" then string.sub(key, 1, 40) else nil
end

local function cleanSource(source)
	return if type(source) == "string" then string.sub(source, 1, 40) else ""
end

function LedgerService:_held(player)
	return typeof(player) == "Instance" and self._shadow:IsShadowed(player)
end

function LedgerService:Grant(player, key, amount, source)
	local userId = userIdOf(player)
	key = cleanKey(key)
	if not userId or not key or type(amount) ~= "number" or amount ~= amount or math.abs(amount) == math.huge then
		return amount
	end
	if amount <= 0 then
		return amount
	end
	local held = self:_held(player)
	self._backend:QueueLedger(userId, "currency", key, amount, nil, cleanSource(source), held)
	return if held then 0 else amount
end

function LedgerService:GrantItem(player, item, source)
	local userId = userIdOf(player)
	item = cleanKey(item)
	if not userId or not item then
		return true
	end
	local held = self:_held(player)
	self._backend:QueueLedger(userId, "item", item, 1, nil, cleanSource(source), held)
	return not held
end

function LedgerService:RecordKill(killer, victim)
	local killerId, victimId = userIdOf(killer), userIdOf(victim)
	if killerId and killerId ~= victimId then
		self._backend:QueueLedger(killerId, "kill", "kill", 1, victimId, "", self:_held(killer))
	end
end

function LedgerService:Transfer(from, to, what, amount)
	local fromId, toId = userIdOf(from), userIdOf(to)
	local key = cleanKey(what)
	if not fromId or not toId or fromId == toId or not key then
		return
	end
	local held = self:_held(to)
	if type(amount) == "number" and amount > 0 and amount == amount then
		self._backend:QueueLedger(toId, "currency", key, amount, fromId, "transfer", held)
	elseif amount == nil then
		self._backend:QueueLedger(toId, "item", key, 1, fromId, "transfer", held)
	end
end

function LedgerService:Start()
	self._backend = Framework.Get("ACBackendService")
	self._shadow = Framework.Get("ACShadowService")

	if not Config.AutoLeaderstats then
		return
	end
	local watched = {}
	local function watch(player)
		local stats = player:WaitForChild("leaderstats", 30)
		if not stats or not player.Parent then
			return
		end
		local conns = {}
		watched[player] = conns
		local function track(value)
			if not (value:IsA("IntValue") or value:IsA("NumberValue")) then
				return
			end
			local last = value.Value
			conns[#conns + 1] = value.Changed:Connect(function(now)
				local gained = now - last
				last = now
				if gained > 0 then
					self._backend:QueueLedger(player.UserId, "currency", cleanKey(value.Name), gained, nil, "leaderstats", false)
				end
			end)
		end
		for _, v in stats:GetChildren() do
			track(v)
		end
		conns[#conns + 1] = stats.ChildAdded:Connect(track)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		for _, c in watched[player] or {} do
			c:Disconnect()
		end
		watched[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end
end

return LedgerService
