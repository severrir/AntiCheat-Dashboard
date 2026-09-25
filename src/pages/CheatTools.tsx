import { useEffect, useMemo, useState } from 'react'
import { supabase, type Action, type Player } from '../lib/supabase'
import { CHECK_COLORS, ago } from '../lib/format'
import { Empty, Panel } from '../components/ui'

type Kick = Pick<Action, 'id' | 'user_id' | 'signature' | 'replay_id' | 'created_at' | 'reason'>
type Group = { sig: string[]; kicks: Kick[] }

const SIMILAR = 0.6

function jaccard(a: Set<string>, b: Set<string>) {
  let inter = 0
  for (const x of a) if (b.has(x)) inter++
  return inter / Math.max(1, a.size + b.size - inter)
}

// kicks whose fingerprints overlap enough end up in the same group. union-find keeps it linear-ish
function cluster(kicks: Kick[]): Group[] {
  const sets = kicks.map((k) => new Set(k.signature ?? []))
  const parent = kicks.map((_, i) => i)
  const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])))
  for (let i = 0; i < kicks.length; i++) {
    if (sets[i].size === 0) continue
    for (let j = i + 1; j < kicks.length; j++) {
      if (sets[j].size && jaccard(sets[i], sets[j]) >= SIMILAR) parent[find(i)] = find(j)
    }
  }
  const groups = new Map<number, Kick[]>()
  kicks.forEach((k, i) => {
    if (!sets[i].size) return
    const root = find(i)
    if (!groups.has(root)) groups.set(root, [])
    groups.get(root)!.push(k)
  })
  return [...groups.values()]
    .map((list) => {
      // the traits most of the group share
      const counts = new Map<string, number>()
      for (const k of list) for (const s of new Set(k.signature ?? [])) counts.set(s, (counts.get(s) ?? 0) + 1)
      const sig = [...counts.entries()].filter(([, n]) => n >= Math.ceil(list.length / 2)).sort((a, b) => b[1] - a[1]).map(([s]) => s)
      return { sig, kicks: list.sort((a, b) => b.created_at.localeCompare(a.created_at)) }
    })
    .sort((a, b) => b.kicks.length - a.kicks.length)
}

export function CheatTools({ players, open, openReplay }: { players: Player[]; open: (id: number) => void; openReplay: (id: number) => void }) {
  const [kicks, setKicks] = useState<Kick[] | null>(null)
  const names = useMemo(() => new Map(players.map((p) => [p.user_id, p.username])), [players])

  useEffect(() => {
    const since = new Date(Date.now() - 30 * 86_400_000).toISOString()
    supabase
      .from('actions')
      .select('id, user_id, signature, replay_id, created_at, reason')
      .eq('action', 'kick')
      .not('signature', 'is', null)
      .gte('created_at', since)
      .order('created_at', { ascending: false })
      .limit(800)
      .then(({ data }) => setKicks(data ?? []))
  }, [])

  const groups = useMemo(() => (kicks ? cluster(kicks) : []), [kicks])

  return (
    <div className="space-y-5">
      <p className="max-w-3xl text-sm text-muted">
        Every kick leaves a fingerprint: which checks fired, how, and how hard. Kicks with overlapping fingerprints get grouped
        together. A big group usually means one exploit script doing the rounds.
      </p>
      {kicks === null ? (
        <Panel><Empty>Loading…</Empty></Panel>
      ) : groups.length === 0 ? (
        <Panel><Empty>No kicks with fingerprints in the last 30 days.</Empty></Panel>
      ) : (
        groups.map((g, i) => (
          <Panel
            key={i}
            title={g.kicks.length > 1 ? `Likely the same tool · ${g.kicks.length} kicks` : 'One-off'}
            right={<span className="text-xs text-muted">latest {ago(g.kicks[0].created_at)}</span>}
          >
            <div className="flex flex-wrap gap-1.5 border-b border-line px-4 py-3">
              {g.sig.map((s) => {
                const check = s.split(':')[0]
                const color = CHECK_COLORS[check] ?? '#94a3b8'
                return (
                  <span key={s} className="rounded-md border px-2 py-0.5 font-mono text-[11px]" style={{ borderColor: `${color}40`, color, background: `${color}12` }}>
                    {s}
                  </span>
                )
              })}
            </div>
            <ul className="divide-y divide-line">
              {g.kicks.slice(0, 12).map((k) => (
                <li key={k.id} className="flex items-center gap-3 px-4 py-2 text-sm">
                  <button onClick={() => open(k.user_id)} className="font-medium hover:text-accent">
                    {names.get(k.user_id) || k.user_id}
                  </button>
                  <span className="truncate text-xs text-muted">{k.reason}</span>
                  <span className="ml-auto text-xs text-muted">{ago(k.created_at)}</span>
                  {k.replay_id && (
                    <button onClick={() => openReplay(k.replay_id!)} className="text-xs text-accent hover:underline">
                      replay
                    </button>
                  )}
                </li>
              ))}
              {g.kicks.length > 12 && <li className="px-4 py-2 text-xs text-muted">+{g.kicks.length - 12} more</li>}
            </ul>
          </Panel>
        ))
      )}
    </div>
  )
}
