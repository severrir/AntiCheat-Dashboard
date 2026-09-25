import { createClient } from '@supabase/supabase-js'

// publishable key is meant to be public. row level security is what actually protects the data
export const SUPABASE_URL = 'https://kapvjoemzsdqiealluzl.supabase.co'
export const supabase = createClient(SUPABASE_URL, 'sb_publishable_2LUd8xlwuO7uvs6l8pwO4Q__-OyVtrr', {
  auth: { flowType: 'pkce', persistSession: true, detectSessionInUrl: true },
})

export type Player = {
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
}

export type Flag = {
  id: number
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
  user_id: number
  action: 'kick' | 'ban' | 'unban'
  reason: string
  actor: string
  replay_id: number | null
  signature: string[] | null
  created_at: string
}

export type Ban = {
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
  role: 'owner' | 'admin' | 'pending'
  roblox_id: number | null
  created_at: string
}

export type Config = {
  thresholds: Record<string, number>
  features: Record<string, boolean>
  version: number
  updated_at: string
  updated_by: string | null
}

export type Server = {
  server_id: string
  place_id: number | null
  players: number
  threat: number
  island: boolean
  last_seen: string
}

export type Replay = {
  id: number
  user_id: number
  server_id: string | null
  place_id: number | null
  map_version: string | null
  kind: 'kick' | 'capture' | 'session'
  reason: string
  meta: Record<string, string | number | boolean>
  samples: [number, number, number, number, number, number, number][]
  events: [number, string, string, string?][]
  created_at: string
}

export type Appeal = {
  id: number
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

// [x, y, z, sx, sy, sz, rx, ry, rz, color, shape]
export type MapPart = number[]

export async function loadMap(placeId: number | null, version?: string | null) {
  if (!placeId) return null
  let q = supabase.from('maps').select('place_id, version, total, received, bounds').eq('place_id', placeId)
  q = version ? q.eq('version', version) : q.order('created_at', { ascending: false })
  const { data: maps } = await q.limit(1)
  const map = maps?.[0]
  if (!map) return null
  const { data: chunks } = await supabase
    .from('map_chunks')
    .select('parts')
    .eq('place_id', placeId)
    .eq('version', map.version)
    .order('idx')
  return {
    version: map.version as string,
    bounds: map.bounds as number[] | null,
    parts: (chunks ?? []).flatMap((c) => c.parts as MapPart[]),
  }
}
