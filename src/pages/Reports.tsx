import { useMemo, useState } from 'react'
import { supabase, type Ban, type Player, type Report } from '../lib/supabase'
import { ago, errorText, scoreTone } from '../lib/format'
import { useGame } from '../lib/game'
import { Button, Empty, Panel, ScoreBar } from '../components/ui'

type Props = {
  reports: Report[]
  players: Player[]
  bans: Ban[]
  kick: number
  open: (id: number) => void
  openReplay: (id: number) => void
}

type Group = {
  target: number
  reports: Report[]
  weight: number
  reasons: [string, number][]
  replay: number | null
  latest: string
}

function group(reports: Report[]): Group[] {
  const by = new Map<number, Report[]>()
  for (const r of reports) {
    const list = by.get(r.target_id) ?? []
    list.push(r)
    by.set(r.target_id, list)
  }
  return [...by.entries()]
    .map(([target, list]) => {
      const reasons = new Map<string, number>()
      for (const r of list) reasons.set(r.reason, (reasons.get(r.reason) ?? 0) + 1)
      const sorted = [...list].sort((a, b) => b.created_at.localeCompare(a.created_at))
      return {
        target,
        reports: sorted,
        weight: list.reduce((n, r) => n + r.weight, 0),
        reasons: [...reasons.entries()].sort((a, b) => b[1] - a[1]),
        replay: sorted.find((r) => r.replay_id)?.replay_id ?? null,
        latest: sorted[0].created_at,
      }
    })
    .sort((a, b) => b.weight - a.weight || b.latest.localeCompare(a.latest))
}

function track(p: Player | undefined) {
  if (!p) return null
  const decided = p.reports_confirmed + p.reports_dismissed
  return decided === 0 ? null : { right: p.reports_confirmed, of: decided }
}

export function Reports({ reports, players, bans, kick, open, openReplay }: Props) {
  const byId = useMemo(() => new Map(players.map((p) => [p.user_id, p])), [players])
  const banned = useMemo(() => new Set(bans.filter((b) => b.active).map((b) => b.user_id)), [bans])
  const openGroups = useMemo(() => group(reports.filter((r) => r.status === 'open')), [reports])
  const decided = useMemo(() => group(reports.filter((r) => r.status !== 'open')).slice(0, 20), [reports])
  const reporters = useMemo(
    () =>
      players
        .filter((p) => p.reports_made > 0)
        .sort((a, b) => b.reports_made - a.reports_made)
        .slice(0, 12),
    [players],
  )
  const name = (id: number) => byId.get(id)?.username || String(id)

  return (
    <div className="grid gap-5 xl:grid-cols-[1fr_320px]">
      <div className="space-y-5">
        <Panel title={`Open reports · ${openGroups.length} ${openGroups.length === 1 ? 'player' : 'players'}`}>
          {openGroups.length === 0 ? (
            <Empty>No open reports. Players can report from the button in the corner of the game, or with /report.</Empty>
          ) : (
            <ul className="divide-y divide-line">
              {openGroups.map((g) => (
                <ReportCard
                  key={g.target}
                  g={g}
                  player={byId.get(g.target)}
                  banned={banned.has(g.target)}
                  kick={kick}
                  name={name}
                  reporter={(id) => byId.get(id)}
                  open={open}
                  openReplay={openReplay}
                />
              ))}
            </ul>
          )}
        </Panel>

        {decided.length > 0 && (
          <Panel title="Recently decided">
            <ul className="divide-y divide-line">
              {decided.map((g) => {
                const r = g.reports[0]
                return (
                  <li key={g.target}>
                    <button onClick={() => open(g.target)} className="flex w-full items-center gap-3 px-4 py-2.5 text-left text-sm hover:bg-panel-2">
                      <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase ${r.status === 'confirmed' ? 'bg-bad/15 text-bad' : 'bg-line text-muted'}`}>
                        {r.status === 'confirmed' ? 'banned' : 'dismissed'}
                      </span>
                      <span className="flex-1 truncate font-medium">{name(g.target)}</span>
                      <span className="text-xs text-muted">
                        {g.reports.length} {g.reports.length === 1 ? 'report' : 'reports'} · {r.decided_by} · {r.decided_at && ago(r.decided_at)}
                      </span>
                    </button>
                  </li>
                )
              })}
            </ul>
          </Panel>
        )}
      </div>

      <Panel title="Reporters">
        {reporters.length === 0 ? (
          <Empty>Nobody has reported anyone yet.</Empty>
        ) : (
          <>
            <ul className="divide-y divide-line">
              {reporters.map((p) => {
                const t = track(p)
                const bad = t && t.of >= 3 && t.right / t.of < 0.3
                return (
                  <li key={p.user_id}>
                    <button onClick={() => open(p.user_id)} className="flex w-full items-center gap-3 px-4 py-2.5 text-left text-sm hover:bg-panel-2">
                      <span className="flex-1 truncate">{p.username || p.user_id}</span>
                      <span className="font-mono text-xs text-muted">{p.reports_made} sent</span>
                      <span className={`w-16 text-right font-mono text-xs ${bad ? 'text-bad' : t ? 'text-good' : 'text-muted'}`}>
                        {t ? `${t.right}/${t.of} right` : 'new'}
                      </span>
                    </button>
                  </li>
                )
              })}
            </ul>
            <p className="border-t border-line px-4 py-3 text-xs text-muted">
              Reports from people who've been right before count more. Banning a reported player marks their reports right, dismissing marks
              them wrong.
            </p>
          </>
        )}
      </Panel>
    </div>
  )
}

function ReportCard({
  g,
  player,
  banned,
  kick,
  name,
  reporter,
  open,
  openReplay,
}: {
  g: Group
  player: Player | undefined
  banned: boolean
  kick: number
  name: (id: number) => string
  reporter: (id: number) => Player | undefined
  open: (id: number) => void
  openReplay: (id: number) => void
}) {
  const { game } = useGame()
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState('')
  const [banning, setBanning] = useState(false)
  const [reason, setReason] = useState(`Cheating (reported for ${g.reasons[0]?.[0].toLowerCase() ?? 'cheating'})`)
  const notes = g.reports.filter((r) => r.note).slice(0, 2)

  async function run(fn: () => PromiseLike<{ error: unknown }>, done: string) {
    setBusy(true)
    setMsg('')
    const { error } = await fn()
    setBusy(false)
    setMsg(error ? errorText(error) : done)
  }

  return (
    <li className="space-y-3 p-4">
      <div className="flex items-start gap-3">
        <button onClick={() => open(g.target)} className="min-w-0 flex-1 text-left">
          <div className="flex items-center gap-2">
            <span className="truncate font-medium hover:text-accent">{name(g.target)}</span>
            {player?.shadowed && <span className="rounded bg-veil/15 px-1.5 text-[10px] font-semibold uppercase text-veil">shadowed</span>}
            {banned && <span className="rounded bg-bad/15 px-1.5 text-[10px] font-semibold uppercase text-bad">banned</span>}
          </div>
          <div className="mt-0.5 text-xs text-muted">
            {g.reports.length} {g.reports.length === 1 ? 'report' : 'reports'}, weight{' '}
            <span className={g.weight >= 2 ? 'text-warn' : ''}>{g.weight.toFixed(1)}</span> · latest {ago(g.latest)}
          </div>
        </button>
        {player && (
          <div className="w-28 shrink-0 text-right">
            <div className={`font-mono text-sm ${scoreTone(player.peak_score, kick)}`}>peak {player.peak_score.toFixed(0)}</div>
            <ScoreBar score={player.peak_score} kick={kick} />
          </div>
        )}
      </div>

      <div className="flex flex-wrap gap-1.5">
        {g.reasons.map(([r, n]) => (
          <span key={r} className="rounded-md border border-warn/30 bg-warn/10 px-2 py-0.5 text-xs text-warn">
            {r}
            {n > 1 && <span className="ml-1 font-mono">×{n}</span>}
          </span>
        ))}
      </div>

      {notes.map((r) => (
        <blockquote key={r.id} className="border-l-2 border-line pl-3 text-sm text-muted">
          "{r.note}" <span className="text-xs">— {name(r.reporter_id)}</span>
        </blockquote>
      ))}

      <div className="text-xs text-muted">
        from{' '}
        {g.reports.slice(0, 6).map((r, i) => {
          const t = track(reporter(r.reporter_id))
          return (
            <span key={r.id}>
              {i > 0 && ', '}
              <button onClick={() => open(r.reporter_id)} className="hover:text-text">
                {name(r.reporter_id)}
              </button>
              {t && <span className="font-mono"> ({t.right}/{t.of})</span>}
            </span>
          )
        })}
        {g.reports.length > 6 && ` and ${g.reports.length - 6} more`}
      </div>

      {banning ? (
        <form
          className="flex flex-wrap items-center gap-2"
          onSubmit={(e) => {
            e.preventDefault()
            run(() => supabase.rpc('admin_ban', { p_game: game, p_user_id: g.target, p_reason: reason.trim(), p_hours: null }), 'Banned. Their reporters were marked right.')
          }}
        >
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={200}
            className="min-w-48 flex-1 rounded-lg border border-line bg-panel-2 px-3 py-1.5 text-sm outline-none focus:border-bad/60"
          />
          <Button tone="danger" type="submit" disabled={busy || !reason.trim()}>
            Ban permanently
          </Button>
          <Button tone="ghost" onClick={() => setBanning(false)}>
            Cancel
          </Button>
        </form>
      ) : (
        <div className="flex flex-wrap items-center gap-2">
          {g.replay && <Button tone="accent" onClick={() => openReplay(g.replay!)}>Watch replay</Button>}
          {!banned && (
            <Button tone="danger" onClick={() => setBanning(true)} disabled={busy}>
              Ban
            </Button>
          )}
          <Button
            onClick={() =>
              run(
                () => supabase.rpc('admin_set_shadow', { p_game: game, p_user_id: g.target, p_on: !player?.shadowed }),
                player?.shadowed ? 'Shadow mode lifted.' : 'Shadowed. If they are online it takes effect within a few seconds.',
              )
            }
            disabled={busy}
          >
            {player?.shadowed ? 'Lift shadow' : 'Shadow'}
          </Button>
          <Button
            tone="ghost"
            onClick={() => run(() => supabase.rpc('admin_decide_reports', { p_game: game, p_target: g.target, p_confirm: false }), 'Dismissed.')}
            disabled={busy}
          >
            Dismiss
          </Button>
        </div>
      )}
      {msg && <div className="text-xs text-muted">{msg}</div>}
    </li>
  )
}
