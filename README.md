# anticheat-dashboard

![anticheat tests](https://severrir.github.io/AntiCheat-Dashboard/badge.svg)

Server-side anticheat for Roblox, built on my own Framework + Net, plus the staff console that watches it.

Live at https://severrir.github.io/AntiCheat-Dashboard/

- `roblox/` – the game side
- `supabase/` – database, edge functions (game ingest, discord bot, alerts, daily report, global bans)
- `src/` – the dashboard (React + Vite + Tailwind + three.js), deployed to GitHub Pages on every push to `main`

## Install

| From repo | Into Studio |
| --- | --- |
| `roblox/Shared/Framework.lua`, `Net.lua` | `ReplicatedStorage.Shared` |
| `roblox/Server/AntiCheat` | `ServerScriptService.AntiCheat` |
| `roblox/Client/AntiCheatClient` | `StarterPlayerScripts.AntiCheatClient` (LocalScript, modules as children) |

`AntiCheat/Boot.server.lua` adds the services to Framework and starts it, and the client LocalScript does the same with its controllers. If your game already boots Framework itself, delete those two boots and add these to yours before `Framework.Start()`:

```lua
Framework.AddDeep(ServerScriptService.AntiCheat.Services)      -- server
Framework.AddDeep(StarterPlayerScripts.AntiCheatClient.Controllers) -- client
```

## Structure

Built the Framework way: **Services** on the server, **Controllers** on the client, and plain OOP classes for anything with state. Every service is registered as `AC<Name>` so it can't clash with your own services (`Framework.Get("ACCombatService")`).

```
AntiCheat/
  Boot.server.lua      Framework.AddDeep(Services) + Start
  Config.lua           thresholds, feature toggles, admins
  API.lua              the one module your game code needs
  Classes/             PlayerProfile, MovementModel, Check (base class), TrapZone, BaitDummy,
                       BaitCoin, Recording, PlayStyle, SyncBatch, Signal, RingBuffer
  Util/                Scoring, Physics
  Services/
    Core/              PlayerService, TrustService, SchedulerService, EnforcementService
    Checks/            MovementService, CharacterService, TimingService, StatsService,
                       CombatService, ClientCheckService, NetGuardService
    Traps/             HoneypotService, VaultService, BaitNpcService, BaitCoinService
    Intel/             RecorderService, BehaviorService, ThreatService
    Link/              BackendService, PulseService, CommandService, MapExportService
    Response/          BanService, GlobalBanService, IslandService
    Admin/             SpectatorService
AntiCheatClient/       LocalScript: Framework.AddDeep(Controllers) + Start
  Controllers/         HeartbeatController, SpectatorController
  Classes/             SpectatorPanel
```

Every per-player check inherits from `Classes/Check`, so adding your own is small:

```lua
local Check = require(ServerScriptService.AntiCheat.Classes.Check)

local FlingService = Check.extend({
	Name = "ACFlingService",
	Category = "Movement",  -- shows up as Movement on the dashboard
	Feature = "Movement",   -- switched off together with Movement
	Rate = "hot",           -- 10x a second per player, "cold" = every 2s
})

function FlingService:Step(profile, now)
	if profile.root and profile.root.AssemblyAngularVelocity.Magnitude > 200 then
		self:Flag(profile, 15, { kind = "Fling" })
	end
end

return FlingService
```

Drop it anywhere in `Services/` and it's picked up, scheduled, and switchable from the dashboard.

Enable HttpService. The game key is **not** in this repo: in Studio it goes in `AntiCheat/ServerKey` (gitignored), in live servers it's an experience secret named `anticheat_key`.

### Net hook

The anticheat watches every `Net` remote through two optional hooks added to `Net.lua` (fully backwards compatible, nil by default):

- `Net.Middleware(player, name, ...) -> boolean` runs after the cooldown/type checks, return false to drop the call
- `Net.OnReject(player, name, reason)` fires on `"cooldown"` or `"types"` rejects

So your own remotes get flood, bad-argument and macro detection without changing anything.

## How it fits together

```
game server --(sync 20s / pulse 5s)--> edge fn "game" --> postgres --realtime--> dashboard
     ^                                                      |
     |-- MessagingService <-- edge fn "notify" <-- ban trigger (instant global bans)
discord <-- alerts with picture, daily report, /check /ban /unban /replay bot
```

Checks never punish anyone directly. They report to Trust, which keeps a decaying score per player. A kick needs the score past `KickScore` **and** at least two different checks agreeing. Traps (honeypots, vault, bait) count as proof on their own, and movement proves itself by replaying the recorded path. Bans are only ever done by a person.

## Features

Every one of these can be switched on/off live from Settings, no republish.

| | |
| --- | --- |
| Movement | speed, teleport, fly, noclip, super jump, blink. Snaps you back to the last good spot |
| Character | humanoid swap/delete, godmode, root resize, deleted limbs |
| Net guard | spam, bad args and canary values on every Net remote |
| Timing / Statistical | macros, and stats way off the player's own baseline |
| Combat | `ValidateHit` range, cooldown and line of sight |
| Client | heartbeat + local speed/jump/gravity edits |
| Honeypots | fake admin remotes and fake secret values, renamed every server |
| Trap vault | sealed invisible room far away, plus any part named `ACVault`. Only teleporters get in |
| Bait NPC | invisible dummy next to suspects. Only aimbots/kill aura target it |
| Bait coins | coins floating out of reach above the map, plus any part named `ACCoin` |
| 3D replays | last 20s of every kick, watch it on the real map in the browser |
| Mission Control | live radar of every server + cheat heatmap |
| Threat level | per-server calm / watch / alert / under attack |
| Spectator | `/spectate` or F8 in game, or the dashboard button (teleports you into their server) |
| Case files | plain-English explanation of every kick |
| Cheat tools | kicks grouped by fingerprint, one big group = one script going around |
| Alts | new accounts that play like a banned player get flagged (never auto-punished) |
| Global bans | ban reaches every live server in about a second |
| Trust carries over | suspicion follows a player between servers |
| Appeals | public appeal page, shown to staff next to the replay |
| Learning loop | every ban/unban teaches it which checks are noisy |
| What-if | drag the sliders, see who would've been kicked in the last 30 days |
| Cheater Island | **off by default**. Sends cheaters to their own server instead of kicking. Published games only |

## Using it from game code

```lua
local AntiCheat = require(game.ServerScriptService.AntiCheat.API)

-- before a legit teleport, knockback, dash...
AntiCheat.Exempt(player, "Movement", 2)

local Attack = Net.Event({ name = "Attack", cooldown = 0.2 }):Expect("Instance")
Attack:Listen(function(player, target)
	if AntiCheat.ValidateHit(player, target, { Range = 10, Cooldown = 0.5, Weapon = "Sword" }) then
		-- damage
	end
end)

-- swung at nothing, still counts toward accuracy
AntiCheat.RecordMiss(player)

-- feed any stat, it learns what's normal for that player
AntiCheat.RecordStat(player, "CoinsPerMinute", cpm)

AntiCheat.OnKicked(function(player, reason) end)
```

Morphs, scaling or removing limbs on purpose? `AntiCheat.Exempt(player, "Character", 3)` first.

Set WalkSpeed / JumpPower on the server. Movement follows the server's values, so a client-only sprint gets flagged.

If your own NPC or hit detection loops over workspace, skip models where `AntiCheat.IsBait(model)` is true (they're also tagged `ACBait` / `ACInternal`).

## Tests

`roblox/tests/run.luau` plays 200 legit sessions (50 on terrible connections) and 50 cheat sessions through the real movement + scoring code. CI runs it on every push; one false kick fails the deploy. The badge above is the latest result.

Real sessions can be added from the replay viewer: *As legit play* / *As cheat* downloads a test case, drop it in `roblox/tests/recorded/` and add it to `init.luau`.

```
luau roblox/tests/run.luau
```

## Setup checklist

- GitHub → Settings → Pages → Source: **GitHub Actions**
- First Discord login to the dashboard becomes the owner, everyone after is pending until approved
- Settings → My Roblox account (needed for the spectate button)
- Discord bot: set the Interactions Endpoint URL shown in Settings, then install the app to your server
- Open Cloud key (Messaging Service → publish, for this experience) goes in Settings → Keys. It's write-only and never reaches the game or the site
