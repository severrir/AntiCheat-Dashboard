import { lazy, Suspense, useCallback, useEffect, useMemo, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, type DashUser, type Game } from './lib/supabase'
import { useConsole } from './lib/useConsole'
import { GameContext, savedGame, saveGame } from './lib/game'
import { DEFAULTS } from './lib/thresholds'
import { Button, Dot } from './components/ui'
import { PlayerDrawer } from './components/PlayerDrawer'
import { Overview } from './pages/Overview'
import { MissionControl } from './pages/MissionControl'
import { Players } from './pages/Players'
import { Feed } from './pages/Feed'
import { CheatTools } from './pages/CheatTools'
import { Appeals, AppealForm } from './pages/Appeals'
import { Reports } from './pages/Reports'
import { Tuning } from './pages/Tuning'
import { Bans } from './pages/Bans'
import { Settings } from './pages/Settings'

const ReplayViewer = lazy(() => import('./pages/ReplayViewer'))

const TABS = ['overview', 'mission', 'players', 'feed', 'reports', 'tools', 'appeals', 'tuning', 'bans', 'settings'] as const
type Tab = (typeof TABS)[number]
const LABELS: Record<Tab, string> = {
  overview: 'Overview',
  mission: 'Live map',
  players: 'Players',
  feed: 'Feed',
  reports: 'Reports',
  tools: 'Tools',
  appeals: 'Appeals',
  tuning: 'Tuning',
  bans: 'Bans',
  settings: 'Settings',
}

type Route = { tab: Tab | 'appeal'; player?: number; replay?: number; game?: number }

function parseHash(): Route {
  const [, a, b, c] = window.location.hash.split('/')
  const id = Number(b)
  const game = Number(c)
  if (a === 'replay' && Number.isSafeInteger(id)) return { tab: 'overview', replay: id }
  if (a === 'player' && Number.isSafeInteger(id)) {
    return { tab: 'players', player: id, game: Number.isSafeInteger(game) && game > 0 ? game : undefined }
  }
  if (a === 'appeal') return { tab: 'appeal' }
  return { tab: (TABS as readonly string[]).includes(a) ? (a as Tab) : 'overview' }
}

function Shield({ className = '' }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={className} aria-hidden>
      <path d="M16 2 4 7v8c0 7.2 5 13.2 12 15 7-1.8 12-7.8 12-15V7z" fill="currentColor" opacity="0.18" />
      <path d="M16 2 4 7v8c0 7.2 5 13.2 12 15 7-1.8 12-7.8 12-15V7z" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="m11 16 3.5 3.5L21 13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function Login({ appeal }: { appeal: boolean }) {
  const [error, setError] = useState('')
  async function go() {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'discord',
      options: { redirectTo: window.location.origin + window.location.pathname + window.location.hash, scopes: 'identify' },
    })
    if (error) setError(error.message)
  }
  return (
    <div className="grid-bg grid min-h-full place-items-center p-6">
      <div className="w-full max-w-sm rounded-2xl border border-line bg-panel/90 p-8 text-center shadow-2xl shadow-black/50 backdrop-blur">
        <Shield className="mx-auto h-12 w-12 text-accent" />
        <h1 className="mt-4 text-xl font-semibold">{appeal ? 'Appeal a ban' : 'AntiCheat'}</h1>
        <p className="mt-1 text-sm text-muted">
          {appeal ? 'Sign in with Discord so we can get back to you.' : 'Staff only. Sign in with the Discord account you were approved with.'}
        </p>
        <button
          onClick={go}
          className="mt-6 inline-flex w-full items-center justify-center gap-2 rounded-lg bg-[#5865F2] px-4 py-2.5 font-medium text-white transition hover:bg-[#4752c4]"
        >
          Continue with Discord
        </button>
        {error && <p className="mt-3 text-sm text-bad">{error}</p>}
        {!appeal && (
          <a href="#/appeal" className="mt-4 block text-xs text-muted hover:text-text">
            Banned? Appeal here
          </a>
        )}
      </div>
    </div>
  )
}

function Pending({ me, signOut }: { me: DashUser | null; signOut: () => void }) {
  return (
    <div className="min-h-full">
      <header className="border-b border-line">
        <div className="mx-auto flex max-w-3xl items-center gap-3 px-5 py-3">
          <Shield className="h-7 w-7 text-accent" />
          <span className="font-semibold">AntiCheat</span>
          <div className="ml-auto">
            <Button tone="ghost" onClick={signOut}>Sign out</Button>
          </div>
        </div>
      </header>
      <main className="px-5 py-8">
        {me && (
          <p className="mx-auto mb-6 max-w-xl rounded-lg border border-line bg-panel px-4 py-3 text-sm text-muted">
            {me.role === 'staff'
              ? "You're on the team but haven't been given a game yet. The owner can add you in Settings → Team."
              : 'Staff? The owner still needs to approve your account (Settings → Team). Everyone else can appeal a ban below.'}
          </p>
        )}
        <AppealForm />
      </main>
    </div>
  )
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [ready, setReady] = useState(false)
  const [profile, setProfile] = useState<DashUser | null>(null)
  const [route, setRoute] = useState<Route>(parseHash)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setReady(true)
    })
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) return
    let alive = true
    const load = () =>
      supabase
        .from('dashboard_users')
        .select('*')
        .eq('user_id', session.user.id)
        .maybeSingle()
        .then(({ data, error }) => {
          if (alive && !error) setProfile(data)
        })
    load()
    const timer = setInterval(load, 15_000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [session])

  const me = session ? profile : null

  const [games, setGames] = useState<Game[]>([])
  const [picked, setPicked] = useState<number | null>(() => parseHash().game ?? savedGame())

  useEffect(() => {
    const onHash = () => {
      const r = parseHash()
      setRoute(r)
      if (r.game) {
        setPicked(r.game)
        saveGame(r.game)
      }
    }
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])
  const signedIn = me?.role === 'owner' || me?.role === 'admin' || me?.role === 'staff'

  const reloadGames = useCallback(() => {
    supabase
      .from('games')
      .select('*')
      .order('id')
      .then(({ data }) => setGames(data ?? []))
  }, [])
  useEffect(() => {
    if (signedIn) reloadGames()
  }, [signedIn, reloadGames])

  const game =
    games.find((g) => g.id === route.game)?.id ?? games.find((g) => g.id === picked)?.id ?? games[0]?.id ?? 0
  const pickGame = useCallback((id: number) => {
    setPicked(id)
    saveGame(id)
  }, [])

  const approved = signedIn && games.length > 0
  const data = useConsole(approved, game)
  const kick = data.config?.thresholds?.KickScore ?? DEFAULTS.KickScore
  const current = games.find((g) => g.id === game)
  const gameState = useMemo(() => ({ game, games, current, reloadGames }), [game, games, current, reloadGames])

  const signOut = useCallback(() => {
    supabase.auth.signOut()
  }, [])
  const open = useCallback(
    (id: number, inGame?: number) => {
      window.location.hash = `#/player/${id}/${inGame ?? game}`
    },
    [game],
  )
  const openReplay = useCallback((id: number) => {
    window.location.hash = `#/replay/${id}`
  }, [])
  const close = useCallback(() => {
    if (window.history.length > 1) window.history.back()
    else window.location.hash = '#/players'
  }, [])

  const selectedPlayer = useMemo(() => data.players.find((p) => p.user_id === route.player), [data.players, route.player])
  const selectedBan = useMemo(() => data.bans.find((b) => b.user_id === route.player), [data.bans, route.player])
  const openAppeals = data.appeals.filter((a) => a.status === 'open').length
  const reported = new Set(data.reports.filter((r) => r.status === 'open').map((r) => r.target_id)).size

  if (!ready) return null
  if (!session) return <Login appeal={route.tab === 'appeal'} />
  if (signedIn && games.length === 0 && route.tab !== 'appeal') {
    return <GamesLoading me={me} signOut={signOut} reload={reloadGames} />
  }
  if (!approved) return <Pending me={me} signOut={signOut} />

  if (route.replay) {
    return (
      <GameContext.Provider value={gameState}>
        <Suspense fallback={<div className="grid min-h-full place-items-center text-sm text-muted">Loading 3D viewer…</div>}>
          <ReplayViewer id={route.replay} back={close} openPlayer={open} />
        </Suspense>
      </GameContext.Provider>
    )
  }

  const tab = route.tab === 'appeal' ? 'appeals' : route.tab

  return (
    <GameContext.Provider value={gameState}>
    <div className="min-h-full">
      <header className="sticky top-0 z-30 border-b border-line bg-bg/85 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center gap-5 px-5 py-3">
          <a href="#/overview" className="flex items-center gap-2.5">
            <Shield className="h-7 w-7 text-accent" />
            <span className="font-semibold tracking-tight">AntiCheat</span>
            <span className="rounded border border-line px-1.5 py-0.5 font-mono text-[10px] text-muted">staff</span>
          </a>
          {games.length > 1 ? (
            <select
              value={game}
              onChange={(e) => pickGame(Number(e.target.value))}
              aria-label="Game"
              className="max-w-44 truncate rounded-lg border border-line bg-panel-2 px-2 py-1 text-sm font-medium outline-none focus:border-accent/60"
            >
              {games.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          ) : (
            <span className="hidden truncate text-sm text-muted sm:inline">{current?.name}</span>
          )}
          <div className="ml-auto flex items-center gap-4">
            <span className="flex items-center gap-2 text-xs text-muted">
              <Dot on={data.live} /> {data.live ? 'live' : 'connecting'}
            </span>
            {me?.avatar_url?.startsWith('https://cdn.discordapp.com/') && <img src={me.avatar_url} alt="" className="h-7 w-7 rounded-full" />}
            <Button tone="ghost" onClick={signOut}>Sign out</Button>
          </div>
        </div>
        <nav className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-3 pb-2">
          {TABS.map((t) => (
            <a
              key={t}
              href={`#/${t}`}
              className={`shrink-0 rounded-lg px-3 py-1.5 text-sm transition ${tab === t ? 'bg-panel-2 text-text' : 'text-muted hover:text-text'}`}
            >
              {LABELS[t]}
              {t === 'appeals' && openAppeals > 0 && (
                <span className="ml-1.5 rounded-full bg-warn/20 px-1.5 text-[10px] font-semibold text-warn">{openAppeals}</span>
              )}
              {t === 'reports' && reported > 0 && (
                <span className="ml-1.5 rounded-full bg-warn/20 px-1.5 text-[10px] font-semibold text-warn">{reported}</span>
              )}
            </a>
          ))}
        </nav>
      </header>

      <main className="mx-auto max-w-7xl px-5 py-6">
        {data.loading ? (
          <div className="py-20 text-center text-sm text-muted">Loading…</div>
        ) : (
          <>
            {tab === 'overview' && <Overview {...data} kick={kick} open={open} />}
            {tab === 'mission' && <MissionControl key={game} servers={data.servers} kick={kick} open={open} />}
            {tab === 'players' && <Players players={data.players} bans={data.bans} kick={kick} open={open} />}
            {tab === 'feed' && <Feed flags={data.flags} players={data.players} fresh={data.fresh} open={open} />}
            {tab === 'reports' && <Reports reports={data.reports} players={data.players} bans={data.bans} kick={kick} open={open} openReplay={openReplay} />}
            {tab === 'tools' && <CheatTools key={game} players={data.players} open={open} openReplay={openReplay} />}
            {tab === 'appeals' && <Appeals appeals={data.appeals} bans={data.bans} players={data.players} open={open} openReplay={openReplay} />}
            {tab === 'tuning' && <Tuning config={data.config} players={data.players} bans={data.bans} reload={data.reload} />}
            {tab === 'bans' && <Bans bans={data.bans} players={data.players} open={open} />}
            {tab === 'settings' && me && <Settings config={data.config} users={data.users} staff={data.staff} me={me} reload={data.reload} />}
          </>
        )}
      </main>

      {route.player !== undefined && (
        <PlayerDrawer
          userId={route.player}
          player={selectedPlayer}
          ban={selectedBan}
          kick={kick}
          close={close}
          openReplay={openReplay}
          open={open}
        />
      )}
    </div>
    </GameContext.Provider>
  )
}

function GamesLoading({ me, signOut, reload }: { me: DashUser | null; signOut: () => void; reload: () => void }) {
  const [waited, setWaited] = useState(false)
  useEffect(() => {
    const t = setTimeout(() => setWaited(true), 2500)
    const again = setInterval(reload, 15_000)
    return () => {
      clearTimeout(t)
      clearInterval(again)
    }
  }, [reload])
  if (!waited) return <div className="grid min-h-full place-items-center text-sm text-muted">Loading…</div>
  return <Pending me={me} signOut={signOut} />
}
