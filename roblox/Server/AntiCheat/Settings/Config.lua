local Signal = require(script:FindFirstAncestor("AntiCheat").Classes.Core.Signal)

local Config = {}

Config.Admins = {
	[5647285586] = true,
}

Config.CheckAdminsInStudio = true

Config.Backend = {
	Url = "https://kapvjoemzsdqiealluzl.supabase.co/functions/v1/game",
	SecretName = "anticheat_key",
	SyncInterval = 20,
	PulseInterval = 5,
	MaxBackoff = 120,
	MaxQueue = 400,
}

Config.Features = {
	Movement = true,
	Character = true,
	Timing = true,
	Statistical = true,
	Combat = true,
	Client = true,
	NetGuard = true,
	Honeypot = true,
	TrapVault = true,
	BaitNPC = true,
	BaitCoin = true,
	Replays = true,
	MapExport = true,
	MissionControl = true,
	Spectator = true,
	CheaterIsland = false,
	AltDetection = true,
	GlobalBans = true,
	CrossServerTrust = true,
	ShadowMode = true,
	Reports = true,
	RevertGains = true,
}

Config.Thresholds = {
	KickScore = 100,
	HalfLife = 45,
	MinCorroboratingChecks = 2,

	SpeedMargin = 1.35,
	TeleportDistance = 45,
	FlyTime = 2.5,
	FlyHeight = 12,

	RemoteBurstMultiplier = 2,
	HeartbeatTimeout = 25,
	TimingMinCV = 0.035,
	AccuracyCap = 0.92,

	ShadowScore = 60,

	WeightMovement = 1,
	WeightCharacter = 1,
	WeightRemote = 1,
	WeightStatistical = 1,
	WeightTiming = 1,
	WeightHoneypot = 1,
	WeightClient = 1,
	WeightCombat = 1,
}

Config.Definitive = {
	Honeypot = true,
}

Config.KickMessage = "You were disconnected. If this keeps happening, contact the developers."
Config.BanMessage = "You are banned from this experience."
Config.AppealUrl = "https://severrir.github.io/AntiCheat-Dashboard/#/appeal"

Config.HotRate = 10
Config.ColdRate = 0.5
Config.HistorySeconds = 20
Config.RecordPoses = true

Config.Vault = {
	Position = Vector3.new(6000, 400, -6000),
	Size = Vector3.new(40, 30, 40),
}

Config.ReportButton = true
Config.ReportReasons = { "Flying", "Speed", "Teleporting", "Aimbot", "Kill aura", "Exploiting", "Other" }

Config.AutoLeaderstats = true

Config.CarryHalfLifeHours = 6

Config.Changed = Signal.new()

local defaults = {
	Features = table.clone(Config.Features),
	Thresholds = table.clone(Config.Thresholds),
}
local appliedVersion = 0

local function merge(target, base, incoming, isValid)
	incoming = if type(incoming) == "table" then incoming else {}
	for key, default in base do
		local v = incoming[key]
		target[key] = if isValid(v) then v else default
	end
end

function Config.ApplyRemote(remote)
	if type(remote) ~= "table" or type(remote.version) ~= "number" or remote.version == appliedVersion then
		return
	end
	appliedVersion = remote.version

	merge(Config.Thresholds, defaults.Thresholds, remote.thresholds, function(v)
		return type(v) == "number" and v == v and v >= 0 and v < 1e5
	end)
	merge(Config.Features, defaults.Features, remote.features, function(v)
		return type(v) == "boolean"
	end)

	Config.Changed:Fire()
end

function Config.On(feature)
	return Config.Features[feature] == true
end

return Config
