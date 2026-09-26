local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- bans come from the dashboard / discord bot. this keeps them enforced in game:
-- join check, kicking people already inside, and roblox's own ban api so alts get caught too
local BanService = { Name = "ACBanService" }

local function message(reason)
	local text = Config.BanMessage
	if type(reason) == "string" and reason ~= "" then
		text ..= "\nReason: " .. reason
	end
	return text .. "\nAppeal: " .. Config.AppealUrl
end

function BanService:Init()
	self._cache = {} -- userId -> reason
end

-- returns true when this server hadn't heard about the ban yet
function BanService:Apply(userId, active, reason)
	if not active then
		self._cache[userId] = nil
		return false
	end
	local isNew = self._cache[userId] == nil
	self._cache[userId] = reason or ""
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:Kick(message(reason))
	end
	return isNew
end

function BanService:IsBanned(userId)
	return self._cache[userId] ~= nil
end

-- doesn't work in studio. live servers pick it up since unsynced bans keep coming back
function BanService:_syncRoblox(userId, active, expires, reason)
	if RunService:IsStudio() then
		return
	end
	local ok
	if active then
		local duration = -1
		if type(expires) == "number" then
			duration = math.max(60, math.floor(expires - os.time()))
		end
		ok = pcall(Players.BanAsync, Players, {
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = duration,
			DisplayReason = if reason ~= "" then string.sub(reason, 1, 400) else "Banned",
			PrivateReason = "anticheat dashboard",
			ExcludeAltAccounts = false,
		})
	else
		ok = pcall(Players.UnbanAsync, Players, { UserIds = { userId }, ApplyToUniverse = true })
	end
	if ok then
		self._backend:Ack(userId, active)
	end
end

function BanService:_onSynced(data)
	if type(data.bans) ~= "table" then
		return
	end
	for _, ban in data.bans do
		local userId = tonumber(ban.id)
		if userId then
			local reason = if type(ban.reason) == "string" then ban.reason else ""
			local active = ban.active == true
			-- tell every other server right away instead of waiting for their next sync
			if self:Apply(userId, active, reason) then
				self._global:Relay(userId, true, reason)
			end
			if not ban.synced then
				task.spawn(self._syncRoblox, self, userId, active, ban.expires, reason)
			end
		end
	end
end

function BanService:_onJoin(player)
	local userId = player.UserId
	if Config.Admins[userId] then
		return
	end
	if self._cache[userId] then
		player:Kick(message(self._cache[userId]))
		return
	end

	local res = self._backend:CheckJoin(userId)
	if not res or not player.Parent then
		return
	end
	if res.banned then
		self._cache[userId] = res.reason or ""
		player:Kick(message(res.reason))
		return
	end

	-- suspicion follows you between servers, fading with time away
	if Config.On("CrossServerTrust") and type(res.carry) == "table" and type(res.carry.score) == "number" then
		local hours = (tonumber(res.carry.away) or 0) / 3600
		local carried = res.carry.score * 0.5 ^ (hours / Config.CarryHalfLifeHours)
		local profile = self._players:Await(player)
		if profile and carried >= 1 then
			profile:Carry(carried)
		end
	end
end

function BanService:Start()
	self._backend = Framework.Get("ACBackendService")
	self._players = Framework.Get("ACPlayerService")
	self._global = Framework.Get("ACGlobalBanService")

	self._backend.Synced:Connect(function(data)
		self:_onSynced(data)
	end)
	Players.PlayerAdded:Connect(function(player)
		self:_onJoin(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._onJoin, self, player)
	end
end

return BanService
