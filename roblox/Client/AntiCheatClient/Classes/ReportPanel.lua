local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- the report button and window players see. only draws things and hands back what was picked,
-- ACReportController talks to the server
local ReportPanel = {}
ReportPanel.__index = ReportPanel

local ACCENT = Color3.fromRGB(34, 211, 238)
local GOOD = Color3.fromRGB(52, 211, 153)
local BAD = Color3.fromRGB(244, 63, 94)
local BG = Color3.fromRGB(13, 17, 23)
local LINE = Color3.fromRGB(29, 37, 49)
local MUTED = Color3.fromRGB(125, 136, 152)
local ROW = Color3.fromRGB(18, 24, 33)
local PICKED = Color3.fromRGB(22, 40, 48)
local WHITE = Color3.new(1, 1, 1)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent, color)
	local s = Instance.new("UIStroke")
	s.Color = color or LINE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function pad(parent, px)
	local p = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		p[side] = UDim.new(0, px)
	end
	p.Parent = parent
end

local function text(parent, value, size, color, bold, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = value
	l.TextSize = size
	l.TextColor3 = color
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.LayoutOrder = order or 0
	l.Parent = parent
	return l
end

-- onSend(targetUserId, reason, note)
function ReportPanel.new(parent, onSend)
	local self = setmetatable({ onSend = onSend, target = nil, reason = nil, reasons = {}, rows = {}, chips = {} }, ReportPanel)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ACReport"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.gui = gui

	-- the always-there button
	local open = Instance.new("TextButton")
	open.Name = "Open"
	open.AnchorPoint = Vector2.new(0, 1)
	open.Position = UDim2.new(0, 16, 1, -16)
	open.Size = UDim2.fromOffset(78, 32)
	open.BackgroundColor3 = BG
	open.BackgroundTransparency = 0.15
	open.Font = Enum.Font.GothamMedium
	open.TextSize = 14
	open.TextColor3 = WHITE
	open.Text = "Report"
	open.AutoButtonColor = true
	-- hidden until the server says reports are on
	open.Visible = false
	corner(open, 16)
	stroke(open)
	open.Parent = gui
	open.Activated:Connect(function()
		self:SetOpen(not self.window.Visible)
	end)
	self.button = open

	-- the window
	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	-- 92% of a phone screen, 340 wide on anything bigger
	window.Size = UDim2.new(0.92, 0, 0, 470)
	window.BackgroundColor3 = BG
	window.Visible = false
	corner(window, 12)
	stroke(window)
	pad(window, 16)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(340, 470)
	sizeLimit.Parent = window
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = window
	window.Parent = gui
	self.window = window

	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 24)
	head.LayoutOrder = 1
	head.Parent = window
	local title = text(head, "Report a player", 18, WHITE, true)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Size = UDim2.new(1, -30, 1, 0)
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(24, 24)
	close.BackgroundTransparency = 1
	close.Text = "×"
	close.TextColor3 = MUTED
	close.TextSize = 16
	close.Font = Enum.Font.GothamBold
	close.Parent = head
	close.Activated:Connect(function()
		self:SetOpen(false)
	end)

	text(window, "WHO", 11, MUTED, true, 2)
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 120)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 3
	list.ScrollBarImageColor3 = MUTED
	list.LayoutOrder = 3
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Parent = list
	list.Parent = window
	self.list = list

	text(window, "WHAT DID THEY DO", 11, MUTED, true, 4)
	local chips = Instance.new("Frame")
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, 0, 0, 0)
	chips.AutomaticSize = Enum.AutomaticSize.Y
	chips.LayoutOrder = 5
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, 28)
	grid.CellPadding = UDim2.fromOffset(8, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = chips
	chips.Parent = window
	self.chipBox = chips

	local note = Instance.new("TextBox")
	note.Size = UDim2.new(1, 0, 0, 34)
	note.BackgroundColor3 = ROW
	note.PlaceholderText = "What did you see? (optional)"
	note.PlaceholderColor3 = MUTED
	note.Text = ""
	note.TextColor3 = WHITE
	note.TextSize = 13
	note.Font = Enum.Font.Gotham
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.ClearTextOnFocus = false
	note.LayoutOrder = 6
	corner(note, 6)
	stroke(note)
	local notePad = Instance.new("UIPadding")
	notePad.PaddingLeft = UDim.new(0, 10)
	notePad.PaddingRight = UDim.new(0, 10)
	notePad.Parent = note
	note.Parent = window
	note:GetPropertyChangedSignal("Text"):Connect(function()
		if #note.Text > 100 then
			note.Text = string.sub(note.Text, 1, 100)
		end
	end)
	self.note = note

	local send = Instance.new("TextButton")
	send.Size = UDim2.new(1, 0, 0, 36)
	send.BackgroundColor3 = ACCENT
	send.Font = Enum.Font.GothamBold
	send.TextSize = 14
	send.TextColor3 = BG
	send.Text = "Send report"
	send.LayoutOrder = 7
	corner(send, 8)
	send.Parent = window
	send.Activated:Connect(function()
		if self.target and self.reason and not self.busy then
			self.busy = true
			send.Text = "Sending..."
			self.onSend(self.target, self.reason, note.Text)
		end
	end)
	self.send = send

	self.status = text(window, "", 12, MUTED, false, 8)

	-- small messages at the top of the screen: "thanks", "a player you reported was banned"
	local toast = Instance.new("TextLabel")
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, -60)
	toast.Size = UDim2.fromOffset(0, 36)
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.BackgroundColor3 = BG
	toast.Font = Enum.Font.GothamMedium
	toast.TextSize = 14
	toast.TextColor3 = WHITE
	toast.Text = ""
	toast.Visible = false
	corner(toast, 18)
	self.toastStroke = stroke(toast, GOOD)
	local toastPad = Instance.new("UIPadding")
	toastPad.PaddingLeft = UDim.new(0, 16)
	toastPad.PaddingRight = UDim.new(0, 16)
	toastPad.Parent = toast
	toast.Parent = gui
	self.toast = toast

	self:_refresh()
	self:Validate()
	gui.Parent = parent
	return self
end

function ReportPanel:SetEnabled(on)
	self.button.Visible = on
	if not on then
		self:SetOpen(false)
	end
end

function ReportPanel:SetOpen(open)
	self.window.Visible = open
	if open then
		self:_refresh()
		self.status.Text = ""
	end
end

function ReportPanel:SetReasons(reasons)
	if type(reasons) ~= "table" then
		return
	end
	self.reasons = reasons
	for _, chip in self.chips do
		chip:Destroy()
	end
	self.chips = {}
	for i, reason in reasons do
		if type(reason) == "string" then
			local chip = Instance.new("TextButton")
			chip.Text = reason
			chip.Font = Enum.Font.GothamMedium
			chip.TextSize = 13
			chip.TextColor3 = WHITE
			chip.BackgroundColor3 = ROW
			chip.LayoutOrder = i
			corner(chip, 6)
			stroke(chip)
			chip.Parent = self.chipBox
			chip.Activated:Connect(function()
				self.reason = reason
				self:_paint()
			end)
			self.chips[reason] = chip
		end
	end
	self:_paint()
end

-- rebuilds the player list, keeps the pick if they're still here
function ReportPanel:_refresh()
	for _, row in self.rows do
		row:Destroy()
	end
	self.rows = {}
	local me = Players.LocalPlayer
	local still = false
	for _, p in Players:GetPlayers() do
		if p ~= me then
			local row = Instance.new("TextButton")
			row.Name = string.lower(p.DisplayName)
			row.Size = UDim2.new(1, -6, 0, 30)
			row.BackgroundColor3 = ROW
			row.Text = ""
			row.AutoButtonColor = true
			corner(row, 6)
			local face = Instance.new("ImageLabel")
			face.BackgroundColor3 = LINE
			face.Size = UDim2.fromOffset(22, 22)
			face.Position = UDim2.fromOffset(5, 4)
			corner(face, 11)
			face.Parent = row
			task.spawn(function()
				local ok, img = pcall(Players.GetUserThumbnailAsync, Players, p.UserId,
					Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
				if ok then
					face.Image = img
				end
			end)
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.fromOffset(36, 0)
			name.Size = UDim2.new(1, -42, 1, 0)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 13
			name.TextColor3 = WHITE
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = if p.DisplayName ~= p.Name then `{p.DisplayName}  <font color="#7d8898">@{p.Name}</font>` else p.Name
			name.RichText = true
			name.Parent = row
			row.Parent = self.list
			row.Activated:Connect(function()
				self.target = p.UserId
				self:_paint()
			end)
			self.rows[p.UserId] = row
			if p.UserId == self.target then
				still = true
			end
		end
	end
	if not still then
		self.target = nil
	end
	if next(self.rows) == nil then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 30)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 13
		empty.TextColor3 = MUTED
		empty.Text = "Nobody else is in this server."
		empty.Parent = self.list
		self.rows[0] = empty
	end
	self:_paint()
end

function ReportPanel:_paint()
	for id, row in self.rows do
		if row:IsA("TextButton") then
			row.BackgroundColor3 = if id == self.target then PICKED else ROW
		end
	end
	for reason, chip in self.chips do
		chip.BackgroundColor3 = if reason == self.reason then PICKED else ROW
		chip.TextColor3 = if reason == self.reason then ACCENT else WHITE
	end
	self:Validate()
end

function ReportPanel:Validate()
	local ready = self.target ~= nil and self.reason ~= nil and not self.busy
	self.send.AutoButtonColor = ready
	self.send.BackgroundTransparency = if ready then 0 else 0.6
end

-- the server answered
function ReportPanel:Result(ok, message)
	self.busy = false
	self.send.Text = "Send report"
	if ok then
		self.target, self.reason = nil, nil
		self.note.Text = ""
		self:SetOpen(false)
		self:Toast(message, true)
	else
		self.status.TextColor3 = BAD
		self.status.Text = message
	end
	self:_paint()
end

function ReportPanel:Toast(message, good)
	local toast = self.toast
	toast.Text = message
	self.toastStroke.Color = if good == false then BAD else GOOD
	toast.Visible = true
	toast.Position = UDim2.new(0.5, 0, 0, -60)
	TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, 16) }):Play()
	local stamp = os.clock()
	self.toastAt = stamp
	task.delay(4.5, function()
		if self.toastAt == stamp then
			local out = TweenService:Create(toast, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -60) })
			out:Play()
			out.Completed:Wait()
			if self.toastAt == stamp then
				toast.Visible = false
			end
		end
	end)
end

return ReportPanel
