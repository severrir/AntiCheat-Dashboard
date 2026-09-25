local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

-- bait remotes and fake secret values. nothing real ever touches them, only exploit tools poking
-- around. they live in Net's folder right next to the real remotes, names shuffled every server
local Honeypot = { Name = "ACHoneypot" }

local EVENT_NAMES = {
	"AdminCommand", "GiveCash", "AddCoins", "GiveItem", "SetLevel", "UnlockAll",
	"KillPlayer", "DevConsole", "GiveGamepass", "SetMoney", "RewardPlayer", "ModAction",
}
local FUNCTION_NAMES = { "GetAdminKey", "RequestAdmin", "FetchDevToken", "GetServerKey" }
local VALUE_NAMES = { "AdminKey", "DevBypassToken", "ServerSecret", "ModToken" }

local PlayerService, Trust
local canaries = {}
local canaryList = {}
local lastTrip = {}

local function pick(list, count)
	local copy = table.clone(list)
	local out = {}
	for _ = 1, math.min(count, #copy) do
		table.insert(out, table.remove(copy, math.random(#copy)))
	end
	return out
end

local function styled(name)
	local roll = math.random(3)
	if roll == 1 then
		return name
	elseif roll == 2 then
		return name .. "Remote"
	end
	return string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

local function freeName(parent, name)
	while parent:FindFirstChild(name) do
		name ..= math.random(9)
	end
	return name
end

-- shared by every trap: vault, bait npc, bait coin. one hit is already a kick
function Honeypot.Trip(target, kind)
	local profile = if typeof(target) == "Instance" then PlayerService.Get(target) else target
	if not profile then
		return
	end
	local now = os.clock()
	if lastTrip[profile] and now - lastTrip[profile] < 5 then
		return
	end
	lastTrip[profile] = now
	Trust.Flag(profile, "Honeypot", 150, { kind = kind })
end

-- called by NetGuard on every string any Net remote receives
function Honeypot.Scan(player, text)
	if not Config.On("Honeypot") then
		return false
	end
	for _, token in canaryList do
		if string.find(text, token, 1, true) then
			Honeypot.Trip(player, "Canary")
			return true
		end
	end
	return false
end

function Honeypot:Start()
	PlayerService = Framework.Get("ACPlayers")
	Trust = Framework.Get("ACTrust")

	local netFolder = ReplicatedStorage:WaitForChild("_Net")
	for _, name in pick(EVENT_NAMES, 5) do
		local remoteName = freeName(netFolder, styled(name))
		Net.Event(remoteName):Listen(function(player)
			if Config.On("Honeypot") then
				Honeypot.Trip(player, "Remote:" .. remoteName)
			end
		end)
	end

	for _, name in pick(FUNCTION_NAMES, 2) do
		local remoteName = freeName(netFolder, styled(name))
		Net.Function(remoteName):Handle(function(player)
			if Config.On("Honeypot") then
				Honeypot.Trip(player, "Function:" .. remoteName)
			end
			-- hand back a canary, if they ever send it anywhere they're done
			return canaryList[1]
		end)
	end

	-- fake secrets. anyone who reads one and sends it back through any remote gets caught
	for _, name in pick(VALUE_NAMES, 2) do
		local token = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 20)
		canaries[token] = true
		table.insert(canaryList, token)
		local value = Instance.new("StringValue")
		value.Name = freeName(ReplicatedStorage, name)
		value.Value = token
		value.Parent = ReplicatedStorage
	end

	PlayerService.Removing:Connect(function(profile)
		lastTrip[profile] = nil
	end)
end

return Honeypot
