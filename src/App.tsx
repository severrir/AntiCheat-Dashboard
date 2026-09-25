import { useCallback, useEffect, useMemo, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, type DashUser } from './lib/supabase'
import { useConsole } from './lib/useConsole'
import { DEFAULTS } from './lib/thresholds'
import { Button, Dot } from './components/ui'
import { PlayerDrawer } from './components/PlayerDrawer'
import { Overview } from './pages/Overview'
import { Players } from './pages/Players'
import { Feed } from './pages/Feed'
import { Bans } from './pages/Bans'
import { Settings } from './pages/Settings'

const TABS = ['overview', 'players', 'feed', 'bans', 'settings'] as const
type Tab = (typeof TABS)[number]
const LABELS: Record<Tab, string> = { overview: 'Overview', players: 'Players', feed: 'Live feed', bans: 'Bans', settings: 'Settings' }

function tabFromHash(): Tab {
  const t = window.location.hash.replace('#/', '') as Tab
  return TABS.includes(t) ? t : 'overview'
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

function Login() {
  const [error, setError] = useState('')
  async function go() {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'discord',
      options: { redirectTo: window.location.origin + window.location.pathname, scopes: 'identify' },
    })
    if (error) setError(error.message)
  }
  return (
    <div className="grid-bg grid min-h-full place-items-center p-6">
      <div className="w-full max-w-sm rounded-2xl border border-line bg-panel/90 p-8 text-center shadow-2xl shadow-black/50 backdrop-blur">
        <Shield className="mx-auto h-12 w-12 text-accent" />
        <h1 className="mt-4 text-xl font-semibold">AntiCheat Console</h1>
        <p className="mt-1 text-sm text-muted">Staff only. Sign in with the Discord account you were approved with.</p>
        <button
          onClick={go}
          className="mt-6 inline-flex w-full items-center justify-center gap-2 rounded-lg bg-[#5865F2] px-4 py-2.5 font-medium text-white transition hover:bg-[#4752c4]"
        >
          Continue with Discord
        </button>
        {error && <p className="mt-3 text-sm text-bad">{error}</p>}
      </div>
    </div>
  )
}

function Waiting({ me, signOut }: { me: DashUser | null; signOut: () => void }) {
  return (
    <div className="grid-bg grid min-h-full place-items-center p-6">
      <div className="w-full max-w-sm rounded-2xl border border-line bg-panel/90 p-8 text-center">
        <Shield className="mx-auto h-12 w-12 text-warn" />
        <h1 className="mt-4 text-lg font-semibold">{me ? 'Waiting for approval' : 'Setting up your account'}</h1>
        <p className="mt-2 text-sm text-muted">
          {me ? 'The owner needs to approve you before you can see anything. Ask them to check Settings → Team.' : 'One sec…'}
        </p>
        <div className="mt-6">
          <Button onClick={signOut}>Sign out</Button>
        </div>
      </div>
    </div>
  )
}

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [ready, setReady] = useState(false)
  const [me, setMe] = useState<DashUser | null>(null)
  const [tab, setTab] = useState<Tab>(tabFromHash)
  const [selected, setSelected] = useState<number | null>(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setReady(true)
    })
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) {
      setMe(null)
      return
    }
    let alive = true
    const load = () =>
      supabase
        .from('dashboard_users')
        .select('*')
        .eq('user_id', session.user.id)
        .maybeSingle()
        .then(({ data }) => alive && setMe(data))
    load()
    // pending users poll so they get in as soon as they're approved
    const timer = setInterval(load, 15_000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [session])

  useEffect(() => {
    const onHash = () => setTab(tabFromHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  const approved = me?.role === 'owner' || me?.role === 'admin'
  const data = useConsole(approved)
  const kick = data.config?.thresholds?.KickScore ?? DEFAULTS.KickScore

  const signOut = useCallback(() => {
    supabase.auth.signOut()
  }, [])
  const open = useCallback((id: number) => setSelected(id), [])
  const close = useCallback(() => setSelected(null), [])

  const selectedPlayer = useMemo(() => data.players.find((p) => p.user_id === selected), [data.players, selected])
  const selectedBan = useMemo(() => data.bans.find((b) => b.user_id === selected), [data.bans, selected])

  if (!ready) return null
  if (!session) return <Login />
  if (!approved) return <Waiting me={me} signOut={signOut} />

  return (
    <div className="min-h-full">
      <header className="sticky top-0 z-30 border-b border-line bg-bg/85 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center gap-6 px-5 py-3">
          <div className="flex items-center gap-2.5">
            <Shield className="h-7 w-7 text-accent" />
            <span className="font-semibold tracking-tight">AntiCheat</span>
            <span className="rounded border border-line px-1.5 py-0.5 font-mono text-[10px] text-muted">console</span>
          </div>
          <nav className="hidden gap-1 md:flex">
            {TABS.map((t) => (
              <a
                key={t}
                href={`#/${t}`}
                className={`rounded-lg px-3 py-1.5 text-sm transition ${tab === t ? 'bg-panel-2 text-text' : 'text-muted hover:text-text'}`}
              >
                {LABELS[t]}
              </a>
            ))}
          </nav>
          <div className="ml-auto flex items-center gap-4">
            <span className="flex items-center gap-2 text-xs text-muted">
              <Dot on={data.live} /> {data.live ? 'live' : 'connecting'}
            </span>
            {me?.avatar_url?.startsWith('https://cdn.discordapp.com/') && <img src={me.avatar_url} alt="" className="h-7 w-7 rounded-full" />}
            <Button tone="ghost" onClick={signOut}>
              Sign out
            </Button>
          </div>
        </div>
        <nav className="flex gap-1 overflow-x-auto px-3 pb-2 md:hidden">
          {TABS.map((t) => (
            <a key={t} href={`#/${t}`} className={`shrink-0 rounded-lg px-3 py-1.5 text-sm ${tab === t ? 'bg-panel-2 text-text' : 'text-muted'}`}>
              {LABELS[t]}
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
            {tab === 'players' && <Players players={data.players} bans={data.bans} kick={kick} open={open} />}
            {tab === 'feed' && <Feed flags={data.flags} players={data.players} fresh={data.fresh} open={open} />}
            {tab === 'bans' && <Bans bans={data.bans} players={data.players} open={open} />}
            {tab === 'settings' && me && <Settings config={data.config} users={data.users} me={me} reload={data.reload} />}
          </>
        )}
      </main>

      {selected !== null && <PlayerDrawer userId={selected} player={selectedPlayer} ban={selectedBan} kick={kick} close={close} />}
    </div>
  )
}
