local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- bans come from the dashboard / discord bot. this keeps them enforced in game:
-- join check, kicking people already inside, and roblox's own ban api so alts get caught too
local Bans = { Name = "ACBans" }

local Backend, PlayerService, GlobalBans
local cache = {}

local function message(reason)
	local text = Config.BanMessage
	if type(reason) == "string" and reason ~= "" then
		text ..= "\nReason: " .. reason
	end
	return text .. "\nAppeal: " .. Config.AppealUrl
end

function Bans.Apply(userId, active, reason)
	if active then
		local isNew = cache[userId] == nil
		cache[userId] = reason or ""
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:Kick(message(reason))
		end
		return isNew
	end
	cache[userId] = nil
	return false
end

function Bans.IsBanned(userId)
	return cache[userId] ~= nil
end

-- doesn't work in studio. live servers pick it up since unsynced bans keep coming back
local function syncRoblox(userId, active, expires, reason)
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
		Backend.Ack(userId, active)
	end
end

local function onSynced(data)
	if type(data.bans) ~= "table" then
		return
	end
	for _, ban in data.bans do
		local userId = tonumber(ban.id)
		if userId then
			local reason = if type(ban.reason) == "string" then ban.reason else ""
			local active = ban.active == true
			local isNew = Bans.Apply(userId, active, reason)
			-- tell every other server right away instead of waiting for their next sync
			if isNew then
				GlobalBans.Relay(userId, true, reason)
			end
			if not ban.synced then
				task.spawn(syncRoblox, userId, active, ban.expires, reason)
			end
		end
	end
end

local function onJoin(player)
	local userId = player.UserId
	if Config.Admins[userId] then
		return
	end
	if cache[userId] then
		player:Kick(message(cache[userId]))
		return
	end

	local res = Backend.CheckJoin(userId)
	if not res or not player.Parent then
		return
	end
	if res.banned then
		cache[userId] = res.reason or ""
		player:Kick(message(res.reason))
		return
	end

	-- suspicion follows you between servers, fading with time away
	if Config.On("CrossServerTrust") and type(res.carry) == "table" and type(res.carry.score) == "number" then
		local hours = (tonumber(res.carry.away) or 0) / 3600
		local carried = res.carry.score * 0.5 ^ (hours / Config.CarryHalfLifeHours)
		local profile = PlayerService.Await(player)
		if profile and carried >= 1 then
			profile:Carry(carried)
		end
	end
end

function Bans:Start()
	Backend = Framework.Get("ACBackend")
	PlayerService = Framework.Get("ACPlayers")
	GlobalBans = Framework.Get("ACGlobalBans")

	Backend.Synced:Connect(onSynced)
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

return Bans
