import { useMemo } from 'react'
import type { Ban, Flag, Player } from '../lib/supabase'
import type { Counts } from '../lib/useConsole'
import { CHECK_COLORS, ago, isOnline, scoreTone } from '../lib/format'
import { CheckTag, Empty, Panel, ScoreBar, Stat } from '../components/ui'

type Props = {
  players: Player[]
  flags: Flag[]
  bans: Ban[]
  counts: Counts
  kick: number
  fresh: Set<number>
  open: (id: number) => void
}

export function Overview({ players, flags, bans, counts, kick, fresh, open }: Props) {
  const online = players.filter((p) => isOnline(p.last_seen))
  const suspects = [...online].sort((a, b) => b.trust_score - a.trust_score).slice(0, 12)
  const activeBans = bans.filter((b) => b.active).length

  const breakdown = useMemo(() => {
    const cutoff = Date.now() - 86_400_000
    const totals: Record<string, number> = {}
    for (const f of flags) {
      if (new Date(f.created_at).getTime() < cutoff) continue
      totals[f.check_name] = (totals[f.check_name] ?? 0) + f.hits
    }
    const sum = Object.values(totals).reduce((a, b) => a + b, 0)
    return { rows: Object.entries(totals).sort((a, b) => b[1] - a[1]), sum }
  }, [flags])

  const names = useMemo(() => new Map(players.map((p) => [p.user_id, p.username])), [players])

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Stat label="Online now" value={online.length} tone="text-good" />
        <Stat label="Flags · 24h" value={counts.flags24} tone="text-accent" />
        <Stat label="Kicks · 24h" value={counts.kicks24} tone={counts.kicks24 ? 'text-warn' : 'text-text'} />
        <Stat label="Active bans" value={activeBans} tone={activeBans ? 'text-bad' : 'text-text'} />
      </div>

      <div className="grid gap-5 xl:grid-cols-[1.4fr_1fr]">
        <Panel title="Live suspects" right={<span className="text-xs text-muted">online, by trust score</span>}>
          {suspects.length === 0 ? (
            <Empty>Nobody online right now.</Empty>
          ) : (
            <ul className="divide-y divide-line">
              {suspects.map((p) => (
                <li key={p.user_id}>
                  <button onClick={() => open(p.user_id)} className="grid w-full grid-cols-[1fr_120px_64px] items-center gap-4 px-4 py-3 text-left hover:bg-panel-2">
                    <div className="min-w-0">
                      <div className="truncate font-medium">{p.username || p.user_id}</div>
                      <div className="font-mono text-xs text-muted">{p.user_id}</div>
                    </div>
                    <ScoreBar score={p.trust_score} kick={kick} />
                    <div className={`text-right font-mono text-sm ${scoreTone(p.trust_score, kick)}`}>{p.trust_score.toFixed(1)}</div>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Panel>

        <Panel title="What's firing · 24h">
          {breakdown.sum === 0 ? (
            <Empty>No flags in the last 24 hours.</Empty>
          ) : (
            <div className="space-y-3 p-4">
              <div className="flex h-2.5 overflow-hidden rounded-full bg-line">
                {breakdown.rows.map(([name, n]) => (
                  <div key={name} style={{ width: `${(n / breakdown.sum) * 100}%`, background: CHECK_COLORS[name] ?? CHECK_COLORS.Custom }} />
                ))}
              </div>
              {breakdown.rows.map(([name, n]) => (
                <div key={name} className="flex items-center justify-between text-sm">
                  <CheckTag name={name} />
                  <span className="font-mono text-muted">{n}</span>
                </div>
              ))}
            </div>
          )}
        </Panel>
      </div>

      <Panel title="Latest flags">
        {flags.length === 0 ? (
          <Empty>Nothing yet. Flags show up here the moment a server syncs.</Empty>
        ) : (
          <ul className="divide-y divide-line">
            {flags.slice(0, 10).map((f) => (
              <li key={f.id} className={fresh.has(f.id) ? 'flash' : ''}>
                <button onClick={() => open(f.user_id)} className="grid w-full grid-cols-[auto_1fr_auto] items-center gap-4 px-4 py-2.5 text-left hover:bg-panel-2">
                  <CheckTag name={f.check_name} />
                  <span className="truncate text-sm">
                    <span className="font-medium">{names.get(f.user_id) || f.user_id}</span>
                    <span className="ml-2 text-muted">{String(f.context?.kind ?? f.context?.stat ?? '')}</span>
                  </span>
                  <span className="font-mono text-xs text-muted">{ago(f.created_at)}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </Panel>
    </div>
  )
}
