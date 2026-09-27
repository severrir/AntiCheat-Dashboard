import { useCallback, useEffect, useRef, useState } from 'react'
import {
  supabase,
  type Appeal,
  type Ban,
  type Config,
  type DashUser,
  type Flag,
  type GameStaff,
  type Player,
  type Report,
  type Server,
} from './supabase'

const FEED_LIMIT = 300

export type Counts = { flags24: number; kicks24: number }

export function useConsole(enabled: boolean, game: number) {
  const [players, setPlayers] = useState<Player[]>([])
  const [flags, setFlags] = useState<Flag[]>([])
  const [bans, setBans] = useState<Ban[]>([])
  const [config, setConfig] = useState<Config | null>(null)
  const [users, setUsers] = useState<DashUser[]>([])
  const [staff, setStaff] = useState<GameStaff[]>([])
  const [servers, setServers] = useState<Server[]>([])
  const [appeals, setAppeals] = useState<Appeal[]>([])
  const [reports, setReports] = useState<Report[]>([])
  const [counts, setCounts] = useState<Counts>({ flags24: 0, kicks24: 0 })
  const [loadedFor, setLoadedFor] = useState(0)
  const [live, setLive] = useState(false)
  const [fresh] = useState(() => new Set<number>())
  const current = useRef(game)

  const loadCounts = useCallback(async () => {
    if (!game) return
    const since = new Date(Date.now() - 86_400_000).toISOString()
    const [f, k] = await Promise.all([
      supabase.from('flags').select('id', { count: 'exact', head: true }).eq('game_id', game).gte('created_at', since),
      supabase.from('actions').select('id', { count: 'exact', head: true }).eq('game_id', game).eq('action', 'kick').gte('created_at', since),
    ])
    if (current.current !== game) return
    setCounts({ flags24: f.count ?? 0, kicks24: k.count ?? 0 })
  }, [game])

  const reload = useCallback(async () => {
    if (!game) return
    const [p, f, b, c, u, st, s, a, r] = await Promise.all([
      supabase.from('players').select('*').eq('game_id', game).order('last_seen', { ascending: false }).limit(500),
      supabase.from('flags').select('*').eq('game_id', game).order('created_at', { ascending: false }).limit(FEED_LIMIT),
      supabase.from('bans').select('*').eq('game_id', game).order('updated_at', { ascending: false }).limit(500),
      supabase.from('config').select('game_id,thresholds,features,version,updated_at,updated_by').eq('game_id', game).maybeSingle(),
      supabase.from('dashboard_users').select('*').order('created_at'),
      supabase.from('game_staff').select('game_id,user_id'),
      supabase.from('servers').select('*').eq('game_id', game).order('last_seen', { ascending: false }),
      supabase.from('appeals').select('*').eq('game_id', game).order('created_at', { ascending: false }).limit(200),
      supabase.from('reports').select('*').eq('game_id', game).order('created_at', { ascending: false }).limit(400),
    ])
    if (current.current !== game) return
    setPlayers(p.data ?? [])
    setFlags(f.data ?? [])
    setBans(b.data ?? [])
    setConfig(c.data ?? null)
    if (u.data) setUsers(u.data)
    if (st.data) setStaff(st.data)
    setServers(s.data ?? [])
    setAppeals(a.data ?? [])
    setReports(r.data ?? [])
    await loadCounts()
    if (current.current === game) setLoadedFor(game)
  }, [game, loadCounts])

  useEffect(() => {
    if (!enabled || !game) return
    current.current = game
    fresh.clear()
    reload()

    const upsert = <T,>(key: keyof T) => (setter: React.Dispatch<React.SetStateAction<T[]>>) => (row: T) =>
      setter((prev) => [row, ...prev.filter((x) => x[key] !== row[key])])
    const filter = `game_id=eq.${game}`

    const channel = supabase
      .channel(`console:${game}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'flags', filter }, (msg) => {
        const flag = msg.new as Flag
        fresh.add(flag.id)
        setFlags((prev) => [flag, ...prev].slice(0, FEED_LIMIT))
        setCounts((c) => ({ ...c, flags24: c.flags24 + 1 }))
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter }, (msg) => {
        const row = msg.new as Player
        if (row?.user_id) upsert<Player>('user_id')(setPlayers)(row)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'bans', filter }, (msg) => {
        const row = msg.new as Ban
        if (row?.user_id) upsert<Ban>('user_id')(setBans)(row)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'servers', filter }, (msg) => {
        if (msg.eventType === 'DELETE') {
          const old = msg.old as Partial<Server>
          setServers((prev) => prev.filter((s) => s.server_id !== old.server_id))
          return
        }
        const row = msg.new as Server
        if (row?.server_id) upsert<Server>('server_id')(setServers)(row)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appeals', filter }, (msg) => {
        const row = msg.new as Appeal
        if (row?.id) upsert<Appeal>('id')(setAppeals)(row)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'reports', filter }, (msg) => {
        const row = msg.new as Report
        if (row?.id) upsert<Report>('id')(setReports)(row)
      })
      .subscribe((status) => setLive(status === 'SUBSCRIBED'))

    const timer = setInterval(loadCounts, 60_000)
    return () => {
      clearInterval(timer)
      supabase.removeChannel(channel)
    }
  }, [enabled, game, reload, loadCounts, fresh])

  return {
    players, flags, bans, config, users, staff, servers, appeals, reports, counts, loading: loadedFor !== game, live, reload,
    fresh,
  }
}

