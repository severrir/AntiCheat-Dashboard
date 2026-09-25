// same defaults as Config.lua in the game. keep these two in sync
export type Field = { key: string; label: string; hint: string; step: number; def: number }

export const GROUPS: { title: string; fields: Field[] }[] = [
  {
    title: 'Scoring',
    fields: [
      { key: 'KickScore', label: 'Kick score', hint: 'Score needed before a kick', step: 5, def: 100 },
      { key: 'HalfLife', label: 'Half-life (s)', hint: 'How fast suspicion fades', step: 5, def: 45 },
      { key: 'MinCorroboratingChecks', label: 'Checks that must agree', hint: 'Honeypots skip this', step: 1, def: 2 },
    ],
  },
  {
    title: 'Movement',
    fields: [
      { key: 'SpeedMargin', label: 'Speed margin', hint: 'Multiplier on WalkSpeed', step: 0.05, def: 1.35 },
      { key: 'TeleportDistance', label: 'Teleport distance', hint: 'Studs in one step', step: 5, def: 45 },
      { key: 'FlyTime', label: 'Fly time (s)', hint: 'Airborne without falling', step: 0.5, def: 2.5 },
      { key: 'FlyHeight', label: 'Fly height', hint: 'Studs above ground', step: 1, def: 12 },
    ],
  },
  {
    title: 'Network & behaviour',
    fields: [
      { key: 'RemoteBurstMultiplier', label: 'Remote burst x', hint: 'Dropped calls before flagging', step: 0.5, def: 2 },
      { key: 'HeartbeatTimeout', label: 'Heartbeat timeout (s)', hint: 'Client detector silence', step: 5, def: 25 },
      { key: 'TimingMinCV', label: 'Timing min CV', hint: 'Lower = only perfect macros', step: 0.005, def: 0.035 },
      { key: 'AccuracyCap', label: 'Accuracy cap', hint: 'Hit ratio over 30 shots', step: 0.01, def: 0.92 },
    ],
  },
  {
    title: 'Check weights',
    fields: ['Movement', 'Character', 'Remote', 'Statistical', 'Timing', 'Honeypot', 'Client', 'Combat'].map((c) => ({
      key: `Weight${c}`,
      label: c,
      hint: '0 turns it off',
      step: 0.1,
      def: 1,
    })),
  },
]

export const DEFAULTS: Record<string, number> = Object.fromEntries(
  GROUPS.flatMap((g) => g.fields.map((f) => [f.key, f.def])),
)

// every feature can be flipped live. same list and defaults as Config.Features in the game
export const FEATURES: { key: string; label: string; hint: string; def: boolean }[] = [
  { key: 'Movement', label: 'Movement check', hint: 'speed, teleport, fly, noclip, super jump, blink', def: true },
  { key: 'Character', label: 'Character check', hint: 'godmode, humanoid swaps, hitbox resize', def: true },
  { key: 'NetGuard', label: 'Net guard', hint: 'watches every Net remote for spam and bad args', def: true },
  { key: 'Timing', label: 'Macro detection', hint: 'remotes fired at inhumanly even rhythm', def: true },
  { key: 'Statistical', label: 'Player baselines', hint: 'accuracy and custom stats vs their own history', def: true },
  { key: 'Combat', label: 'Hit validation', hint: 'range, cooldown, line of sight', def: true },
  { key: 'Client', label: 'Client detector', hint: 'heartbeat + local speed/jump/gravity edits', def: true },
  { key: 'Honeypot', label: 'Honeypot remotes', hint: 'fake admin remotes and fake secret keys', def: true },
  { key: 'TrapVault', label: 'Trap vault', hint: 'sealed room only teleporters can reach', def: true },
  { key: 'BaitNPC', label: 'Bait NPC', hint: 'invisible dummies next to suspects', def: true },
  { key: 'BaitCoin', label: 'Bait coins', hint: 'coins floating out of reach above the map', def: true },
  { key: 'Replays', label: '3D replays', hint: 'record the last 20s when someone is kicked', def: true },
  { key: 'MapExport', label: 'Map export', hint: 'send the map so replays have a world', def: true },
  { key: 'MissionControl', label: 'Mission Control', hint: 'live player positions every 5s', def: true },
  { key: 'Spectator', label: 'Spectator mode', hint: 'invisible admin spectating in game', def: true },
  { key: 'AltDetection', label: 'Alt detection', hint: 'flag new accounts that play like banned ones', def: true },
  { key: 'GlobalBans', label: 'Instant global bans', hint: 'push bans to every server in about a second', def: true },
  { key: 'CrossServerTrust', label: 'Trust follows players', hint: 'suspicion carries over between servers', def: true },
  { key: 'CheaterIsland', label: 'Cheater Island', hint: 'send cheaters to their own server instead of kicking', def: false },
]

export const FEATURE_DEFAULTS: Record<string, boolean> = Object.fromEntries(FEATURES.map((f) => [f.key, f.def]))
