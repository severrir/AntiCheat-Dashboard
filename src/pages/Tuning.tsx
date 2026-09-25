import { useEffect, useMemo, useState } from 'react'
import { supabase, type Ban, type Config, type Player } from '../lib/supabase'
import { DEFAULTS } from '../lib/thresholds'
import { errorText } from '../lib/format'
import { Button, Empty, Panel } from '../components/ui'

type Suggestion = { key: string; current: number; suggested: number; reason: string }
type Row = { user_id: number; check_name: string; raw: number | null; severity: number; created_at: string }

const CHECKS = ['Movement', 'Character', 'Remote', 'Statistical', 'Timing', 'Honeypot', 'Client', 'Combat']

async function push(config: Config | null, patch: Record<string, number>) {
  const next = { ...DEFAULTS, ...(config?.thresholds ?? {}), ...patch }
  const diff = Object.fromEntries(Object.entries(next).filter(([k, v]) => v !== DEFAULTS[k]))
  return supabase.rpc('admin_set_thresholds', { p_thresholds: diff })
}

export function Tuning({ config, players, bans, reload }: { config: Config | null; players: Player[]; bans: Ban[]; reload: () => void }) {
  return (
    <div className="space-y-5">
      <Suggestions config={config} reload={reload} />
      <WhatIf config={config} players={players} bans={bans} reload={reload} />
    </div>
  )
}

function Suggestions({ config, reload }: { config: Config | null; reload: () => void }) {
  const [data, setData] = useState<{ labeled: number; needed: number; suggestions: Suggestion[] } | null>(null)
  const [msg, setMsg] = useState('')

  const load = () => supabase.rpc('tuning_suggestions').then(({ data }) => setData(data))
  useEffect(() => {
    load()
  }, [])

  async function apply(s: Suggestion) {
    const { error } = await push(config, { [s.key]: s.suggested })
    setMsg(error ? errorText(error) : `${s.key} set to ${s.suggested}. Servers pick it up within 20s.`)
    reload()
    load()
  }

  return (
    <Panel title="Learned from your decisions">
      <div className="p-4">
        <p className="mb-3 max-w-3xl text-sm text-muted">
          Every ban you keep is a confirmed cheater, and every unban or approved appeal is a mistake. The system checks which checks
          were right and which were noisy, and suggests changes.
        </p>
        {!data ? (
          <p className="text-sm text-muted">Loading…</p>
        ) : data.labeled < data.needed ? (
          <div className="rounded-lg bg-panel-2 p-3 text-sm">
            Needs <b>{data.needed}</b> decided kicks to learn from, has <b>{data.labeled}</b>. Ban confirmed cheaters and unban
            mistakes from the dashboard or Discord and suggestions will show up here.
            <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-line">
              <div className="h-full bg-accent" style={{ width: `${(data.labeled / data.needed) * 100}%` }} />
            </div>
          </div>
        ) : data.suggestions.length === 0 ? (
          <p className="text-sm text-good">Based on {data.labeled} decisions, the current settings look right. Nothing to change.</p>
        ) : (
          <ul className="space-y-2">
            {data.suggestions.map((s) => (
              <li key={s.key} className="flex flex-wrap items-center gap-3 rounded-lg bg-panel-2 p-3">
                <span className="font-mono text-sm">{s.key}</span>
                <span className="font-mono text-sm text-muted">
                  {s.current} → <span className="text-accent">{s.suggested}</span>
                </span>
                <span className="min-w-60 flex-1 text-xs text-muted">{s.reason}</span>
                <Button tone="accent" onClick={() => apply(s)}>Apply</Button>
              </li>
            ))}
          </ul>
        )}
        {msg && <p className="mt-2 text-sm text-muted">{msg}</p>}
      </div>
    </Panel>
  )
}

type Settings = { KickScore: number; HalfLife: number; MinCorroboratingChecks: number } & Record<string, number>

// replays the last 30 days of real flags through the same scoring rules the game uses
function simulate(rows: Row[], s: Settings, oldWeights: Record<string, number>) {
  const byUser = new Map<number, Row[]>()
  for (const r of rows) {
    if (!byUser.has(r.user_id)) byUser.set(r.user_id, [])
    byUser.get(r.user_id)!.push(r)
  }
  const kicked = new Set<number>()
  for (const [uid, list] of byUser) {
    let score = 0
    let at = 0
    const parts = new Map<string, { v: number; at: number }>()
    const decay = (v: number, since: number, now: number) => v * 0.5 ** ((now - since) / Math.max(s.HalfLife, 1))
    for (const r of list) {
      const now = new Date(r.created_at).getTime() / 1000
      const raw = r.raw ?? r.severity / (oldWeights[`Weight${r.check_name}`] || 1)
      const amount = raw * (s[`Weight${r.check_name}`] ?? 1)
      if (amount <= 0) continue
      score = decay(score, at, now) + amount
      at = now
      const p = parts.get(r.check_name)
      parts.set(r.check_name, { v: (p ? decay(p.v, p.at, now) : 0) + amount, at: now })
      if (score < s.KickScore) continue

      const breakdown = [...parts.entries()].map(([check, p]) => ({ check, value: decay(p.v, p.at, now) })).sort((a, b) => b.value - a.value)
      const proof = breakdown.some((b) => b.check === 'Honeypot' && b.value >= s.KickScore * 0.5)
      const distinct = breakdown.filter((b) => b.value >= s.KickScore * 0.1).length
      // movement proves itself through forensic replay in game, assume it would confirm
      if (proof || breakdown[0].check === 'Movement' || distinct >= s.MinCorroboratingChecks) {
        kicked.add(uid)
        break
      }
    }
  }
  return kicked
}

function WhatIf({ config, players, bans, reload }: { config: Config | null; players: Player[]; bans: Ban[]; reload: () => void }) {
  const current = useMemo(() => ({ ...DEFAULTS, ...(config?.thresholds ?? {}) }) as Settings, [config])
  const [s, setS] = useState<Settings>(current)
  const [rows, setRows] = useState<Row[] | null>(null)
  const [actual, setActual] = useState<Set<number>>(new Set())
  const [msg, setMsg] = useState('')

  useEffect(() => setS(current), [current])

  useEffect(() => {
    const since = new Date(Date.now() - 30 * 86_400_000).toISOString()
    ;(async () => {
      const { data: kicks } = await supabase.from('actions').select('user_id').eq('action', 'kick').gte('created_at', since).limit(2000)
      setActual(new Set((kicks ?? []).map((k) => k.user_id)))
      const { data: suspects } = await supabase.from('players').select('user_id').or('kicks.gt.0,peak_score.gte.20').gte('last_seen', since).limit(400)
      const ids = (suspects ?? []).map((p) => p.user_id)
      if (ids.length === 0) {
        setRows([])
        return
      }
      const { data } = await supabase
        .from('flags')
        .select('user_id, check_name, raw, severity, created_at')
        .in('user_id', ids)
        .gte('created_at', since)
        .order('created_at')
        .limit(20000)
      setRows((data as Row[]) ?? [])
    })()
  }, [])

  const names = useMemo(() => new Map(players.map((p) => [p.user_id, p.username])), [players])
  const banned = useMemo(() => new Set(bans.filter((b) => b.active).map((b) => b.user_id)), [bans])
  const unbanned = useMemo(() => new Set(bans.filter((b) => !b.active).map((b) => b.user_id)), [bans])

  const result = useMemo(() => {
    if (!rows) return null
    const now = simulate(rows, current, current)
    const next = simulate(rows, s, current)
    return {
      now,
      next,
      gained: [...next].filter((u) => !now.has(u)),
      lost: [...now].filter((u) => !next.has(u)),
    }
  }, [rows, s, current])

  const slider = (key: string, label: string, min: number, max: number, step: number) => (
    <label key={key} className="grid grid-cols-[140px_1fr_52px] items-center gap-3 text-sm">
      <span className={s[key] !== current[key] ? 'text-accent' : ''}>{label}</span>
      <input type="range" min={min} max={max} step={step} value={s[key]} onChange={(e) => setS({ ...s, [key]: Number(e.target.value) })} className="accent-cyan-400" />
      <span className="text-right font-mono text-xs">{s[key]}</span>
    </label>
  )

  const changed = Object.keys(s).some((k) => s[k] !== current[k])

  async function apply() {
    const patch = Object.fromEntries(Object.entries(s).filter(([k, v]) => v !== current[k]))
    const { error } = await push(config, patch)
    setMsg(error ? errorText(error) : 'Pushed to every server.')
    reload()
  }

  const who = (u: number) => (
    <li key={u} className="flex items-center justify-between py-1 text-sm">
      <span>{names.get(u) || u}</span>
      <span className="text-xs">
        {banned.has(u) ? <span className="text-bad">banned, real cheater</span> : unbanned.has(u) ? <span className="text-good">was unbanned, innocent</span> : <span className="text-muted">undecided</span>}
      </span>
    </li>
  )

  return (
    <Panel title="What if…" right={<span className="text-xs text-muted">last 30 days of real flags, replayed</span>}>
      <div className="grid gap-6 p-4 lg:grid-cols-2">
        <div className="space-y-2">
          {slider('KickScore', 'Kick score', 40, 300, 5)}
          {slider('HalfLife', 'Half-life (s)', 10, 180, 5)}
          {slider('MinCorroboratingChecks', 'Checks that agree', 1, 4, 1)}
          <div className="pt-2 text-[11px] uppercase tracking-[0.14em] text-muted">Weights</div>
          {CHECKS.map((c) => slider(`Weight${c}`, c, 0, 3, 0.1))}
          <div className="flex gap-2 pt-2">
            <Button tone="accent" onClick={apply} disabled={!changed}>Use these settings</Button>
            <Button onClick={() => setS(current)} disabled={!changed}>Reset</Button>
          </div>
          {msg && <p className="text-sm text-muted">{msg}</p>}
        </div>
        <div>
          {!result ? (
            <Empty>Loading flag history…</Empty>
          ) : rows && rows.length === 0 ? (
            <Empty>No flag history yet. Once players get flagged, you can test settings against it here.</Empty>
          ) : (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-3">
                <div className="rounded-lg bg-panel-2 p-3">
                  <div className="text-[10px] uppercase tracking-[0.14em] text-muted">Kicked for real</div>
                  <div className="font-mono text-2xl">{actual.size}</div>
                </div>
                <div className="rounded-lg bg-panel-2 p-3">
                  <div className="text-[10px] uppercase tracking-[0.14em] text-muted">Current rules</div>
                  <div className="font-mono text-2xl">{result.now.size}</div>
                </div>
                <div className="rounded-lg bg-panel-2 p-3">
                  <div className="text-[10px] uppercase tracking-[0.14em] text-muted">With your changes</div>
                  <div className={`font-mono text-2xl ${result.next.size > result.now.size ? 'text-warn' : result.next.size < result.now.size ? 'text-accent' : ''}`}>
                    {result.next.size}
                  </div>
                </div>
              </div>
              <div>
                <div className="mb-1 flex items-center gap-2 text-sm font-medium">Would now be kicked <span className="rounded bg-warn/15 px-1.5 font-mono text-xs text-warn">+{result.gained.length}</span></div>
                {result.gained.length ? <ul className="divide-y divide-line">{result.gained.slice(0, 15).map(who)}</ul> : <p className="text-xs text-muted">Nobody new.</p>}
              </div>
              <div>
                <div className="mb-1 flex items-center gap-2 text-sm font-medium">Would no longer be kicked <span className="rounded bg-accent/15 px-1.5 font-mono text-xs text-accent">−{result.lost.length}</span></div>
                {result.lost.length ? <ul className="divide-y divide-line">{result.lost.slice(0, 15).map(who)}</ul> : <p className="text-xs text-muted">Nobody.</p>}
              </div>
            </div>
          )}
        </div>
      </div>
    </Panel>
  )
}
