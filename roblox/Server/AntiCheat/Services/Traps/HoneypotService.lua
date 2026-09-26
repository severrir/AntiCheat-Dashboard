local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)
local Net = require(ReplicatedStorage.Shared.Net)

-- bait remotes and fake secret values. nothing real ever touches them, only exploit tools poking
-- around. they're made with Net like every real remote, so they sit in the same folder, names
-- shuffled every server. every other trap (vault, bait npc, bait coin) trips through here too
local HoneypotService = { Name = "ACHoneypotService" }

local EVENT_NAMES = {
	"AdminCommand", "GiveCash", "AddCoins", "GiveItem", "SetLevel", "UnlockAll",
	"KillPlayer", "DevConsole", "GiveGamepass", "SetMoney", "RewardPlayer", "ModAction",
}
local FUNCTION_NAMES = { "GetAdminKey", "RequestAdmin", "FetchDevToken", "GetServerKey" }
local VALUE_NAMES = { "AdminKey", "DevBypassToken", "ServerSecret", "ModToken" }
local DEBOUNCE = 5

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

function HoneypotService:Init()
	self._canaries = {}
	self._lastTrip = {}
end

-- one hit from any trap is proof on its own
function HoneypotService:Trip(target, kind)
	local profile = if typeof(target) == "Instance" then self._players:Get(target) else target
	if not profile then
		return
	end
	local now = os.clock()
	local last = self._lastTrip[profile]
	if last and now - last < DEBOUNCE then
		return
	end
	self._lastTrip[profile] = now
	self._trust:Flag(profile, "Honeypot", 150, { kind = kind })
end

-- NetGuardService runs every string any Net remote receives through here
function HoneypotService:Scan(player, text)
	if not Config.On("Honeypot") then
		return false
	end
	for _, token in self._canaries do
		if string.find(text, token, 1, true) then
			self:Trip(player, "Canary")
			return true
		end
	end
	return false
end

function HoneypotService:_plantRemotes()
	local netFolder = ReplicatedStorage:WaitForChild("_Net")
	for _, name in pick(EVENT_NAMES, 5) do
		local remoteName = freeName(netFolder, styled(name))
		Net.Event(remoteName):Listen(function(player)
			if Config.On("Honeypot") then
				self:Trip(player, "Remote:" .. remoteName)
			end
		end)
	end
	for _, name in pick(FUNCTION_NAMES, 2) do
		local remoteName = freeName(netFolder, styled(name))
		Net.Function(remoteName):Handle(function(player)
			if Config.On("Honeypot") then
				self:Trip(player, "Function:" .. remoteName)
			end
			-- hand back a canary, if they ever send it anywhere they're done
			return self._canaries[1]
		end)
	end
end

-- fake secrets. anyone who reads one and sends it back through any remote gets caught
function HoneypotService:_plantCanaries()
	for _, name in pick(VALUE_NAMES, 2) do
		local token = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 20)
		table.insert(self._canaries, token)
		local value = Instance.new("StringValue")
		value.Name = freeName(ReplicatedStorage, name)
		value.Value = token
		value.Parent = ReplicatedStorage
	end
end

function HoneypotService:Start()
	self._players = Framework.Get("ACPlayerService")
	self._trust = Framework.Get("ACTrustService")

	self:_plantCanaries()
	self:_plantRemotes()

	self._players.Removing:Connect(function(profile)
		self._lastTrip[profile] = nil
	end)
end

return HoneypotService
