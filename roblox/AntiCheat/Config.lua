local Config = {}

-- these people skip every check
Config.Admins = {
	[5647285586] = true,
}

Config.Backend = {
	Url = "https://kapvjoemzsdqiealluzl.supabase.co/functions/v1/game",
	SecretName = "anticheat_key",
	SyncInterval = 20,
	MaxBackoff = 120,
	MaxQueue = 400,
}

-- everything here can be changed live from the dashboard, no republish
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

	WeightMovement = 1,
	WeightCharacter = 1,
	WeightRemote = 1,
	WeightStatistical = 1,
	WeightTiming = 1,
	WeightHoneypot = 1,
	WeightClient = 1,
	WeightCombat = 1,
}

Config.Defaults = table.clone(Config.Thresholds)

-- proof on their own, no second check needed before kicking
Config.Definitive = {
	Honeypot = true,
}

Config.KickMessage = "You were disconnected. If this keeps happening, contact the developers."
Config.BanMessage = "You are banned from this experience."

Config.HotRate = 10
Config.ColdRate = 0.5

local appliedVersion = 0

function Config.ApplyRemote(remote)
	if type(remote) ~= "table" or type(remote.version) ~= "number" then
		return
	end
	if remote.version == appliedVersion then
		return
	end
	appliedVersion = remote.version

	-- start from defaults so removing a value on the site actually resets it
	local incoming = type(remote.thresholds) == "table" and remote.thresholds or {}
	for key, default in Config.Defaults do
		local v = incoming[key]
		if type(v) == "number" and v == v and v >= 0 and v < 1e5 then
			Config.Thresholds[key] = v
		else
			Config.Thresholds[key] = default
		end
	end
end

return Config
