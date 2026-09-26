-- the admin spectator panel. only draws things and reports clicks,
-- ACSpectatorController decides what they mean
local SpectatorPanel = {}
SpectatorPanel.__index = SpectatorPanel

local ACCENT = Color3.fromRGB(34, 211, 238)
local BAD = Color3.fromRGB(244, 63, 94)
local WARN = Color3.fromRGB(251, 191, 36)
local BG = Color3.fromRGB(13, 17, 23)
local LINE = Color3.fromRGB(29, 37, 49)
local MUTED = Color3.fromRGB(125, 136, 152)
local ROW = Color3.fromRGB(18, 24, 33)
local ROW_ACTIVE = Color3.fromRGB(22, 40, 48)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent)
	local s = Instance.new("UIStroke")
	s.Color = LINE
	s.Parent = parent
end

local function label(parent, text, size, color, bold, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.LayoutOrder = order or 0
	l.Parent = parent
	return l
end

local function button(parent, text, color, onClick)
	local b = Instance.new("TextButton")
	b.Text = text
	b.TextSize = 13
	b.Font = Enum.Font.GothamMedium
	b.TextColor3 = color
	b.BackgroundColor3 = ROW
	b.AutoButtonColor = true
	b.Size = UDim2.new(0.25, -6, 0, 30)
	corner(b, 6)
	stroke(b)
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

-- onAction(action, targetId) gets called for every button press
function SpectatorPanel.new(parent, onAction)
	local self = setmetatable({ onAction = onAction }, SpectatorPanel)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ACAdmin"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false
	self.gui = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -16)
	panel.Size = UDim2.fromOffset(300, 360)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	corner(panel, 10)
	stroke(panel)
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

	label(panel, "ANTICHEAT · SPECTATOR", 11, MUTED, true, 1)
	self.target = label(panel, "Not spectating", 18, Color3.new(1, 1, 1), true, 2)

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 6)
	bar.BackgroundColor3 = LINE
	bar.LayoutOrder = 3
	corner(bar, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = ACCENT
	corner(fill, 3)
	fill.Parent = bar
	bar.Parent = panel
	self.fill = fill

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
		onAction("prev", 0)
	end)
	button(row, "▶", Color3.new(1, 1, 1), function()
		onAction("next", 0)
	end)
	button(row, "Watch", ACCENT, function()
		onAction("spectate", 0)
	end)
	button(row, "Stop", BAD, function()
		onAction("stop", 0)
	end)

	label(panel, "SUSPECTS", 11, MUTED, true, 5)

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 170)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 3
	list.LayoutOrder = 6
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list
	list.Parent = panel
	self.list = list

	local foot = Instance.new("Frame")
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, 30)
	foot.LayoutOrder = 7
	foot.Parent = panel
	local rec = button(foot, "● Record my session", WARN, function()
		onAction("record", 0)
	end)
	rec.Size = UDim2.new(1, 0, 0, 30)

	self.note = label(panel, "", 12, MUTED, false, 8)

	gui.Parent = parent
	return self
end

function SpectatorPanel:IsOpen()
	return self.gui.Enabled
end

function SpectatorPanel:SetOpen(open)
	self.gui.Enabled = open
end

-- state = { active, target, kick, list = { {id, name, score, top} }, note }
function SpectatorPanel:Render(state)
	local kick = math.max(state.kick or 100, 1)
	local current
	for _, s in state.list do
		if s.id == state.target then
			current = s
		end
	end

	if state.active and current then
		self.target.Text = current.name
		local pct = math.clamp(current.score / kick, 0, 1)
		self.fill.Size = UDim2.new(pct, 0, 1, 0)
		self.fill.BackgroundColor3 = if pct >= 1 then BAD elseif pct >= 0.5 then WARN else ACCENT
	else
		self.target.Text = if state.active then "Waiting for a target" else "Not spectating"
		self.fill.Size = UDim2.new(0, 0, 1, 0)
	end
	self.note.Text = state.note or ""

	for _, child in self.list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, s in state.list do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -6, 0, 26)
		b.BackgroundColor3 = if s.id == state.target then ROW_ACTIVE else ROW
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Font = Enum.Font.Gotham
		b.TextSize = 13
		b.TextColor3 = if s.score >= kick * 0.5 then WARN else Color3.new(1, 1, 1)
		b.Text = string.format("  %s   %.0f   %s", s.name, s.score, s.top)
		corner(b, 5)
		b.Parent = self.list
		b.Activated:Connect(function()
			self.onAction("spectate", s.id)
		end)
	end
end

return SpectatorPanel
