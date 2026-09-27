local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)
local API = require(game.ServerScriptService.AntiCheat.API)

local toast = Net.Event("ACReportState")

local function say(player, text)
	print("[ACTest] " .. text)
	toast:Fire(player, { message = text })
end

local function coins(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local c = stats:FindFirstChild("Coins")
	if not c then
		c = Instance.new("IntValue")
		c.Name = "Coins"
		c.Parent = stats
	end
	return c
end

local function dummy(profile)
	local model = workspace:FindFirstChild("ACTestDummy")
	if not model then
		model = Instance.new("Model")
		model.Name = "ACTestDummy"
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Anchored = true
		root.Parent = model
		Instance.new("Humanoid").Parent = model
		model.PrimaryPart = root
		model.Parent = workspace
	end
	model:PivotTo(profile.root.CFrame * CFrame.new(0, 0, -4))
	return model
end

local commands = {}

function commands.acstate(player, profile)
	say(player, string.format("score %.0f · shadow %s · Coins %d", profile:Score(), tostring(profile.shadow or "off"), coins(player).Value))
end

function commands.acshadow(player)
	API.Shadow(player, true)
	say(player, "Shadow mode ON. Try /achit and /acgrant 100")
end

function commands.acunshadow(player)
	API.Shadow(player, false)
	say(player, "Shadow mode off")
end

function commands.acgrant(player, _, arg)
	local amount = tonumber(arg) or 100
	local got = API.Grant(player, "Gems", amount, "test kit")
	say(player, string.format("Asked for %d Gems, the anticheat allowed %d", amount, got))
end

function commands.accoins(player, _, arg)
	local c = coins(player)
	c.Value += tonumber(arg) or 50
	say(player, "Coins now " .. c.Value .. " (recorded, a ban or undo takes it back)")
end

function commands.achit(player, profile)
	if not profile.root then
		say(player, "spawn first")
		return
	end
	local ok = API.ValidateHit(player, dummy(profile), { Range = 10, Cooldown = 0, LineOfSight = false })
	say(player, if ok then "Hit landed" else "Hit blocked (shadow mode)")
end

function commands.acreport(player, profile)
	local recorder = Framework.Get("ACRecorderService")
	local backend = Framework.Get("ACBackendService")
	profile:AddReport(1)
	backend:Track(function()
		local replay = recorder:Upload(recorder:Capture(profile, "capture", "reported for Flying by TestReporter"))
		backend:QueueReport({
			target = tostring(player.UserId),
			reporter = "1",
			reason = "Flying",
			w = 1,
			score = profile:Score(),
			name = player.Name,
			by = "TestReporter",
			note = "saw them flying over the map",
			replay = replay,
		})
		backend:Sync()
		say(player, "Fake report sent. Check the Reports tab on the dashboard")
	end)
end

function commands.acreplay(player, profile)
	local recorder = Framework.Get("ACRecorderService")
	local backend = Framework.Get("ACBackendService")
	local recording = recorder:Capture(profile, "capture", "test replay from /acreplay")
	backend:Track(function()
		local id = recorder:Upload(recording)
		say(player, if id then "Replay #" .. id .. " saved, open it from your player page" else "Replay upload failed")
	end)
end

function commands.acboost(player, _, arg)
	local speed = tonumber(arg) or 60
	API.AllowSpeed(player, speed, 15)
	say(player, "Speed up to " .. speed .. " allowed for 15s. Set your WalkSpeed on the client to try it")
end

function commands.acjump(player, _, arg)
	local power = tonumber(arg) or 120
	API.AllowJump(player, power, 15)
	say(player, "JumpPower up to " .. power .. " allowed for 15s")
end

function commands.acfly(player, _, arg)
	API.AllowFly(player, 15, tonumber(arg))
	say(player, "Flying allowed for 15s")
end

function commands.actp(player, profile)
	if not profile.root then
		say(player, "spawn first")
		return
	end
	API.Teleport(player, profile.root.CFrame * CFrame.new(0, 0, -100))
	say(player, "Teleported 100 studs forward through AntiCheat.Teleport, nothing should be flagged")
end

function commands.actpwrong(player, profile)
	if not profile.root then
		say(player, "spawn first")
		return
	end
	local target = profile.root.CFrame * CFrame.new(0, 0, -100)
	API.ExpectTeleport(player, target.Position, 8, 3)
	profile.char:PivotTo(target * CFrame.new(40, 0, 0))
	say(player, "Expected a teleport 100 studs ahead but landed 40 studs off, this should be flagged")
end

local folder = TextChatService:WaitForChild("TextChatCommands", 10)
for name, run in commands do
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "ACTest_" .. name
	cmd.PrimaryAlias = "/" .. name
	cmd.Parent = folder
	cmd.Triggered:Connect(function(source, text)
		local player = Players:GetPlayerByUserId(source.UserId)
		local profile = player and Framework.Get("ACPlayerService"):Get(player)
		if not profile then
			return
		end
		local arg = string.match(text, "^%S+%s+(%S+)")
		local ok, err = pcall(run, player, profile, arg)
		if not ok then
			warn("[ACTest] " .. tostring(err))
		end
	end)
end
print("[ACTest] test commands ready: /acstate /acshadow /acunshadow /acgrant /accoins /achit /acreport /acreplay /acboost /acjump /acfly /actp /actpwrong")
