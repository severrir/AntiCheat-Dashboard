import { useEffect, useState } from 'react'
import { supabase, type Action, type Ban, type Flag, type Player } from '../lib/supabase'
import { ago, errorText, isOnline, robloxProfile, scoreTone } from '../lib/format'
import { Button, CheckTag, Dot, Empty, ScoreBar } from './ui'
import { Context } from './Context'

const DURATIONS = [
  { label: 'Permanent', hours: null },
  { label: '1 day', hours: 24 },
  { label: '3 days', hours: 72 },
  { label: '7 days', hours: 168 },
  { label: '30 days', hours: 720 },
]

type Props = {
  userId: number
  player?: Player
  ban?: Ban
  kick: number
  close: () => void
  openReplay: (id: number) => void
  open: (id: number) => void
}

type ReplayRow = { id: number; kind: string; reason: string; created_at: string }

export function PlayerDrawer({ userId, player, ban, kick, close, openReplay, open }: Props) {
  const [flags, setFlags] = useState<Flag[]>([])
  const [actions, setActions] = useState<Action[]>([])
  const [replays, setReplays] = useState<ReplayRow[]>([])
  const [cmdMsg, setCmdMsg] = useState('')
  const [reason, setReason] = useState('')
  const [duration, setDuration] = useState(0)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    Promise.all([
      supabase.from('flags').select('*').eq('user_id', userId).order('created_at', { ascending: false }).limit(100),
      supabase.from('actions').select('*').eq('user_id', userId).order('created_at', { ascending: false }).limit(50),
      supabase.from('replays').select('id, kind, reason, created_at').eq('user_id', userId).order('created_at', { ascending: false }).limit(20),
    ]).then(([f, a, r]) => {
      if (!alive) return
      setFlags(f.data ?? [])
      setActions(a.data ?? [])
      setReplays(r.data ?? [])
    })
    return () => {
      alive = false
    }
  }, [userId, ban?.updated_at])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [close])

  const banned = ban?.active && (!ban.expires_at || new Date(ban.expires_at).getTime() > Date.now())
  const online = player ? isOnline(player.last_seen) : false

  // these go into whichever live server the player is on, through the next pulse (~5s)
  async function command(kind: 'replay' | 'spectate' | 'kick') {
    setCmdMsg('')
    const { error } = await supabase.rpc('admin_command', { p_kind: kind, p_target: userId })
    if (error) setCmdMsg(errorText(error))
    else
      setCmdMsg(
        kind === 'replay'
          ? 'Capturing, it shows up below in a few seconds.'
          : kind === 'spectate'
            ? 'Sent. If you are in any server of the game, you get pulled in invisibly.'
            : 'Kick sent.',
      )
    if (kind === 'replay') {
      setTimeout(() => {
        supabase.from('replays').select('id, kind, reason, created_at').eq('user_id', userId).order('created_at', { ascending: false }).limit(20).then(({ data }) => setReplays(data ?? []))
      }, 8000)
    }
  }

  async function doBan() {
    if (!reason.trim()) {
      setError('Give a reason, it shows up for the player.')
      return
    }
    setBusy(true)
    setError('')
    const { error } = await supabase.rpc('admin_ban', {
      p_user_id: userId,
      p_reason: reason.trim(),
      p_hours: DURATIONS[duration].hours,
    })
    setBusy(false)
    if (error) setError(errorText(error))
    else setReason('')
  }

  async function doUnban() {
    setBusy(true)
    setError('')
    const { error } = await supabase.rpc('admin_unban', { p_user_id: userId })
    setBusy(false)
    if (error) setError(errorText(error))
  }

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={close} />
      <aside className="relative flex h-full w-full max-w-xl flex-col overflow-y-auto border-l border-line bg-bg">
        <header className="sticky top-0 z-10 border-b border-line bg-bg/95 px-5 py-4 backdrop-blur">
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                {player && <Dot on={isOnline(player.last_seen)} />}
                <h2 className="truncate text-lg font-semibold">{player?.username || 'Unknown player'}</h2>
                {banned && <span className="rounded bg-bad/15 px-1.5 text-[10px] font-semibold uppercase text-bad">banned</span>}
              </div>
              <a href={robloxProfile(userId)} target="_blank" rel="noopener noreferrer" className="font-mono text-xs text-accent hover:underline">
                {userId} ↗
              </a>
            </div>
            <Button tone="ghost" onClick={close}>
              Close
            </Button>
          </div>
        </header>

        <div className="space-y-6 p-5">
          {player?.alt_of && (
            <button onClick={() => open(player.alt_of!)} className="w-full rounded-lg border border-warn/40 bg-warn/10 px-3 py-2 text-left text-sm text-warn">
              Possible alt of <span className="font-mono">{player.alt_of}</span>: plays {Math.round((player.alt_score ?? 0) * 100)}% like a banned account
              {player.account_age !== null && <span className="text-warn/70"> · account is {player.account_age} days old</span>}
            </button>
          )}
          {player?.on_island && <div className="rounded-lg bg-bad/10 px-3 py-2 text-sm text-bad">Currently on Cheater Island</div>}

          {online && (
            <section className="flex flex-wrap items-center gap-2">
              <Button tone="accent" onClick={() => command('spectate')}>👁 Spectate</Button>
              <Button onClick={() => command('replay')}>⏺ Capture replay</Button>
              <Button tone="danger" onClick={() => command('kick')}>Kick</Button>
              {cmdMsg && <span className="w-full text-xs text-muted">{cmdMsg}</span>}
            </section>
          )}

          {player && (
            <div className="grid grid-cols-4 gap-3">
              {[
                ['Score', player.trust_score.toFixed(1), scoreTone(player.trust_score, kick)],
                ['Peak', player.peak_score.toFixed(1), scoreTone(player.peak_score, kick)],
                ['Flags', String(player.total_flags), ''],
                ['Kicks', String(player.kicks), ''],
              ].map(([label, value, tone]) => (
                <div key={label} className="rounded-lg border border-line bg-panel p-3">
                  <div className="text-[10px] uppercase tracking-[0.14em] text-muted">{label}</div>
                  <div className={`mt-1 font-mono text-xl ${tone}`}>{value}</div>
                </div>
              ))}
              <div className="col-span-4">
                <ScoreBar score={player.peak_score} kick={kick} />
                <div className="mt-1.5 flex justify-between text-[11px] text-muted">
                  <span>first seen {ago(player.first_seen)}</span>
                  <span>last seen {ago(player.last_seen)}</span>
                </div>
              </div>
            </div>
          )}

          <section className="rounded-xl border border-line bg-panel p-4">
            {banned ? (
              <div className="space-y-3">
                <div className="text-sm">
                  Banned by <span className="font-medium">{ban!.banned_by}</span> {ago(ban!.updated_at)}
                  {ban!.expires_at && <> · until {new Date(ban!.expires_at).toLocaleString()}</>}
                </div>
                {ban!.reason && <div className="rounded-lg bg-panel-2 px-3 py-2 text-sm text-muted">{ban!.reason}</div>}
                <div className="text-xs text-muted">{ban!.roblox_synced ? 'Roblox ban applied' : 'Waiting for a live server to apply the Roblox ban'}</div>
                <Button tone="accent" onClick={doUnban} disabled={busy}>
                  Unban
                </Button>
              </div>
            ) : (
              <form
                className="space-y-3"
                onSubmit={(e) => {
                  e.preventDefault()
                  doBan()
                }}
              >
                <div className="text-xs font-semibold uppercase tracking-[0.14em] text-muted">Ban player</div>
                <input
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  maxLength={200}
                  placeholder="Reason (the player sees this)"
                  className="w-full rounded-lg border border-line bg-panel-2 px-3 py-2 text-sm outline-none focus:border-bad/60"
                />
                <div className="flex flex-wrap items-center gap-2">
                  <select
                    value={duration}
                    onChange={(e) => setDuration(Number(e.target.value))}
                    className="rounded-lg border border-line bg-panel-2 px-2 py-1.5 text-sm"
                  >
                    {DURATIONS.map((d, i) => (
                      <option key={d.label} value={i}>
                        {d.label}
                      </option>
                    ))}
                  </select>
                  <Button tone="danger" type="submit" disabled={busy}>
                    Ban
                  </Button>
                  <span className="text-xs text-muted">kicks them from every server within ~20s</span>
                </div>
              </form>
            )}
            {error && <div className="mt-3 text-sm text-bad">{error}</div>}
          </section>

          {replays.length > 0 && (
            <section>
              <h3 className="mb-2 text-xs font-semibold uppercase tracking-[0.14em] text-muted">3D replays</h3>
              <ul className="space-y-2">
                {replays.map((r) => (
                  <li key={r.id}>
                    <button onClick={() => openReplay(r.id)} className="flex w-full items-center gap-3 rounded-lg border border-line bg-panel p-3 text-left hover:border-accent/40">
                      <span className="grid h-8 w-8 place-items-center rounded-full bg-accent/15 text-accent">▶</span>
                      <span className="flex-1">
                        <span className="block text-sm font-medium">#{r.id} · {r.kind}</span>
                        <span className="block truncate text-xs text-muted">{r.reason || 'no reason'}</span>
                      </span>
                      <span className="text-xs text-muted">{ago(r.created_at)}</span>
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          )}

          <section>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-[0.14em] text-muted">Flag history</h3>
            {flags.length === 0 ? (
              <Empty>No flags on record (flags are kept 30 days).</Empty>
            ) : (
              <ul className="space-y-2">
                {flags.map((f) => (
                  <li key={f.id} className="rounded-lg border border-line bg-panel p-3">
                    <div className="flex items-center justify-between gap-2">
                      <CheckTag name={f.check_name} />
                      <span className="font-mono text-xs text-muted">
                        +{f.severity.toFixed(0)}
                        {f.hits > 1 && ` ×${f.hits}`} · {ago(f.created_at)}
                      </span>
                    </div>
                    <div className="mt-2">
                      <Context ctx={f.context} />
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-[0.14em] text-muted">Actions</h3>
            {actions.length === 0 ? (
              <Empty>No kicks or bans.</Empty>
            ) : (
              <ul className="divide-y divide-line rounded-lg border border-line bg-panel">
                {actions.map((a) => (
                  <li key={a.id} className="flex items-center justify-between gap-3 px-3 py-2 text-sm">
                    <span className={a.action === 'unban' ? 'text-good' : a.action === 'ban' ? 'text-bad' : 'text-warn'}>{a.action}</span>
                    <span className="flex-1 truncate text-muted">{a.reason}</span>
                    <span className="text-xs text-muted">
                      {a.actor} · {ago(a.created_at)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </aside>
    </div>
  )
}
