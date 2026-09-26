local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local SpectatorPanel = require(script.Parent.Parent.Classes.SpectatorPanel)

-- client half of ACSpectatorService. the panel only ever gets built for accounts the server
-- says are admins, and the server re-checks everything it receives anyway. /spectate or F8
local SpectatorController = { Name = "ACSpectatorController" }

local player = Players.LocalPlayer

function SpectatorController:Init()
	self._admin = Net.Event("ACAdmin")
	self._state = Net.Event("ACSpectateState")
	self._action = Net.Event("ACAdminAction")
	self._panel = nil
end

function SpectatorController:_send(action, targetId)
	self._action:FireServer(action, targetId or 0)
end

function SpectatorController:_toggle()
	local open = not self._panel:IsOpen()
	self._panel:SetOpen(open)
	if open then
		self:_send("list")
	end
end

function SpectatorController:_setup()
	if self._panel then
		return
	end
	self._panel = SpectatorPanel.new(player:WaitForChild("PlayerGui"), function(action, targetId)
		self:_send(action, targetId)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			self:_toggle()
		end
	end)

	-- /spectate in chat, only created for admins
	local commands = TextChatService:FindFirstChild("TextChatCommands")
	if commands then
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "ACSpectate"
		cmd.PrimaryAlias = "/spectate"
		cmd.Triggered:Connect(function()
			self._panel:SetOpen(true)
			self:_send("spectate")
		end)
		cmd.Parent = commands
	end
end

-- point the camera at whoever we're watching, or back at ourselves
function SpectatorController:_follow(state)
	local camera = workspace.CurrentCamera
	local target = state.active and Players:GetPlayerByUserId(state.target)
	local hum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = hum
	elseif not state.active then
		local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if own and camera.CameraSubject ~= own then
			camera.CameraSubject = own
		end
	end
end

function SpectatorController:Start()
	self._admin:Listen(function(info)
		if type(info) == "table" and info.spectator then
			self:_setup()
		end
	end)

	self._state:Listen(function(state)
		if type(state) ~= "table" or type(state.list) ~= "table" or not self._panel then
			return
		end
		if state.active then
			self._panel:SetOpen(true)
		end
		self._panel:Render(state)
		self:_follow(state)
	end)
end

return SpectatorController
