import { createClient } from '@supabase/supabase-js'

// publishable key is meant to be public. row level security is what actually protects the data
export const supabase = createClient(
  'https://kapvjoemzsdqiealluzl.supabase.co',
  'sb_publishable_2LUd8xlwuO7uvs6l8pwO4Q__-OyVtrr',
  { auth: { flowType: 'pkce', persistSession: true, detectSessionInUrl: true } },
)

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
}

export type Flag = {
  id: number
  user_id: number
  server_id: string
  check_name: string
  severity: number
  score_after: number
  hits: number
  context: Record<string, string | number | boolean>
  created_at: string
}

export type Action = {
  id: number
  user_id: number
  action: 'kick' | 'ban' | 'unban'
  reason: string
  actor: string
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
  created_at: string
}

export type Config = {
  thresholds: Record<string, number>
  version: number
  updated_at: string
  updated_by: string | null
}
