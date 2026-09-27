local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

local GlobalBanService = { Name = "ACGlobalBanService" }

local TOPIC = "AC_Ban"
local RELAY_COOLDOWN = 60

function GlobalBanService:Init()
	self._lastRelay = {}
end

function GlobalBanService:Relay(userId, active, reason)
	if not Config.On("GlobalBans") then
		return
	end
	local key = userId .. tostring(active)
	local last = self._lastRelay[key]
	if last and os.clock() - last < RELAY_COOLDOWN then
		return
	end
	self._lastRelay[key] = os.clock()
	for k, t in self._lastRelay do
		if os.clock() - t > RELAY_COOLDOWN then
			self._lastRelay[k] = nil
		end
	end
	local payload = HttpService:JSONEncode({ id = tostring(userId), active = active, reason = reason })
	task.spawn(pcall, MessagingService.PublishAsync, MessagingService, TOPIC, payload)
end

function GlobalBanService:_onMessage(message)
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
		self._bans:Apply(userId, data.active, if type(data.reason) == "string" then data.reason else "")
	end
end

function GlobalBanService:Start()
	self._bans = Framework.Get("ACBanService")
	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
			self:_onMessage(message)
		end)
		if not ok then
			warn(`[AntiCheat] couldn't subscribe to global bans: {err}`)
		end
	end)
end

return GlobalBanService
