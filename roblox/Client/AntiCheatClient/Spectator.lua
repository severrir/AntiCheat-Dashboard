local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

-- admin-only panel. /spectate or F8 to open. only ever built for accounts the server
-- says are admins, and the server re-checks everything it receives anyway
local Spectator = { Name = "ACClientSpectator" }

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ACCENT = Color3.fromRGB(34, 211, 238)
local BAD = Color3.fromRGB(244, 63, 94)
local WARN = Color3.fromRGB(251, 191, 36)
local BG = Color3.fromRGB(13, 17, 23)
local LINE = Color3.fromRGB(29, 37, 49)
local MUTED = Color3.fromRGB(125, 136, 152)

local Action
local gui, panel, title, targetLabel, scoreBar, scoreFill, noteLabel, listFrame
local state = { active = false, target = 0, list = {}, kick = 100 }

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent, text, size, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.Parent = parent
	return l
end

local function button(parent, text, color, onClick)
	local b = Instance.new("TextButton")
	b.Text = text
	b.TextSize = 13
	b.Font = Enum.Font.GothamMedium
	b.TextColor3 = color
	b.BackgroundColor3 = Color3.fromRGB(18, 24, 33)
	b.AutoButtonColor = true
	b.Size = UDim2.new(0.25, -6, 0, 30)
	corner(b, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Color = LINE
	stroke.Parent = b
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ACAdmin"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -16)
	panel.Size = UDim2.fromOffset(300, 360)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	corner(panel, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = LINE
	stroke.Parent = panel
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		pad[side] = UDim.new(0, 12)
	end
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	panel.Parent = gui

	title = label(panel, "ANTICHEAT · SPECTATOR", 11, MUTED, true)
	title.LayoutOrder = 1
	targetLabel = label(panel, "Not spectating", 18, Color3.new(1, 1, 1), true)
	targetLabel.LayoutOrder = 2

	scoreBar = Instance.new("Frame")
	scoreBar.Size = UDim2.new(1, 0, 0, 6)
	scoreBar.BackgroundColor3 = LINE
	scoreBar.LayoutOrder = 3
	corner(scoreBar, 3)
	scoreFill = Instance.new("Frame")
	scoreFill.Size = UDim2.new(0, 0, 1, 0)
	scoreFill.BackgroundColor3 = ACCENT
	corner(scoreFill, 3)
	scoreFill.Parent = scoreBar
	scoreBar.Parent = panel

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 30)
	row.LayoutOrder = 4
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row
	row.Parent = panel
	button(row, "◀", Color3.new(1, 1, 1), function()
		Action:FireServer("prev", 0)
	end)
	button(row, "▶", Color3.new(1, 1, 1), function()
		Action:FireServer("next", 0)
	end)
	button(row, "Watch", ACCENT, function()
		Action:FireServer("spectate", 0)
	end)
	button(row, "Stop", BAD, function()
		Action:FireServer("stop", 0)
	end)

	local sub = label(panel, "SUSPECTS", 11, MUTED, true)
	sub.LayoutOrder = 5

	listFrame = Instance.new("ScrollingFrame")
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.Size = UDim2.new(1, 0, 0, 170)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.ScrollBarThickness = 3
	listFrame.LayoutOrder = 6
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = listFrame
	listFrame.Parent = panel

	local foot = Instance.new("Frame")
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, 30)
	foot.LayoutOrder = 7
	foot.Parent = panel
	local rec = button(foot, "● Record my session", WARN, function()
		Action:FireServer("record", 0)
	end)
	rec.Size = UDim2.new(1, 0, 0, 30)

	noteLabel = label(panel, "", 12, MUTED, false)
	noteLabel.LayoutOrder = 8

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function render()
	local kick = math.max(state.kick, 1)
	local current
	for _, s in state.list do
		if s.id == state.target then
			current = s
		end
	end

	if state.active and current then
		targetLabel.Text = current.name
		local pct = math.clamp(current.score / kick, 0, 1)
		scoreFill.Size = UDim2.new(pct, 0, 1, 0)
		scoreFill.BackgroundColor3 = if pct >= 1 then BAD elseif pct >= 0.5 then WARN else ACCENT
	else
		targetLabel.Text = if state.active then "Waiting for a target" else "Not spectating"
		scoreFill.Size = UDim2.new(0, 0, 1, 0)
	end
	noteLabel.Text = state.note or ""

	for _, child in listFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, s in state.list do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -6, 0, 26)
		b.BackgroundColor3 = if s.id == state.target then Color3.fromRGB(22, 40, 48) else Color3.fromRGB(18, 24, 33)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Font = Enum.Font.Gotham
		b.TextSize = 13
		b.TextColor3 = if s.score >= kick * 0.5 then WARN else Color3.new(1, 1, 1)
		b.Text = string.format("  %s   %.0f   %s", s.name, s.score, s.top)
		corner(b, 5)
		b.Parent = listFrame
		b.Activated:Connect(function()
			Action:FireServer("spectate", s.id)
		end)
	end

	-- point the camera at whoever we're watching
	local targetPlayer = state.active and Players:GetPlayerByUserId(state.target)
	local hum = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
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

local function toggle()
	gui.Enabled = not gui.Enabled
	if gui.Enabled then
		Action:FireServer("list", 0)
	end
end

local function setup()
	if gui then
		return
	end
	build()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			toggle()
		end
	end)

	-- /spectate in chat, only created for admins
	local commands = TextChatService:FindFirstChild("TextChatCommands")
	if commands then
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "ACSpectate"
		cmd.PrimaryAlias = "/spectate"
		cmd.Triggered:Connect(function()
			gui.Enabled = true
			Action:FireServer("spectate", 0)
		end)
		cmd.Parent = commands
	end
end

function Spectator:Start()
	Action = Net.Event("ACAdminAction")

	Net.Event("ACAdmin"):Listen(function(info)
		if type(info) == "table" and info.spectator then
			setup()
		end
	end)

	Net.Event("ACSpectateState"):Listen(function(newState)
		if type(newState) ~= "table" or not gui then
			return
		end
		state = newState
		if state.active then
			gui.Enabled = true
		end
		render()
	end)
end

return Spectator
