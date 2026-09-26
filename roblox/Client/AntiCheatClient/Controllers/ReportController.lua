local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local ReportPanel = require(script.Parent.Parent.Classes.ReportPanel)

-- client half of ACReportService: the report button, /report in chat, and the little
-- "thanks" messages. the server decides everything, this only shows it
local ReportController = { Name = "ACReportController" }

local player = Players.LocalPlayer

function ReportController:Init()
	self._send = Net.Event("ACReport")
	self._state = Net.Event("ACReportState")
	self._panel = nil
end

function ReportController:_ensurePanel()
	if self._panel then
		return self._panel
	end
	self._panel = ReportPanel.new(player:WaitForChild("PlayerGui"), function(targetId, reason, note)
		self._send:FireServer(targetId, reason, note or "")
	end)

	local commands = TextChatService:FindFirstChild("TextChatCommands")
	if commands and not commands:FindFirstChild("ACReport") then
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "ACReport"
		cmd.PrimaryAlias = "/report"
		cmd.Triggered:Connect(function()
			if self._panel.button.Visible then
				self._panel:SetOpen(true)
			end
		end)
		cmd.Parent = commands
	end
	return self._panel
end

function ReportController:Start()
	self._state:Listen(function(info)
		if type(info) ~= "table" then
			return
		end
		if info.enabled ~= nil then
			if info.enabled or self._panel then
				local panel = self:_ensurePanel()
				panel:SetEnabled(info.enabled == true)
				panel:SetReasons(info.reasons)
			end
		end
		if type(info.result) == "table" and self._panel then
			self._panel:Result(info.result.ok == true, tostring(info.result.message or ""))
		end
		if type(info.message) == "string" and info.message ~= "" then
			self:_ensurePanel():Toast(info.message, true)
		end
	end)
end

return ReportController
