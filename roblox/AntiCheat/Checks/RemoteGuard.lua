local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Parent.Config)
local Registry = require(script.Parent.Parent.Core.Registry)
local TrustService = require(script.Parent.Parent.Core.TrustService)
local InputTiming = require(script.Parent.InputTiming)
local Honeypot = require(script.Parent.Honeypot)

local T = Config.Thresholds

-- wrap your remotes with this and you get arg validation + rate limits for free.
-- bad calls never reach your handler
local RemoteGuard = { Name = "Remote" }
RemoteGuard.__index = RemoteGuard

local registry = {}
local defaultFolder

local function folder()
	if not defaultFolder then
		defaultFolder = ReplicatedStorage:FindFirstChild("Remotes")
		if not defaultFolder then
			defaultFolder = Instance.new("Folder")
			defaultFolder.Name = "Remotes"
			defaultFolder.Parent = ReplicatedStorage
		end
	end
	return defaultFolder
end

local function finite(n)
	return n == n and n > -math.huge and n < math.huge
end

local function parseSpec(spec)
	if type(spec) == "function" then
		return { custom = spec }
	end
	local optional = string.sub(spec, -1) == "?"
	if optional then
		spec = string.sub(spec, 1, -2)
	end
	local kind, class = string.match(spec, "^(%w+):(%w+)$")
	return { kind = kind or spec, class = class, optional = optional }
end

local function scanString(player, s, maxLen)
	if #s > maxLen or utf8.len(s) == nil then
		return false
	end
	return not Honeypot.Scan(player, s)
end

local function valid(player, value, spec, maxLen)
	if value == nil then
		return spec.optional
	end
	if spec.custom then
		return spec.custom(value) == true
	end
	local kind = spec.kind
	if kind == "any" then
		return true
	elseif kind == "number" then
		return type(value) == "number" and finite(value)
	elseif kind == "integer" then
		return type(value) == "number" and finite(value) and value % 1 == 0
	elseif kind == "string" then
		return type(value) == "string" and scanString(player, value, maxLen)
	elseif kind == "boolean" then
		return type(value) == "boolean"
	elseif kind == "Vector3" then
		return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
	elseif kind == "CFrame" then
		if typeof(value) ~= "CFrame" then
			return false
		end
		local p = value.Position
		return finite(p.X) and finite(p.Y) and finite(p.Z)
	elseif kind == "Instance" then
		return typeof(value) == "Instance" and (spec.class == nil or value:IsA(spec.class))
	elseif kind == "table" then
		if type(value) ~= "table" then
			return false
		end
		local count = 0
		for _, v in value do
			count += 1
			if count > 64 then
				return false
			end
			if type(v) == "string" and not scanString(player, v, maxLen) then
				return false
			end
		end
		return true
	end
	return false
end

function RemoteGuard.new(name, opts)
	assert(type(name) == "string", "remote needs a name")
	if registry[name] then
		return registry[name]
	end
	opts = opts or {}

	local specs = {}
	for i, spec in opts.Args or {} do
		specs[i] = parseSpec(spec)
	end

	local self = setmetatable({
		Name = name,
		specs = specs,
		rate = opts.Rate or 10,
		burst = opts.Burst or (opts.Rate or 10) * 2,
		maxString = opts.MaxString or 200,
		handlers = {},
	}, RemoteGuard)

	local instance = Instance.new(if opts.Function then "RemoteFunction" else "RemoteEvent")
	instance.Name = name
	self.Instance = instance

	if opts.Function then
		instance.OnServerInvoke = function(player, ...)
			if self:_allow(player, ...) and self.callback then
				return self.callback(player, ...)
			end
			return nil
		end
	else
		instance.OnServerEvent:Connect(function(player, ...)
			if self:_allow(player, ...) then
				for _, fn in self.handlers do
					task.spawn(fn, player, ...)
				end
			end
		end)
	end

	instance.Parent = opts.Parent or folder()
	registry[name] = self
	return self
end

function RemoteGuard:_allow(player, ...)
	local profile = Registry.Get(player)
	if not profile or profile.kicked then
		return false
	end
	local now = os.clock()

	-- token bucket
	local b = profile.buckets[self.Name]
	if not b then
		b = { tokens = self.burst, at = now, dropped = 0, dropAt = now }
		profile.buckets[self.Name] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.at) * self.rate)
	b.at = now
	if b.tokens < 1 then
		if now - b.dropAt > 1 then
			b.dropped, b.dropAt = 0, now
		end
		b.dropped += 1
		if b.dropped > self.rate * T.RemoteBurstMultiplier then
			b.dropped = 0
			TrustService.Flag(profile, "Remote", 8, { kind = "RateLimit", remote = self.Name })
		end
		return false
	end
	b.tokens -= 1

	InputTiming.Record(profile, self.Name, now)

	local count = select("#", ...)
	local limit = if #self.specs > 0 then #self.specs else 16
	if count > limit then
		TrustService.Flag(profile, "Remote", 5, { kind = "ExtraArgs", remote = self.Name, count = count })
		return false
	end
	for i, spec in self.specs do
		if not valid(player, (select(i, ...)), spec, self.maxString) then
			TrustService.Flag(profile, "Remote", 5, { kind = "BadArgs", remote = self.Name, arg = i })
			return false
		end
	end
	return true
end

function RemoteGuard:Connect(fn)
	table.insert(self.handlers, fn)
end

function RemoteGuard:SetCallback(fn)
	self.callback = fn
end

function RemoteGuard:FireClient(player, ...)
	self.Instance:FireClient(player, ...)
end

function RemoteGuard:FireAllClients(...)
	self.Instance:FireAllClients(...)
end

return RemoteGuard
