import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase, type Ban, type Config, type DashUser, type Flag, type Player } from './supabase'

const FEED_LIMIT = 300

export type Counts = { flags24: number; kicks24: number }

// one place that loads everything and keeps it live through realtime
export function useConsole(enabled: boolean) {
  const [players, setPlayers] = useState<Player[]>([])
  const [flags, setFlags] = useState<Flag[]>([])
  const [bans, setBans] = useState<Ban[]>([])
  const [config, setConfig] = useState<Config | null>(null)
  const [users, setUsers] = useState<DashUser[]>([])
  const [counts, setCounts] = useState<Counts>({ flags24: 0, kicks24: 0 })
  const [loading, setLoading] = useState(true)
  const [live, setLive] = useState(false)
  const fresh = useRef(new Set<number>())

  const loadCounts = useCallback(async () => {
    const since = new Date(Date.now() - 86_400_000).toISOString()
    const [f, k] = await Promise.all([
      supabase.from('flags').select('id', { count: 'exact', head: true }).gte('created_at', since),
      supabase.from('actions').select('id', { count: 'exact', head: true }).eq('action', 'kick').gte('created_at', since),
    ])
    setCounts({ flags24: f.count ?? 0, kicks24: k.count ?? 0 })
  }, [])

  const reload = useCallback(async () => {
    const [p, f, b, c, u] = await Promise.all([
      supabase.from('players').select('*').order('last_seen', { ascending: false }).limit(500),
      supabase.from('flags').select('*').order('created_at', { ascending: false }).limit(FEED_LIMIT),
      supabase.from('bans').select('*').order('updated_at', { ascending: false }).limit(500),
      supabase.from('config').select('thresholds,version,updated_at,updated_by').eq('id', 1).maybeSingle(),
      supabase.from('dashboard_users').select('*').order('created_at'),
    ])
    if (p.data) setPlayers(p.data)
    if (f.data) setFlags(f.data)
    if (b.data) setBans(b.data)
    if (c.data) setConfig(c.data)
    if (u.data) setUsers(u.data)
    await loadCounts()
    setLoading(false)
  }, [loadCounts])

  useEffect(() => {
    if (!enabled) return
    reload()

    const channel = supabase
      .channel('console')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'flags' }, (msg) => {
        const flag = msg.new as Flag
        fresh.current.add(flag.id)
        setFlags((prev) => [flag, ...prev].slice(0, FEED_LIMIT))
        setCounts((c) => ({ ...c, flags24: c.flags24 + 1 }))
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players' }, (msg) => {
        const row = msg.new as Player
        if (!row?.user_id) return
        setPlayers((prev) => {
          const rest = prev.filter((p) => p.user_id !== row.user_id)
          return [row, ...rest]
        })
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'bans' }, (msg) => {
        const row = msg.new as Ban
        if (!row?.user_id) return
        setBans((prev) => [row, ...prev.filter((b) => b.user_id !== row.user_id)])
      })
      .subscribe((status) => setLive(status === 'SUBSCRIBED'))

    // counts and anything realtime missed, every so often
    const timer = setInterval(loadCounts, 60_000)
    return () => {
      clearInterval(timer)
      supabase.removeChannel(channel)
    }
  }, [enabled, reload, loadCounts])

  return { players, flags, bans, config, users, counts, loading, live, reload, fresh: fresh.current }
}
