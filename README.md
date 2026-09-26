# anticheat-dashboard

![anticheat tests](https://severrir.github.io/AntiCheat-Dashboard/badge.svg)

Server-side anticheat for Roblox, plus a web dashboard for staff. Built on my own Framework + Net.

Dashboard: https://severrir.github.io/AntiCheat-Dashboard/

Everything that matters runs on the server, so an exploiter can't just delete a LocalScript and walk around it. The server keeps its own idea of where each player should be and what they can do, and compares.

- `roblox/` game side
- `supabase/` database + edge functions (game sync, Discord bot, alerts, daily report)
- `src/` dashboard (React, Vite, Tailwind, three.js), deployed to Pages on push

## What it does

**Catches**
- speed, teleport, fly, noclip, super jump. You get pulled back to your last valid spot
- humanoid swaps, godmode, hitbox resizing, deleted limbs
- remote spam, bad arguments and macros on every Net remote
- hits from too far, too fast or through walls (`ValidateHit`)
- client-side WalkSpeed/JumpPower/gravity edits, and the client script being disabled

**Traps** (things only a cheater can touch)
- fake admin remotes and values, renamed every server
- a sealed room far off the map that you can only reach by teleporting
- an invisible dummy only aimbots and kill aura go for
- coins floating out of reach

**When someone gets caught**
- nothing kicks on its own. Every check adds to a score that decays over time, and a kick needs the score over the limit *and* two different checks agreeing. Traps count as proof by themselves
- past a lower score they go into shadow mode first: still playing, but their hits do nothing and their earnings are held
- the last 20 seconds get saved as a 3D replay: their real avatar and clothes, animated limb by limb, on a copy of the map. You can orbit around it and save it as a video
- bans are always done by a person, from the dashboard or Discord, and reach every server in about a second
- a ban can undo what they gained (coins, items, kills) and pay back the people they took it from

**Dashboard**
- live map of every server, heatmap of where cheats happen
- player pages with flags, replays, reports, shadow and undo buttons
- spectate button that drops you invisibly into their server (`/spectate` or F8 in game works too)
- kicks grouped by fingerprint, so one script going around shows up as one big group
- new accounts that play like a banned player get flagged as possible alts (never punished automatically)
- player reports from in game, weighted by how often the reporter was right before
- appeals page for banned players
- tuning: test new thresholds against the last 30 days of flags before applying them
- several games on one dashboard, each with its own key, staff and Discord
- Discord bot: `/check /ban /unban /replay /shadow`, kick alerts, daily report

Every feature can be turned off live from Settings. There's also Cheater Island, off by default, which sends cheaters to their own server instead of kicking them.

## Install

| From repo | Into Studio |
| --- | --- |
| `roblox/Shared/Framework.lua`, `Net.lua` | `ReplicatedStorage.Shared` |
| `roblox/Server/AntiCheat` | `ServerScriptService.AntiCheat` |
| `roblox/Client/AntiCheatClient` | `StarterPlayerScripts.AntiCheatClient` (LocalScript, modules as children) |

Turn on HttpService. The game key isn't in this repo: in Studio it goes in `AntiCheat/Settings/ServerKey` (gitignored), live it's an experience secret called `anticheat_key`.

If your game already boots Framework, delete the two Boot scripts and add these before `Framework.Start()`:

```lua
Framework.AddDeep(ServerScriptService.AntiCheat.Services)
Framework.AddDeep(StarterPlayerScripts.AntiCheatClient.Controllers)
```

## Layout

Services on the server, Controllers on the client, OOP classes for anything with state. Services are named `AC<Name>` so they don't clash with yours.

```
AntiCheat/
  Boot, API
  Settings/     Config, ServerKey
  Classes/
    Core/       Check, Signal, RingBuffer, SyncBatch
    Player/     PlayerProfile, MovementModel, PlayStyle, Recording, Rig
    Traps/      TrapZone, BaitDummy, BaitCoin
  Util/         Scoring, Physics
  Services/
    Core/       Player, Trust, Scheduler, Enforcement
    Checks/     Movement, Character, Timing, Stats, Combat, ClientCheck, NetGuard
    Traps/      Honeypot, Vault, BaitNpc, BaitCoin
    Intel/      Recorder, Behavior, Threat
    Response/   Ban, GlobalBan, Island, Shadow
    Economy/    Ledger, Revert
    Community/  Report
    Link/       Backend, Pulse, Command, MapExport
    Admin/      Spectator
```

Adding a check:

```lua
local Check = require(ServerScriptService.AntiCheat.Classes.Core.Check)

local FlingService = Check.extend({
	Name = "ACFlingService",
	Category = "Movement",
	Feature = "Movement",
	Rate = "hot",
})

function FlingService:Step(profile, now)
	if profile.root and profile.root.AssemblyAngularVelocity.Magnitude > 200 then
		self:Flag(profile, 15, { kind = "Fling" })
	end
end

return FlingService
```

Put it anywhere in `Services/`. `Rate = "hot"` runs it 10 times a second per player, `"cold"` every 2 seconds.

Net has two optional hooks the anticheat uses to watch every remote: `Net.Middleware(player, name, ...)` (return false to drop the call) and `Net.OnReject(player, name, reason)`. They're nil by default.

## Game code

```lua
local AntiCheat = require(game.ServerScriptService.AntiCheat.API)

AntiCheat.Exempt(player, "Movement", 2) -- before your own teleports, dashes, knockback

Attack:Listen(function(player, target)
	if AntiCheat.ValidateHit(player, target, { Range = 10, Cooldown = 0.5, Weapon = "Sword" }) then
		-- damage
	end
end)

AntiCheat.RecordMiss(player)
AntiCheat.RecordStat(player, "CoinsPerMinute", cpm)
AntiCheat.OnKicked(function(player, reason) end)

data.Coins += AntiCheat.Grant(player, "Coins", 100, "quest") -- 0 while shadowed
if AntiCheat.GrantItem(player, "Golden Sword", "shop") then giveSword(player) end
AntiCheat.RecordKill(killer, victim)
AntiCheat.Transfer(seller, buyer, "Gem", nil)

AntiCheat.OnRevert(function(userId, summary)
	-- summary.currency, summary.items, summary.kills, summary.victims
	return pcall(function()
		store:UpdateAsync(userId, function(d)
			d.Coins = math.max(0, d.Coins - (summary.currency.Coins or 0))
			return d
		end)
	end)
end)
```

Also: `GetScore`, `Flag`, `OnFlagged`, `IsShadowed`, `Shadow`, `Report`, `IsBait`.

Notes:
- games that only use `leaderstats` don't need `Grant`, increases there are recorded automatically
- set WalkSpeed/JumpPower on the server, movement follows the server's values
- exempt `"Character"` before morphs or scaling
- your own NPC or hit loops should skip models where `AntiCheat.IsBait(model)` is true
- own report UI? `Config.ReportButton = false` and call `AntiCheat.Report(reporter, target, reason, note)`

## Tests

`roblox/tests/run.luau` plays 200 legit sessions (50 of them on bad connections) and 50 cheat sessions through the real movement and scoring code. CI runs it on every push and one false kick fails the deploy.

```
luau roblox/tests/run.luau
```

Real sessions can be added from the replay page (*As legit play* / *As cheat*), drop the file in `roblox/tests/recorded/`.

`roblox/tests/StudioTestKit.server.lua` adds Studio-only chat commands for trying things by hand: `/acstate /acshadow /acunshadow /acgrant /accoins /achit /acreport /acreplay`.

## Setup

- GitHub Pages source: GitHub Actions
- the first Discord login becomes the owner, everyone after waits for approval
- link your Roblox account in Settings (for the spectate button)
- Discord bot: paste the Interactions Endpoint URL from Settings, then add the app to your server
- Open Cloud key (Messaging Service publish) goes in Settings → Keys. It's write-only
- more games: Settings → Add another game. The key is shown once, put it in that game's `anticheat_key` secret
