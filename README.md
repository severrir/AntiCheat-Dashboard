# anticheat-dashboard

Server-side anticheat for Roblox plus the staff console that watches it.

- `roblox/` – the game side. Drop `AntiCheat` into ServerScriptService and `Client/InputHandler` into StarterPlayerScripts.
- `supabase/` – the ingest function the game servers talk to.
- `src/` – the dashboard (React + Vite + Tailwind), deployed to GitHub Pages on every push to `main`.

Live at https://severrir.github.io/anticheat-dashboard/

## How it fits together

```
game server --(every 20s, x-game-key)--> edge function "game" --> postgres
                                                                    |
dashboard (discord login, RLS) <------ realtime --------------------+
```

Checks never punish anyone directly. They report to `TrustService`, which keeps a decaying score per player. When the score passes `KickScore` and at least two different checks agree (honeypots count as proof on their own), forensic replay double checks movement flags against the recorded path, then the player gets kicked. Bans are only ever done by a person from the dashboard.

## Checks

| Check | What it catches |
| --- | --- |
| Movement | speed, teleport, fly, noclip. Snaps you back to the last good spot |
| Character | humanoid swap/delete, godmode, root resize, deleted limbs |
| Remote | rate limits + argument validation for remotes made with `AntiCheat.Remote.new` |
| Timing | remotes fired with inhumanly even gaps (macros) |
| Statistical | per-player baselines for any stat you feed it, plus accuracy |
| Honeypot | fake remotes / fake secret values, renamed every server |
| Client | heartbeat from the client script, local speed/jump/gravity edits |
| Combat | `ValidateHit` range, cooldown and line of sight |

## Using it from game code

```lua
local AntiCheat = require(game.ServerScriptService.AntiCheat.API)

-- before a legit teleport, knockback, dash...
AntiCheat.Exempt(player, "Movement", 2)

local attack = AntiCheat.Remote.new("Attack", { Args = { "Instance:Model", "Vector3?" }, Rate = 8 })
attack:Connect(function(player, target, dir)
	if AntiCheat.Combat.ValidateHit(player, target, { Range = 10, Cooldown = 0.5, Weapon = "Sword" }) then
		-- damage
	else
		AntiCheat.Combat.RecordMiss(player)
	end
end)
```

Set WalkSpeed / JumpPower on the server. The movement check reads the server's values, so a sprint that only changes speed on the client will get flagged.

## Setup notes

- The game key is **not** in this repo. In Studio it lives in `ServerScriptService.AntiCheat.ServerKey`. For live servers, add it as an experience secret named `anticheat_key` (Creator Hub → your experience → Secrets) and delete the module.
- HttpService must be enabled.
- Thresholds are tuned live from Settings in the dashboard, no republish needed.
