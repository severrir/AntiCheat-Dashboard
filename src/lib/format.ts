export function ago(iso: string) {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 10) return 'just now'
  if (s < 60) return `${Math.floor(s)}s ago`
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  return `${Math.floor(s / 86400)}d ago`
}

// servers sync every 20s, so anyone seen in the last minute is still in game
export function isOnline(iso: string) {
  return Date.now() - new Date(iso).getTime() < 60_000
}

export function scoreTone(score: number, kick: number) {
  if (score >= kick) return 'text-bad'
  if (score >= kick * 0.5) return 'text-warn'
  if (score > 0.5) return 'text-accent'
  return 'text-muted'
}

export const CHECK_COLORS: Record<string, string> = {
  Movement: '#22d3ee',
  Character: '#a78bfa',
  Remote: '#fbbf24',
  Statistical: '#34d399',
  Timing: '#fb923c',
  Honeypot: '#f43f5e',
  Client: '#60a5fa',
  Combat: '#f472b6',
  Custom: '#94a3b8',
}

export const robloxProfile = (id: number) => `https://www.roblox.com/users/${encodeURIComponent(String(id))}/profile`

export function errorText(e: unknown) {
  if (e && typeof e === 'object' && 'message' in e) return String((e as { message: unknown }).message)
  return 'Something went wrong'
}
