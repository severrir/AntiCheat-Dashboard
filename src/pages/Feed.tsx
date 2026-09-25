import { useMemo, useState } from 'react'
import type { Flag, Player } from '../lib/supabase'
import { CHECK_COLORS, ago } from '../lib/format'
import { CheckTag, Empty, Panel } from '../components/ui'
import { Context } from '../components/Context'

export function Feed({ flags, players, fresh, open }: { flags: Flag[]; players: Player[]; fresh: Set<number>; open: (id: number) => void }) {
  const [check, setCheck] = useState<string>('all')
  const names = useMemo(() => new Map(players.map((p) => [p.user_id, p.username])), [players])
  const rows = check === 'all' ? flags : flags.filter((f) => f.check_name === check)

  return (
    <Panel
      title="Live flag feed"
      right={
        <div className="flex flex-wrap gap-1">
          {['all', ...Object.keys(CHECK_COLORS)].map((c) => (
            <button
              key={c}
              onClick={() => setCheck(c)}
              className={`rounded-md px-2 py-0.5 text-xs transition ${check === c ? 'bg-accent/15 text-accent' : 'text-muted hover:text-text'}`}
            >
              {c}
            </button>
          ))}
        </div>
      }
    >
      {rows.length === 0 ? (
        <Empty>Quiet. Nothing flagged{check !== 'all' ? ` for ${check}` : ''}.</Empty>
      ) : (
        <ul className="divide-y divide-line">
          {rows.map((f) => (
            <li key={f.id} className={fresh.has(f.id) ? 'flash' : ''}>
              <button onClick={() => open(f.user_id)} className="grid w-full gap-2 px-4 py-3 text-left hover:bg-panel-2 md:grid-cols-[110px_180px_1fr_auto] md:items-center">
                <CheckTag name={f.check_name} />
                <div className="min-w-0">
                  <div className="truncate font-medium">{names.get(f.user_id) || f.user_id}</div>
                  <div className="font-mono text-[11px] text-muted">
                    +{f.severity.toFixed(0)} · score {f.score_after.toFixed(0)}
                    {f.hits > 1 && ` · ×${f.hits}`}
                  </div>
                </div>
                <Context ctx={f.context} />
                <span className="font-mono text-xs text-muted">{ago(f.created_at)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  )
}
