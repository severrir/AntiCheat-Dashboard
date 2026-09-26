local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- runs what the dashboard asks for: capture a replay, kick, or pull an admin in to spectate
local CommandService = { Name = "ACCommandService" }

function CommandService:Init()
	self._acks = {}
	self._handled = {}
	self._handlers = {
		replay = self._replay,
		kick = self._kick,
		spectate = self._spectate,
	}
end

function CommandService:TakeAcks()
	local out = self._acks
	self._acks = {}
	return out
end

function CommandService:_replay(cmd, target)
	local profile = target and self._players:GetById(target)
	if not profile then
		return false, "player left"
	end
	local id = self._recorder:Upload(self._recorder:Capture(profile, "capture", "captured from dashboard"))
	return id ~= nil, if id then "replay " .. id else "upload failed"
end

function CommandService:_kick(_cmd, target)
	local player = target and Players:GetPlayerByUserId(target)
	if not player then
		return false, "player left"
	end
	player:Kick(Config.KickMessage)
	return true, "kicked"
end

function CommandService:_spectate(cmd, target)
	local admin = Players:GetPlayerByUserId(tonumber(cmd.admin) or 0)
	if not admin or not Config.Admins[admin.UserId] then
		return false, "admin not here"
	end
	if Players:GetPlayerByUserId(target or 0) then
		self._spectator:Begin(admin, target)
		return true, "spectating here"
	end
	-- target is in another server, take the admin there
	if type(cmd.server) ~= "string" or cmd.server == "" or string.sub(cmd.server, 1, 7) == "studio-" then
		return false, "target server unknown"
	end
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = cmd.server
	options:SetTeleportData({ acSpectate = target })
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { admin }, options)
	return ok, if ok then "teleporting" else tostring(err)
end

function CommandService:Dispatch(list)
	if type(list) ~= "table" then
		return
	end
	for _, cmd in list do
		-- the same command can arrive through both sync and pulse
		if type(cmd) == "table" and type(cmd.id) == "number" and not self._handled[cmd.id] then
			self._handled[cmd.id] = true
			task.spawn(function()
				local handler = self._handlers[cmd.kind]
				local ok, ranOk, result = false, false, "unknown command"
				if handler then
					ok, ranOk, result = pcall(handler, self, cmd, tonumber(cmd.target))
				end
				table.insert(self._acks, {
					id = cmd.id,
					ok = ok and ranOk == true,
					result = if handler and not ok then "error" else result,
				})
			end)
		end
	end
end

function CommandService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._recorder = Framework.Get("ACRecorderService")
	self._spectator = Framework.Get("ACSpectatorService")
end

return CommandService
