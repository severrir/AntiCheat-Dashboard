local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- runs what the dashboard asks for: capture a replay, kick, or pull an admin in to spectate
local Commands = { Name = "ACCommands" }

local PlayerService, Recorder, Spectator
local acks = {}
local handled = {}

local function ack(id, ok, result)
	table.insert(acks, { id = id, ok = ok, result = result })
end

function Commands.TakeAcks()
	local out = acks
	acks = {}
	return out
end

local function run(cmd)
	local target = tonumber(cmd.target)
	if cmd.kind == "replay" then
		local profile = target and PlayerService.GetById(target)
		if not profile then
			return false, "player left"
		end
		local snap = Recorder.Snapshot(profile, "capture", "captured from dashboard")
		local id = Recorder.Upload(snap)
		return id ~= nil, if id then "replay " .. id else "upload failed"
	elseif cmd.kind == "kick" then
		local player = target and Players:GetPlayerByUserId(target)
		if not player then
			return false, "player left"
		end
		player:Kick(Config.KickMessage)
		return true, "kicked"
	elseif cmd.kind == "spectate" then
		local admin = Players:GetPlayerByUserId(tonumber(cmd.admin) or 0)
		if not admin or not Config.Admins[admin.UserId] then
			return false, "admin not here"
		end
		if Players:GetPlayerByUserId(target or 0) then
			Spectator.Begin(admin, target)
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
	return false, "unknown command"
end

function Commands.Dispatch(list)
	if type(list) ~= "table" then
		return
	end
	for _, cmd in list do
		-- the same command can arrive through both sync and pulse
		if type(cmd) == "table" and type(cmd.id) == "number" and not handled[cmd.id] then
			handled[cmd.id] = true
			task.spawn(function()
				local ok, ranOk, result = pcall(run, cmd)
				if not ok then
					ack(cmd.id, false, "error")
				else
					ack(cmd.id, ranOk == true, result)
				end
			end)
		end
	end
end

function Commands:Start()
	PlayerService = Framework.Get("ACPlayers")
	Recorder = Framework.Get("ACRecorder")
	Spectator = Framework.Get("ACSpectator")
end

return Commands
