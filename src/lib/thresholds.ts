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
