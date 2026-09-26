import { useEffect, useState } from 'react'
import { supabase, type Action, type Ban, type Flag, type Player, type Report, type Revert } from '../lib/supabase'
import { ago, errorText, isOnline, robloxProfile, scoreTone } from '../lib/format'
import { useGame } from '../lib/game'
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
type LedgerRow = { kind: string; key: string; amount: number; victim: number | null; withheld: boolean; created_at: string }

const UNDO_WINDOWS = [
  { label: 'since they started cheating', hours: null },
  { label: 'last hour', hours: 1 },
  { label: 'last 24 hours', hours: 24 },
  { label: 'last 7 days', hours: 168 },
]

function gains(rows: LedgerRow[]) {
  const out = new Map<string, { label: string; amount: number; held: number }>()
  for (const r of rows) {
    const key = r.kind === 'kill' ? 'kills' : `${r.kind}:${r.key}`
    const e = out.get(key) ?? { label: r.kind === 'kill' ? 'Kills' : r.key, amount: 0, held: 0 }
    if (r.withheld) e.held += r.amount
    else e.amount += r.amount
    out.set(key, e)
  }
  return [...out.values()].sort((a, b) => b.amount + b.held - (a.amount + a.held))
}

function summaryText(s: Revert['summary']) {
  const parts = [
    ...Object.entries(s.currency ?? {}).map(([k, v]) => `${Math.round(v)} ${k}`),
    ...Object.entries(s.items ?? {}).map(([k, v]) => (v > 1 ? `${v}× ${k}` : k)),
  ]
  if (s.kills) parts.push(`${s.kills} kills`)
  const victims = Object.keys(s.victims ?? {}).length
  if (victims) parts.push(`${victims} ${victims === 1 ? 'victim' : 'victims'} to pay back`)
  return parts.length ? parts.join(', ') : 'nothing'
}

export function PlayerDrawer({ userId, player, ban, kick, close, openReplay, open }: Props) {
  const { game } = useGame()
  const [flags, setFlags] = useState<Flag[]>([])
  const [actions, setActions] = useState<Action[]>([])
  const [replays, setReplays] = useState<ReplayRow[]>([])
  const [reports, setReports] = useState<Report[]>([])
  const [reverts, setReverts] = useState<Revert[]>([])
  const [ledger, setLedger] = useState<LedgerRow[]>([])
  const [undoWindow, setUndoWindow] = useState(0)
  const [actMsg, setActMsg] = useState('')
  const [tick, setTick] = useState(0)
  const [cmdMsg, setCmdMsg] = useState('')
  const [reason, setReason] = useState('')
  const [duration, setDuration] = useState(0)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    const week = new Date(Date.now() - 7 * 86_400_000).toISOString()
    Promise.all([
      supabase.from('flags').select('*').eq('game_id', game).eq('user_id', userId).order('created_at', { ascending: false }).limit(100),
      supabase.from('actions').select('*').eq('game_id', game).eq('user_id', userId).order('created_at', { ascending: false }).limit(50),
      supabase.from('replays').select('id, kind, reason, created_at').eq('game_id', game).eq('user_id', userId).order('created_at', { ascending: false }).limit(20),
      supabase.from('reports').select('*').eq('game_id', game).eq('target_id', userId).order('created_at', { ascending: false }).limit(30),
      supabase.from('reverts').select('*').eq('game_id', game).eq('user_id', userId).order('created_at', { ascending: false }).limit(10),
      supabase.from('ledger').select('kind, key, amount, victim, withheld, created_at').eq('game_id', game).eq('user_id', userId).gte('created_at', week).limit(2000),
    ]).then(([f, a, r, rp, rv, l]) => {
      if (!alive) return
      setFlags(f.data ?? [])
      setActions(a.data ?? [])
      setReplays(r.data ?? [])
      setReports(rp.data ?? [])
      setReverts(rv.data ?? [])
      setLedger(l.data ?? [])
    })
    return () => {
      alive = false
    }
  }, [game, userId, ban?.updated_at, player?.shadowed, tick])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [close])

  const banned = ban?.active && (!ban.expires_at || new Date(ban.expires_at).getTime() > Date.now())
  const online = player ? isOnline(player.last_seen) : false

  async function command(kind: 'replay' | 'spectate' | 'kick') {
    setCmdMsg('')
    const { error } = await supabase.rpc('admin_command', { p_game: game, p_kind: kind, p_target: userId })
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
        supabase.from('replays').select('id, kind, reason, created_at').eq('game_id', game).eq('user_id', userId).order('created_at', { ascending: false }).limit(20).then(({ data }) => setReplays(data ?? []))
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
      p_game: game,
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
    const { error } = await supabase.rpc('admin_unban', { p_game: game, p_user_id: userId })
    setBusy(false)
    if (error) setError(errorText(error))
  }

  async function act(call: () => PromiseLike<{ error: unknown }>, done: string) {
    setActMsg('')
    const { error } = await call()
    setActMsg(error ? errorText(error) : done)
    setTick((t) => t + 1)
  }

  const shadowed = player?.shadowed ?? false
  const gained = gains(ledger)
  const openReports = reports.filter((r) => r.status === 'open')

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
                {shadowed && <span className="rounded bg-veil/15 px-1.5 text-[10px] font-semibold uppercase text-veil">shadowed</span>}
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

          {!banned && (
            <section className={`rounded-xl border p-4 ${shadowed ? 'border-veil/40 bg-veil/5' : 'border-line bg-panel'}`}>
              <div className="flex items-start gap-3">
                <div className="flex-1 text-sm">
                  <div className="font-medium">{shadowed ? 'In shadow mode' : 'Shadow mode'}</div>
                  <div className="mt-0.5 text-xs text-muted">
                    {shadowed
                      ? `Since ${player?.shadowed_at ? ago(player.shadowed_at) : 'a while'}, by ${player?.shadow_by ?? 'anticheat'}. They keep playing, their hits do nothing, their earnings are held, and every check keeps collecting proof.${player?.shadow_by && player.shadow_by !== 'anticheat' ? ' Staff shadow: no auto-kick.' : ''}`
                      : 'Keep them in the game without letting them hurt anyone or earn anything, while the anticheat collects proof.'}
                  </div>
                </div>
                <Button
                  tone={shadowed ? 'default' : 'accent'}
                  onClick={() =>
                    act(
                      () => supabase.rpc('admin_set_shadow', { p_game: game, p_user_id: userId, p_on: !shadowed }),
                      shadowed ? 'Shadow mode lifted.' : 'Shadowed. Online players switch within a few seconds.',
                    )
                  }
                >
                  {shadowed ? 'Lift' : 'Shadow'}
                </Button>
              </div>
            </section>
          )}

          {online && (
            <section className="flex flex-wrap items-center gap-2">
              <Button tone="accent" onClick={() => command('spectate')}>Spectate</Button>
              <Button onClick={() => command('replay')}>Record replay</Button>
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

          {actMsg && <div className="text-sm text-muted">{actMsg}</div>}

          {(reports.length > 0 || (player?.reports_made ?? 0) > 0) && (
            <section>
              <h3 className="mb-2 text-xs font-semibold uppercase tracking-[0.14em] text-muted">
                Reports{openReports.length > 0 && <span className="text-warn"> · {openReports.length} open</span>}
              </h3>
              {reports.length > 0 && (
                <ul className="space-y-2">
                  {reports.slice(0, 8).map((r) => (
                    <li key={r.id} className="rounded-lg border border-line bg-panel p-3 text-sm">
                      <div className="flex items-center justify-between gap-2">
                        <span>
                          <span className="font-medium text-warn">{r.reason}</span>
                          <span className="text-muted"> by </span>
                          <button onClick={() => open(r.reporter_id)} className="font-mono text-xs text-accent hover:underline">
                            {r.reporter_id}
                          </button>
                        </span>
                        <span className="text-xs text-muted">
                          {r.status !== 'open' && `${r.status} · `}weight {r.weight.toFixed(2)} · {ago(r.created_at)}
                        </span>
                      </div>
                      {r.note && <div className="mt-1 text-muted">"{r.note}"</div>}
                      {r.replay_id && (
                        <button onClick={() => openReplay(r.replay_id!)} className="mt-1 text-xs text-accent hover:underline">
                          ▶ replay from the moment of the report
                        </button>
                      )}
                    </li>
                  ))}
                </ul>
              )}
              {openReports.length > 0 && !banned && (
                <div className="mt-2">
                  <Button tone="ghost" onClick={() => act(() => supabase.rpc('admin_decide_reports', { p_game: game, p_target: userId, p_confirm: false }), 'Reports dismissed.')}>
                    Dismiss open reports
                  </Button>
                </div>
              )}
              {player && player.reports_made > 0 && (
                <p className="mt-2 text-xs text-muted">
                  As a reporter: {player.reports_made} sent, {player.reports_confirmed} led to a ban, {player.reports_dismissed} dismissed.
                </p>
              )}
            </section>
          )}

          <section className="rounded-xl border border-line bg-panel p-4">
            <div className="text-xs font-semibold uppercase tracking-[0.14em] text-muted">Gains this week</div>
            {gained.length === 0 ? (
              <p className="mt-2 text-sm text-muted">
                Nothing recorded. Leaderstats are tracked automatically, other currencies and items need AntiCheat.Grant in your game code.
              </p>
            ) : (
              <ul className="mt-2 grid grid-cols-2 gap-2">
                {gained.slice(0, 8).map((g) => (
                  <li key={g.label} className="rounded-lg bg-panel-2 px-3 py-2">
                    <div className="truncate text-xs text-muted">{g.label}</div>
                    <div className="font-mono">
                      {Math.round(g.amount)}
                      {g.held > 0 && <span className="ml-1.5 text-xs text-veil">+{Math.round(g.held)} held</span>}
                    </div>
                  </li>
                ))}
              </ul>
            )}
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <select
                value={undoWindow}
                onChange={(e) => setUndoWindow(Number(e.target.value))}
                className="rounded-lg border border-line bg-panel-2 px-2 py-1.5 text-sm"
              >
                {UNDO_WINDOWS.map((w, i) => (
                  <option key={w.label} value={i}>
                    Undo {w.label}
                  </option>
                ))}
              </select>
              <Button
                tone="danger"
                onClick={() =>
                  act(
                    () => supabase.rpc('admin_revert', { p_game: game, p_user_id: userId, p_hours: UNDO_WINDOWS[undoWindow].hours }),
                    'Undo queued. The next live server of the game runs it, usually within 20 seconds.',
                  )
                }
              >
                Undo gains
              </Button>
              <span className="text-xs text-muted">bans do this on their own</span>
            </div>
            {reverts.length > 0 && (
              <ul className="mt-3 space-y-1.5">
                {reverts.slice(0, 4).map((r) => (
                  <li key={r.id} className="flex items-start gap-2 text-xs">
                    <span
                      className={`mt-0.5 rounded px-1.5 py-0.5 font-semibold uppercase ${
                        r.status === 'done' ? 'bg-good/15 text-good' : r.status === 'failed' ? 'bg-bad/15 text-bad' : 'bg-line text-muted'
                      }`}
                    >
                      {r.status === 'sent' ? 'running' : r.status}
                    </span>
                    <span className="flex-1 text-muted">
                      {summaryText(r.summary)}
                      {r.result && <span className="block text-muted/70">{r.result}</span>}
                    </span>
                    <span className="text-muted">{ago(r.created_at)}</span>
                  </li>
                ))}
              </ul>
            )}
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
                    <span
                      className={
                        a.action === 'unban' || a.action === 'unshadow'
                          ? 'text-good'
                          : a.action === 'ban' || a.action === 'revert'
                            ? 'text-bad'
                            : a.action === 'shadow'
                              ? 'text-veil'
                              : 'text-warn'
                      }
                    >
                      {a.action === 'revert' ? 'undo' : a.action}
                    </span>
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
