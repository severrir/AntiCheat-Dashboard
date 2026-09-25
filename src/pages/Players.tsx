import { useMemo, useState } from 'react'
import type { Ban, Player } from '../lib/supabase'
import { ago, isOnline, scoreTone } from '../lib/format'
import { Dot, Empty, Panel } from '../components/ui'

type Sort = 'recent' | 'score' | 'peak' | 'flags' | 'kicks'

export function Players({ players, bans, kick, open }: { players: Player[]; bans: Ban[]; kick: number; open: (id: number) => void }) {
  const [q, setQ] = useState('')
  const [sort, setSort] = useState<Sort>('recent')
  const [onlyOnline, setOnlyOnline] = useState(false)

  const banned = useMemo(() => new Set(bans.filter((b) => b.active).map((b) => b.user_id)), [bans])

  const rows = useMemo(() => {
    const needle = q.trim().toLowerCase()
    const list = players.filter((p) => {
      if (onlyOnline && !isOnline(p.last_seen)) return false
      if (!needle) return true
      return p.username.toLowerCase().includes(needle) || String(p.user_id).includes(needle)
    })
    const by: Record<Sort, (a: Player, b: Player) => number> = {
      recent: (a, b) => b.last_seen.localeCompare(a.last_seen),
      score: (a, b) => b.trust_score - a.trust_score,
      peak: (a, b) => b.peak_score - a.peak_score,
      flags: (a, b) => b.total_flags - a.total_flags,
      kicks: (a, b) => b.kicks - a.kicks,
    }
    return list.sort(by[sort])
  }, [players, q, sort, onlyOnline])

  return (
    <Panel
      title={`Players · ${rows.length}`}
      right={
        <div className="flex flex-wrap items-center gap-2">
          <label className="flex items-center gap-2 text-xs text-muted">
            <input type="checkbox" checked={onlyOnline} onChange={(e) => setOnlyOnline(e.target.checked)} className="accent-cyan-400" />
            online only
          </label>
          <select value={sort} onChange={(e) => setSort(e.target.value as Sort)} className="rounded-lg border border-line bg-panel-2 px-2 py-1 text-xs">
            <option value="recent">Last seen</option>
            <option value="score">Score</option>
            <option value="peak">Peak score</option>
            <option value="flags">Flags</option>
            <option value="kicks">Kicks</option>
          </select>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search name or id"
            maxLength={40}
            className="w-44 rounded-lg border border-line bg-panel-2 px-3 py-1 text-sm outline-none focus:border-accent/60"
          />
        </div>
      }
    >
      {rows.length === 0 ? (
        <Empty>No players match.</Empty>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-[11px] uppercase tracking-[0.12em] text-muted">
              <tr className="border-b border-line">
                <th className="px-4 py-2 font-medium">Player</th>
                <th className="px-4 py-2 text-right font-medium">Score</th>
                <th className="px-4 py-2 text-right font-medium">Peak</th>
                <th className="px-4 py-2 text-right font-medium">Flags</th>
                <th className="px-4 py-2 text-right font-medium">Kicks</th>
                <th className="px-4 py-2 text-right font-medium">Last seen</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {rows.map((p) => (
                <tr key={p.user_id} onClick={() => open(p.user_id)} className="cursor-pointer hover:bg-panel-2">
                  <td className="px-4 py-2.5">
                    <div className="flex items-center gap-3">
                      <Dot on={isOnline(p.last_seen)} />
                      <div className="min-w-0">
                        <div className="flex items-center gap-2 font-medium">
                          <span className="truncate">{p.username || '—'}</span>
                          {banned.has(p.user_id) && <span className="rounded bg-bad/15 px-1.5 text-[10px] font-semibold uppercase text-bad">banned</span>}
                        </div>
                        <div className="font-mono text-xs text-muted">{p.user_id}</div>
                      </div>
                    </div>
                  </td>
                  <td className={`px-4 py-2.5 text-right font-mono ${scoreTone(p.trust_score, kick)}`}>{p.trust_score.toFixed(1)}</td>
                  <td className={`px-4 py-2.5 text-right font-mono ${scoreTone(p.peak_score, kick)}`}>{p.peak_score.toFixed(1)}</td>
                  <td className="px-4 py-2.5 text-right font-mono">{p.total_flags}</td>
                  <td className="px-4 py-2.5 text-right font-mono">{p.kicks}</td>
                  <td className="px-4 py-2.5 text-right text-xs text-muted">{ago(p.last_seen)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  )
}
