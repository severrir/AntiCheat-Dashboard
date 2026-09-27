import { createClient } from '@supabase/supabase-js'

export const SUPABASE_URL = 'https://kapvjoemzsdqiealluzl.supabase.co'
export async function allPages<T>(
  page: (from: number, to: number) => PromiseLike<{ data: T[] | null }>,
  max: number,
): Promise<T[]> {
  const out: T[] = []
  for (let from = 0; from < max; from += 1000) {
    const { data } = await page(from, Math.min(from + 999, max - 1))
    if (!data?.length) break
    out.push(...data)
    if (data.length < 1000) break
  }
  return out
}

export const supabase = createClient(SUPABASE_URL, 'sb_publishable_2LUd8xlwuO7uvs6l8pwO4Q__-OyVtrr', {
  auth: { flowType: 'pkce', persistSession: true, detectSessionInUrl: true },
})

export type Game = {
  id: number
  name: string
  universe_id: number | null
  discord_guild: string | null
  created_at: string
}

export type Player = {
  game_id: number
  user_id: number
  username: string
  trust_score: number
  peak_score: number
  total_flags: number
  kicks: number
  last_server: string | null
  first_seen: string
  last_seen: string
  fingerprint: number[] | null
  account_age: number | null
  alt_of: number | null
  alt_score: number | null
  on_island: boolean
  shadowed: boolean
  shadow_by: string | null
  shadowed_at: string | null
  reports_against: number
  reports_made: number
  reports_confirmed: number
  reports_dismissed: number
}

export type Flag = {
  id: number
  game_id: number
  user_id: number
  server_id: string
  check_name: string
  severity: number
  raw: number | null
  score_after: number
  hits: number
  context: Record<string, string | number | boolean>
  place_id: number | null
  pos_x: number | null
  pos_y: number | null
  pos_z: number | null
  created_at: string
}

export type Action = {
  id: number
  game_id: number
  user_id: number
  action: 'kick' | 'ban' | 'unban' | 'shadow' | 'unshadow' | 'revert'
  reason: string
  actor: string
  replay_id: number | null
  signature: string[] | null
  created_at: string
}

export type Ban = {
  game_id: number
  user_id: number
  reason: string
  active: boolean
  banned_by: string
  expires_at: string | null
  updated_at: string
  roblox_synced: boolean
}

export type DashUser = {
  user_id: string
  discord_id: string | null
  username: string
  avatar_url: string | null
  role: 'owner' | 'admin' | 'staff' | 'pending'
  roblox_id: number | null
  created_at: string
}

export type Config = {
  game_id: number
  thresholds: Record<string, number>
  features: Record<string, boolean>
  version: number
  updated_at: string
  updated_by: string | null
}

export type Server = {
  server_id: string
  game_id: number
  place_id: number | null
  players: number
  threat: number
  island: boolean
  last_seen: string
}

export type Replay = {
  id: number
  game_id: number
  user_id: number
  server_id: string | null
  place_id: number | null
  map_version: string | null
  kind: 'kick' | 'capture' | 'session'
  reason: string
  meta: Record<string, string | number | boolean>
  samples: [number, number, number, number, number, number, number][]
  events: [number, string, string, string?][]
  rig: Rig | null
  poses: number[][] | null
  created_at: string
}

export type RigPart = { n: string; s: [number, number, number]; r: number[]; c: number }
export type RigAccessory = { l: string; s: [number, number, number]; o: number[]; c: number; t: number | null; w: boolean }
export type Rig = {
  type: 'R15' | 'R6'
  hip: number
  root: [number, number, number]
  parts: RigPart[]
  clothes?: { shirt: number | null; pants: number | null; tshirt: number | null; face: number | null }
  acc?: RigAccessory[]
}

export type Sky = {
  clock: number
  ambient: number | null
  fog: number | null
  fogEnd: number | null
  brightness: number | null
  haze: number | null
  density: number | null
  sun: [number, number, number] | null
}

export type Terrain = {
  x0: number
  z0: number
  step: number
  cols: number
  rows: number
  palette: Record<string, number>
  water: number
  h: number[]
  w: number[]
  m: number[]
}

export type Appeal = {
  id: number
  game_id: number
  user_id: number
  username: string
  message: string
  discord_name: string
  status: 'open' | 'approved' | 'denied'
  note: string
  decided_by: string | null
  decided_at: string | null
  created_at: string
}

export type Report = {
  id: number
  game_id: number
  target_id: number
  reporter_id: number
  reason: string
  note: string
  weight: number
  server_id: string | null
  replay_id: number | null
  target_score: number | null
  status: 'open' | 'confirmed' | 'dismissed'
  decided_by: string | null
  decided_at: string | null
  created_at: string
}

export type Revert = {
  id: number
  game_id: number
  user_id: number
  since: string
  summary: {
    currency?: Record<string, number>
    items?: Record<string, number>
    kills?: number
    victims?: Record<string, { kills?: number; currency?: Record<string, number>; items?: Record<string, number> }>
  }
  status: 'pending' | 'sent' | 'done' | 'failed' | 'empty'
  result: string | null
  created_by: string
  created_at: string
  done_at: string | null
}

export type GameStaff = { game_id: number; user_id: string }

export type MapPart = number[]

export async function loadMap(placeId: number | null, version?: string | null) {
  if (!placeId) return null
  let q = supabase.from('maps').select('place_id, version, total, received, bounds, sky, terrain').eq('place_id', placeId)
  q = version ? q.eq('version', version) : q.order('created_at', { ascending: false })
  const { data: maps } = await q.limit(1)
  const map = maps?.[0]
  if (!map) return null
  const [{ data: chunks }, { data: rows }] = await Promise.all([
    supabase.from('map_chunks').select('parts').eq('place_id', placeId).eq('version', map.version).order('idx'),
    map.terrain
      ? supabase.from('map_terrain').select('start, data').eq('place_id', placeId).eq('version', map.version).order('idx')
      : Promise.resolve({ data: [] as { start: number; data: { h: number[]; w: number[]; m: number[] } }[] }),
  ])

  let terrain: Terrain | null = null
  if (map.terrain && rows && rows.length > 0) {
    const meta = map.terrain as Omit<Terrain, 'h' | 'w' | 'm'>
    const n = meta.cols * meta.rows
    const h = new Array<number>(n).fill(-99999), w = new Array<number>(n).fill(-99999), m = new Array<number>(n).fill(0)
    for (const row of rows) {
      const d = row.data as { h: number[]; w: number[]; m: number[] }
      for (let i = 0; i < d.h.length && row.start + i < n; i++) {
        h[row.start + i] = d.h[i]
        w[row.start + i] = d.w[i] ?? -99999
        m[row.start + i] = d.m[i] ?? 0
      }
    }
    terrain = { ...meta, h, w, m }
  }

  return {
    version: map.version as string,
    bounds: map.bounds as number[] | null,
    sky: (map.sky as Sky | null) ?? null,
    terrain,
    parts: (chunks ?? []).flatMap((c) => c.parts as MapPart[]),
  }
}

export type MapData = NonNullable<Awaited<ReturnType<typeof loadMap>>>
