local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Config)
local Backend = require(script.Parent.Parent.Net.Backend)

local Bans = {}

local cache = {}

local function message(reason)
	if type(reason) == "string" and reason ~= "" then
		return Config.BanMessage .. "\nReason: " .. reason
	end
	return Config.BanMessage
end

local function kickIfHere(userId, reason)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:Kick(message(reason))
	end
end

-- roblox's own ban api also catches alts and works even if our backend is down.
-- doesn't work in studio, the live servers pick it up since unsynced bans keep coming back
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
		ok = pcall(Players.UnbanAsync, Players, {
			UserIds = { userId },
			ApplyToUniverse = true,
		})
	end
	if ok then
		Backend.Ack(userId, active)
	end
end

local function apply(data)
	if type(data.bans) ~= "table" then
		return
	end
	for _, ban in data.bans do
		local userId = tonumber(ban.id)
		if userId then
			local reason = type(ban.reason) == "string" and ban.reason or ""
			if ban.active then
				cache[userId] = reason
				kickIfHere(userId, reason)
			else
				cache[userId] = nil
			end
			if not ban.synced then
				task.spawn(syncRoblox, userId, ban.active == true, ban.expires, reason)
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
	if res and res.banned and player.Parent then
		cache[userId] = res.reason or ""
		player:Kick(message(res.reason))
	end
end

function Bans.Init()
	Backend.Synced:Connect(apply)
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

function Bans.IsBanned(userId)
	return cache[userId] ~= nil
end

return Bans
