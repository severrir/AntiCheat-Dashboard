// turns replay events into sentences anyone can read. shared by the dashboard and the edge functions

export type ReplayEvent = [number, string, string, string?] // [t, check, kind, detail]
export type Sample = [number, number, number, number, number, number, number] // [t, x, y, z, yaw, snapped, grounded]

export type CaseInput = {
  name: string
  events: ReplayEvent[]
  samples?: Sample[]
  score?: number
  kickScore?: number
  walkSpeed?: number
  kind?: string
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

function remoteName(kind: string) {
  const i = kind.indexOf(':')
  return i >= 0 ? kind.slice(i + 1) : kind
}

// top speed seen in the path, studs per second
function topSpeed(samples: Sample[] = []) {
  let best = 0
  for (let i = 1; i < samples.length; i++) {
    const [t0, x0, , z0] = samples[i - 1]
    const [t1, x1, , z1, , snapped] = samples[i]
    const dt = t1 - t0
    if (dt <= 0 || snapped) continue
    best = Math.max(best, Math.hypot(x1 - x0, z1 - z0) / dt)
  }
  return best
}

export function caseFile(input: CaseInput) {
  const counts = new Map<string, number>()
  const details = new Map<string, string>()
  for (const [, check, kind, detail] of input.events) {
    const key = `${check}:${kind}`
    counts.set(key, (counts.get(key) ?? 0) + 1)
    if (detail) details.set(key, detail)
  }
  const snaps = (input.samples ?? []).filter((s) => s[5] === 1).length
  const walk = input.walkSpeed ?? 16
  const lines: string[] = []

  const has = (prefix: string) => [...counts.keys()].some((k) => k.startsWith(prefix))
  const n = (key: string) => counts.get(key) ?? 0

  if (has('Movement:Speed') || has('Movement:Teleport') || has('Movement:Blink')) {
    const top = topSpeed(input.samples)
    const mult = details.get('Movement:Speed')?.replace('x', '')
    const bits: string[] = []
    if (has('Movement:Speed')) {
      bits.push(
        mult
          ? `ran about ${mult}× faster than their walk speed allows`
          : `ran faster than their walk speed allows`,
      )
    }
    if (has('Movement:Blink')) bits.push('moved in sudden bursts over and over (a "blink" speed hack)')
    if (has('Movement:Teleport')) bits.push(`teleported ${plural(n('Movement:Teleport'), 'time')}`)
    let line = `${capital(bits.join(', then '))}.`
    if (top > 0) line += ` Top speed ${Math.round(top)} studs/s, a normal player tops out around ${Math.round(walk * 1.35 + 4)}.`
    lines.push(line)
  }
  if (has('Movement:Fly')) lines.push(`Hovered in the air for more than 2.5 seconds without falling, ${plural(n('Movement:Fly'), 'time')}.`)
  if (has('Movement:SuperJump')) lines.push('Launched upward far faster than any normal jump.')
  if (has('Movement:Noclip')) lines.push(`Walked straight through a solid wall${n('Movement:Noclip') > 1 ? `, ${plural(n('Movement:Noclip'), 'time')}` : ''}.`)
  if (snaps > 0) lines.push(`The anticheat pulled them back to their last legit spot ${plural(snaps, 'time')}.`)

  for (const key of counts.keys()) {
    if (!key.startsWith('Honeypot:')) continue
    const kind = key.slice('Honeypot:'.length)
    if (kind === 'Canary') lines.push('Sent back a fake admin key that only an exploit tool could have read.')
    else if (kind.startsWith('Remote') || kind.startsWith('Function'))
      lines.push(`Fired a fake "${remoteName(kind)}" remote. Nothing in the game uses it, it only exists to catch exploit tools.`)
    else if (kind === 'TrapVault') lines.push('Showed up inside the sealed trap room, which can only be reached by teleporting or noclipping.')
    else if (kind.startsWith('BaitNPC')) lines.push('Attacked an invisible bait player that no human can see, a sign of kill aura or aimbot.')
    else if (kind === 'BaitCoin') lines.push('Grabbed a bait coin floating far above the map, out of any normal player\'s reach.')
  }

  const ws = details.get('Client:LocalWalkSpeed')
  if (has('Client:LocalWalkSpeed')) lines.push(`Their own game client had WalkSpeed set to ${ws ? ws.replace('=', '') : 'a higher value'}, the server never allowed that.`)
  if (has('Client:LocalJump')) lines.push('Their client had jump power set higher than the server allows.')
  if (has('Client:LocalGravity')) lines.push('Their client lowered gravity for themselves.')
  if (has('Client:NoHeartbeat')) lines.push('The anticheat script on their client stopped responding, it was likely disabled.')
  if (has('Character:Godmode') || has('Character:HumanoidSwap')) lines.push('Tampered with their character to become unkillable.')
  if (has('Character:RootResized')) lines.push('Resized their character\'s hitbox.')
  if (has('Timing:Macro')) lines.push(`Fired ${details.get('Timing:Macro') ?? 'a remote'} with a perfectly even rhythm, the way a macro does and a human can't.`)
  if (has('Remote:Spam')) lines.push('Spammed the server with far more requests than the game allows.')
  if (has('Remote:BadArgs')) lines.push('Sent the server malformed requests, typical of an exploit tool poking at remotes.')
  if (has('Combat:Range')) lines.push('Hit people from further away than their weapon reaches.')
  if (has('Combat:ThroughWall')) lines.push('Hit people through walls.')
  if (has('Combat:Cooldown')) lines.push('Attacked faster than the weapon\'s cooldown allows.')
  if (has('Statistical:Accuracy')) lines.push('Landed a suspiciously perfect share of their hits.')

  if (lines.length === 0) lines.push('Nothing unusual in this recording.')

  const verdict =
    input.kind === 'kick'
      ? `Kicked automatically${input.score ? ` at score ${Math.round(input.score)}` : ''}${input.kickScore ? ` (limit ${Math.round(input.kickScore)})` : ''}.`
      : input.kind === 'session'
        ? 'Recorded by an admin as a normal play sample.'
        : 'Captured for review.'

  return { title: `${input.name}: case file`, lines, verdict }
}

function capital(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1)
}
