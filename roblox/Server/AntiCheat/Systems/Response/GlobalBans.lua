local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- bans land on every live server within about a second.
-- the dashboard publishes through roblox open cloud the moment you click ban,
-- and any server that hears about a new ban first relays it to the rest
local GlobalBans = { Name = "ACGlobalBans" }

local TOPIC = "AC_Ban"

local Bans
local lastRelay = {}

function GlobalBans.Relay(userId, active, reason)
	if not Config.On("GlobalBans") then
		return
	end
	-- every server hears about the same ban on its sync, one relay per ban per server is plenty
	local key = userId .. tostring(active)
	if lastRelay[key] and os.clock() - lastRelay[key] < 60 then
		return
	end
	lastRelay[key] = os.clock()
	task.spawn(pcall, MessagingService.PublishAsync, MessagingService, TOPIC,
		HttpService:JSONEncode({ id = tostring(userId), active = active, reason = reason }))
end

local function onMessage(message)
	if not Config.On("GlobalBans") then
		return
	end
	local data = message.Data
	if type(data) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, data)
		data = if ok then decoded else nil
	end
	if type(data) ~= "table" then
		return
	end
	local userId = tonumber(data.id)
	if userId and type(data.active) == "boolean" then
		Bans.Apply(userId, data.active, if type(data.reason) == "string" then data.reason else "")
	end
end

function GlobalBans:Start()
	Bans = Framework.Get("ACBans")
	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, onMessage)
		if not ok then
			warn("[AntiCheat] couldn't subscribe to global bans:", err)
		end
	end)
end

return GlobalBans
