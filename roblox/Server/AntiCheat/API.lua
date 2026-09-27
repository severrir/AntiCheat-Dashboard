local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage.Shared.Framework)

local API = {}

local function service(name: string): any
	return Framework.Get(name)
end

function API.Exempt(player: Player, check: string, seconds: number)
	local profile = service("ACPlayerService"):Get(player)
	if profile and type(check) == "string" and type(seconds) == "number" then
		profile:Exempt(check, math.clamp(seconds, 0, 60))
	end
end

local function profileOf(player: Player)
	return service("ACPlayerService"):Get(player)
end

local function noop() end

type Stop = () -> ()

local function allow(kind: string, player: Player, value: number, seconds: number): Stop
	local profile = profileOf(player)
	if not profile or type(value) ~= "number" or value < 0 or type(seconds) ~= "number" or seconds <= 0 then
		return noop
	end
	return profile:Allow(kind, value, math.min(seconds, 600))
end

function API.AllowSpeed(player: Player, walkSpeed: number, seconds: number): Stop
	return allow("Speed", player, walkSpeed, seconds)
end

function API.AllowJump(player: Player, jumpPower: number, seconds: number): Stop
	return allow("Jump", player, jumpPower, seconds)
end

function API.AllowFly(player: Player, seconds: number, speed: number?): Stop
	return allow("Fly", player, speed or 0, seconds)
end

function API.ExpectTeleport(player: Player, position: Vector3 | CFrame, radius: number?, seconds: number?): Stop
	local profile = profileOf(player)
	if typeof(position) == "CFrame" then
		position = position.Position
	end
	if not profile or typeof(position) ~= "Vector3" then
		return noop
	end
	return profile:ExpectTeleport(position, math.clamp(radius or 8, 1, 200), math.clamp(seconds or 3, 0.1, 60))
end

function API.Teleport(player: Player, target: CFrame | Vector3): boolean
	local char = player.Character
	if not char or not char.PrimaryPart then
		return false
	end
	local cf = if typeof(target) == "Vector3" then CFrame.new(target) * char.PrimaryPart.CFrame.Rotation else target
	if typeof(cf) ~= "CFrame" then
		return false
	end
	API.ExpectTeleport(player, cf.Position, 8, 3)
	char:PivotTo(cf)
	return true
end

function API.GetScore(player: Player): number
	local profile = service("ACPlayerService"):Get(player)
	return if profile then profile:Score() else 0
end

function API.Flag(player: Player, check: string, severity: number, ctx: { [string]: any }?)
	if type(check) ~= "string" or not string.match(check, "^%a+$") or #check > 24 then
		check = "Custom"
	end
	service("ACTrustService"):Flag(player, check, severity, if type(ctx) == "table" then ctx else nil)
end

function API.ValidateHit(attacker: Player, victim: Model | Player, opts: { [string]: any }?): boolean
	return service("ACCombatService"):ValidateHit(attacker, victim, opts)
end

function API.RecordMiss(attacker: Player)
	service("ACCombatService"):RecordMiss(attacker)
end

function API.RecordStat(player: Player, name: string, value: number, lowerIsSuspicious: boolean?)
	service("ACStatsService"):Record(player, name, value, lowerIsSuspicious)
end

function API.OnFlagged(fn)
	return service("ACTrustService").Flagged:Connect(fn)
end

function API.OnKicked(fn)
	return service("ACEnforcementService").Kicked:Connect(fn)
end

function API.IsShadowed(player: Player): boolean
	return service("ACShadowService"):IsShadowed(player)
end

function API.Shadow(player: Player, on: boolean?)
	local profile = service("ACPlayerService"):Get(player)
	if not profile then
		return
	end
	if on == false then
		service("ACShadowService"):Clear(profile)
	else
		service("ACShadowService"):Set(profile, "staff", "from game code")
	end
end

function API.Grant(player: Player | number, key: string, amount: number, source: string?): number
	return service("ACLedgerService"):Grant(player, key, amount, source)
end

function API.GrantItem(player: Player | number, item: string, source: string?): boolean
	return service("ACLedgerService"):GrantItem(player, item, source)
end

function API.RecordKill(killer: Player | number, victim: (Player | number)?)
	service("ACLedgerService"):RecordKill(killer, victim)
end

function API.Transfer(from: Player | number, to: Player | number, what: string, amount: number?)
	service("ACLedgerService"):Transfer(from, to, what, amount)
end

function API.OnRevert(fn)
	service("ACRevertService"):OnRevert(fn)
end

function API.Report(reporter: Player, target: Player | number, reason: string, note: string?)
	return service("ACReportService"):Report(reporter, target, reason, note)
end

function API.IsBait(model: Instance): boolean
	return service("ACBaitNpcService"):IsBait(model)
end

return API
