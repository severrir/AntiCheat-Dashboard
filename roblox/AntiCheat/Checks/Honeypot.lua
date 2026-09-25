local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(script.Parent.Parent.Core.Registry)
local TrustService = require(script.Parent.Parent.Core.TrustService)

-- bait. nothing in the real game ever touches these, only exploit tools poking around.
-- names get shuffled every server so nobody can hardcode a skip list
local Honeypot = { Name = "Honeypot" }

local EVENT_NAMES = {
	"AdminCommand", "GiveCash", "AddCoins", "GiveItem", "SetLevel", "UnlockAll",
	"KillPlayer", "DevConsole", "GiveGamepass", "SetMoney", "RewardPlayer", "ModAction",
}
local FUNCTION_NAMES = { "GetAdminKey", "RequestAdmin", "FetchDevToken", "GetServerKey" }
local VALUE_NAMES = { "AdminKey", "DevBypassToken", "ServerSecret", "ModToken" }

local canaries = {}
local canaryList = {}
local lastFlag = {}

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

local function newToken()
	return string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 20)
end

local function trip(player, what)
	local profile = Registry.Get(player)
	if not profile then
		return
	end
	-- one flag is already a kick, no need to log a spam of them
	local now = os.clock()
	if lastFlag[player] and now - lastFlag[player] < 5 then
		return
	end
	lastFlag[player] = now
	TrustService.Flag(profile, "Honeypot", 150, { kind = what })
end

local function freeName(parent, name)
	while parent:FindFirstChild(name) do
		name ..= math.random(9)
	end
	return name
end

function Honeypot.Init()
	local folder = Instance.new("Folder")
	folder.Name = freeName(ReplicatedStorage, pick({ "Events", "Network", "RemoteStorage", "Signals" }, 1)[1])
	folder.Parent = ReplicatedStorage

	for i, name in pick(EVENT_NAMES, 5) do
		local remote = Instance.new("RemoteEvent")
		local parent = if i % 2 == 0 then ReplicatedStorage else folder
		remote.Name = freeName(parent, styled(name))
		remote.OnServerEvent:Connect(function(player)
			trip(player, "Remote:" .. remote.Name)
		end)
		remote.Parent = parent
	end

	for _, name in pick(FUNCTION_NAMES, 2) do
		local fn = Instance.new("RemoteFunction")
		fn.Name = freeName(folder, styled(name))
		fn.OnServerInvoke = function(player)
			trip(player, "Function:" .. fn.Name)
			return canaryList[1]
		end
		fn.Parent = folder
	end

	-- fake secrets. anyone who reads one and sends it back through any remote is caught
	for _, name in pick(VALUE_NAMES, 2) do
		local token = newToken()
		canaries[token] = true
		table.insert(canaryList, token)
		local value = Instance.new("StringValue")
		value.Name = freeName(ReplicatedStorage, name)
		value.Value = token
		value.Parent = ReplicatedStorage
	end

	Registry.Removing:Connect(function(profile)
		lastFlag[profile.player] = nil
	end)
end

-- called by RemoteGuard on every string argument
function Honeypot.Scan(player, text)
	for token in canaries do
		if string.find(text, token, 1, true) then
			trip(player, "Canary")
			return true
		end
	end
	return false
end

return Honeypot
