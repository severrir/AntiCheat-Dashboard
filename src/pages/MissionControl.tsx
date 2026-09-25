import { useEffect, useMemo, useRef, useState } from 'react'
import { loadMap, supabase, type MapPart, type Player, type Server } from '../lib/supabase'
import { CHECK_COLORS, ago } from '../lib/format'
import { Empty, Panel } from '../components/ui'

type LivePlayer = { id: string; name: string; score: number; x: number | null; y: number | null; z: number | null; yaw: number; admin?: boolean }
type Pulse = { server: string; place: string | null; threat: number; island: boolean; t: number; players: LivePlayer[] }

export const THREAT = [
  { name: 'Calm', color: '#34d399' },
  { name: 'Watch', color: '#22d3ee' },
  { name: 'Alert', color: '#fbbf24' },
  { name: 'Red', color: '#f43f5e' },
]

type Props = { servers: Server[]; players: Player[]; kick: number; open: (id: number) => void }

const mapCache = new Map<number, Promise<{ parts: MapPart[]; bounds: number[] | null } | null>>()
function cachedMap(place: number) {
  if (!mapCache.has(place)) mapCache.set(place, loadMap(place))
  return mapCache.get(place)!
}

export function MissionControl({ servers, players, kick, open }: Props) {
  const [pulses, setPulses] = useState<Record<string, Pulse>>({})
  const [selected, setSelected] = useState<string | null>(null)
  const [mode, setMode] = useState<'live' | 'heat'>('live')
  const [heatDays, setHeatDays] = useState(7)

  // private broadcast channel, the server only lets approved admins subscribe
  useEffect(() => {
    let channel: ReturnType<typeof supabase.channel> | null = null
    let cancelled = false
    ;(async () => {
      await supabase.realtime.setAuth()
      if (cancelled) return
      channel = supabase
        .channel('mission', { config: { private: true } })
        .on('broadcast', { event: 'pulse' }, ({ payload }) => {
          const p = payload as Pulse
          if (p?.server) setPulses((prev) => ({ ...prev, [p.server]: { ...p, t: Date.now() } }))
        })
        .subscribe()
    })()
    return () => {
      cancelled = true
      if (channel) supabase.removeChannel(channel)
    }
  }, [])

  const list = useMemo(() => {
    const byId = new Map(servers.map((s) => [s.server_id, s]))
    for (const p of Object.values(pulses)) {
      if (!byId.has(p.server) && Date.now() - p.t < 30_000) {
        byId.set(p.server, {
          server_id: p.server, place_id: p.place ? Number(p.place) : null, players: p.players.length,
          threat: p.threat, island: p.island, last_seen: new Date(p.t).toISOString(),
        })
      }
    }
    return [...byId.values()].sort((a, b) => b.threat - a.threat || b.players - a.players)
  }, [servers, pulses])

  const current = list.find((s) => s.server_id === selected) ?? list[0]
  const pulse = current ? pulses[current.server_id] : undefined
  const placeId = current?.place_id ?? (players.length ? null : null)

  return (
    <div className="grid gap-5 xl:grid-cols-[320px_1fr]">
      <Panel title={`Live servers · ${list.length}`}>
        {list.length === 0 ? (
          <Empty>No servers running right now.</Empty>
        ) : (
          <ul className="divide-y divide-line">
            {list.map((s) => {
              const t = THREAT[s.threat] ?? THREAT[0]
              const live = pulses[s.server_id]
              return (
                <li key={s.server_id}>
                  <button
                    onClick={() => setSelected(s.server_id)}
                    className={`w-full px-4 py-3 text-left hover:bg-panel-2 ${current?.server_id === s.server_id ? 'bg-panel-2' : ''}`}
                  >
                    <div className="flex items-center justify-between">
                      <span className="font-mono text-xs text-muted">{s.server_id.slice(0, 13)}</span>
                      <span className="rounded px-2 py-0.5 text-[11px] font-semibold" style={{ color: t.color, background: `${t.color}1f` }}>
                        {t.name}
                      </span>
                    </div>
                    <div className="mt-1 flex items-center gap-2 text-sm">
                      <span className="font-medium">{s.players} players</span>
                      {s.island && <span className="rounded bg-bad/15 px-1.5 text-[10px] font-semibold uppercase text-bad">cheater island</span>}
                      <span className="ml-auto text-xs text-muted">{live ? 'live' : ago(s.last_seen)}</span>
                    </div>
                  </button>
                </li>
              )
            })}
          </ul>
        )}
      </Panel>

      <Panel
        title={mode === 'live' ? 'Radar' : 'Cheat heatmap'}
        right={
          <div className="flex items-center gap-1">
            {(['live', 'heat'] as const).map((m) => (
              <button
                key={m}
                onClick={() => setMode(m)}
                className={`rounded-md px-2.5 py-1 text-xs ${mode === m ? 'bg-accent/15 text-accent' : 'text-muted hover:text-text'}`}
              >
                {m === 'live' ? 'Live radar' : 'Heatmap'}
              </button>
            ))}
            {mode === 'heat' && (
              <select value={heatDays} onChange={(e) => setHeatDays(Number(e.target.value))} className="ml-2 rounded border border-line bg-panel-2 px-1.5 py-0.5 text-xs">
                <option value={1}>24h</option>
                <option value={7}>7 days</option>
                <option value={30}>30 days</option>
              </select>
            )}
          </div>
        }
      >
        <Radar
          key={`${current?.server_id}-${mode}`}
          placeId={placeId}
          pulse={mode === 'live' ? pulse : undefined}
          heat={mode === 'heat' ? heatDays : 0}
          kick={kick}
          open={open}
        />
      </Panel>
    </div>
  )
}

type HeatPoint = { x: number; z: number; check: string; hits: number }

function Radar({ placeId, pulse, heat, kick, open }: { placeId: number | null; pulse?: Pulse; heat: number; kick: number; open: (id: number) => void }) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const [map, setMap] = useState<{ parts: MapPart[]; bounds: number[] | null } | null>(null)
  const [points, setPoints] = useState<HeatPoint[]>([])
  const view = useRef({ cx: 0, cz: 0, scale: 1, ready: false })
  const prev = useRef(new Map<string, { x: number; z: number }>())
  const pulseAt = useRef(0)
  const dots = useRef<{ id: number; x: number; y: number }[]>([])

  useEffect(() => {
    if (placeId) cachedMap(placeId).then(setMap)
  }, [placeId])

  useEffect(() => {
    if (!heat || !placeId) return
    const since = new Date(Date.now() - heat * 86_400_000).toISOString()
    supabase
      .from('flags')
      .select('pos_x, pos_z, check_name, hits')
      .eq('place_id', placeId)
      .not('pos_x', 'is', null)
      .gte('created_at', since)
      .limit(5000)
      .then(({ data }) =>
        setPoints((data ?? []).map((f) => ({ x: f.pos_x as number, z: f.pos_z as number, check: f.check_name, hits: f.hits }))),
      )
  }, [heat, placeId])

  // remember where everyone was, so the dots glide to the new spot instead of jumping
  const lastPulse = useRef<Pulse | undefined>(undefined)
  if (pulse !== lastPulse.current) {
    if (lastPulse.current) {
      const m = new Map<string, { x: number; z: number }>()
      for (const p of lastPulse.current.players) if (p.x !== null && p.z !== null) m.set(p.id, { x: p.x, z: p.z })
      prev.current = m
    }
    lastPulse.current = pulse
    pulseAt.current = performance.now()
  }

  useEffect(() => {
    const el = canvas.current
    if (!el) return
    const ctx = el.getContext('2d')!
    let raf = 0
    let drag: { x: number; y: number } | null = null

    const fit = () => {
      const w = el.clientWidth, h = el.clientHeight
      el.width = w * devicePixelRatio
      el.height = h * devicePixelRatio
      ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0)
      if (!view.current.ready) {
        let b = map?.bounds
        if (!b && pulse?.players.length) {
          const xs = pulse.players.flatMap((p) => (p.x !== null ? [p.x] : []))
          const zs = pulse.players.flatMap((p) => (p.z !== null ? [p.z] : []))
          if (xs.length) b = [Math.min(...xs) - 50, 0, Math.min(...zs) - 50, Math.max(...xs) + 50, 0, Math.max(...zs) + 50]
        }
        if (!b && points.length) {
          b = [Math.min(...points.map((p) => p.x)), 0, Math.min(...points.map((p) => p.z)), Math.max(...points.map((p) => p.x)), 0, Math.max(...points.map((p) => p.z))]
        }
        if (b) {
          view.current.cx = (b[0] + b[3]) / 2
          view.current.cz = (b[2] + b[5]) / 2
          view.current.scale = Math.min(w / Math.max(b[3] - b[0], 50), h / Math.max(b[5] - b[2], 50)) * 0.9
          view.current.ready = true
        }
      }
    }
    fit()
    const observer = new ResizeObserver(fit)
    observer.observe(el)

    const sorted = (map?.parts ?? []).slice().sort((a, b) => a[1] + a[4] / 2 - (b[1] + b[4] / 2))

    const draw = (now: number) => {
      const w = el.clientWidth, h = el.clientHeight
      const { cx, cz, scale } = view.current
      const sx = (x: number) => (x - cx) * scale + w / 2
      const sy = (z: number) => (z - cz) * scale + h / 2
      ctx.fillStyle = '#07090d'
      ctx.fillRect(0, 0, w, h)

      // radar rings
      ctx.strokeStyle = 'rgba(34,211,238,0.06)'
      for (let r = 80; r < Math.max(w, h); r += 80) {
        ctx.beginPath()
        ctx.arc(w / 2, h / 2, r, 0, Math.PI * 2)
        ctx.stroke()
      }

      for (const p of sorted) {
        const c = p[9]
        ctx.save()
        ctx.translate(sx(p[0]), sy(p[2]))
        ctx.rotate(-p[7])
        ctx.fillStyle = `rgba(${(c >> 16) & 255},${(c >> 8) & 255},${c & 255},0.28)`
        ctx.strokeStyle = 'rgba(29,37,49,0.9)'
        const pw = p[3] * scale, ph = p[5] * scale
        ctx.fillRect(-pw / 2, -ph / 2, pw, ph)
        if (pw > 6 && ph > 6) ctx.strokeRect(-pw / 2, -ph / 2, pw, ph)
        ctx.restore()
      }

      if (heat) {
        ctx.globalCompositeOperation = 'lighter'
        for (const p of points) {
          const r = Math.max(10, 5 * scale) * Math.min(3, 1 + Math.log2(p.hits))
          const g = ctx.createRadialGradient(sx(p.x), sy(p.z), 0, sx(p.x), sy(p.z), r)
          const col = CHECK_COLORS[p.check] ?? '#f43f5e'
          g.addColorStop(0, `${col}66`)
          g.addColorStop(1, `${col}00`)
          ctx.fillStyle = g
          ctx.fillRect(sx(p.x) - r, sy(p.z) - r, r * 2, r * 2)
        }
        ctx.globalCompositeOperation = 'source-over'
      }

      dots.current = []
      if (pulse) {
        const k = Math.min(1, (now - pulseAt.current) / 5000)
        for (const p of pulse.players) {
          if (p.x === null || p.z === null) continue
          const from = prev.current.get(p.id)
          const x = from ? from.x + (p.x - from.x) * k : p.x
          const z = from ? from.z + (p.z - from.z) * k : p.z
          const X = sx(x), Y = sy(z)
          const ratio = p.score / Math.max(kick, 1)
          const col = p.admin ? '#a78bfa' : ratio >= 1 ? '#f43f5e' : ratio >= 0.5 ? '#fbbf24' : ratio > 0.05 ? '#22d3ee' : '#34d399'
          if (ratio >= 0.5) {
            // suspects pulse
            const phase = (now / 900) % 1
            ctx.strokeStyle = col
            ctx.globalAlpha = 1 - phase
            ctx.beginPath()
            ctx.arc(X, Y, 6 + phase * 18, 0, Math.PI * 2)
            ctx.stroke()
            ctx.globalAlpha = 1
          }
          ctx.fillStyle = col
          ctx.beginPath()
          ctx.arc(X, Y, 5, 0, Math.PI * 2)
          ctx.fill()
          ctx.strokeStyle = col
          ctx.beginPath()
          ctx.moveTo(X, Y)
          ctx.lineTo(X - Math.sin(p.yaw) * 11, Y - Math.cos(p.yaw) * 11)
          ctx.stroke()
          ctx.fillStyle = '#e6ebf2'
          ctx.font = '11px Inter, sans-serif'
          ctx.fillText(p.name, X + 8, Y - 7)
          dots.current.push({ id: Number(p.id), x: X, y: Y })
        }
      }

      if (!pulse && !heat) {
        ctx.fillStyle = '#7d8898'
        ctx.font = '13px Inter, sans-serif'
        ctx.fillText('Waiting for this server\'s next pulse (every 5s)…', 16, 24)
      }
      raf = requestAnimationFrame(draw)
    }
    raf = requestAnimationFrame(draw)

    const onWheel = (e: WheelEvent) => {
      e.preventDefault()
      view.current.scale *= e.deltaY < 0 ? 1.15 : 1 / 1.15
    }
    const onDown = (e: PointerEvent) => {
      drag = { x: e.clientX, y: e.clientY }
    }
    const onMove = (e: PointerEvent) => {
      if (!drag) return
      view.current.cx -= (e.clientX - drag.x) / view.current.scale
      view.current.cz -= (e.clientY - drag.y) / view.current.scale
      drag = { x: e.clientX, y: e.clientY }
    }
    const onUp = (e: PointerEvent) => {
      const moved = drag && Math.hypot(e.clientX - drag.x, e.clientY - drag.y) > 3
      drag = null
      if (moved) return
      const rect = el.getBoundingClientRect()
      const hit = dots.current.find((d) => Math.hypot(d.x - (e.clientX - rect.left), d.y - (e.clientY - rect.top)) < 10)
      if (hit) open(hit.id)
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    el.addEventListener('pointerdown', onDown)
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
    return () => {
      cancelAnimationFrame(raf)
      observer.disconnect()
      el.removeEventListener('wheel', onWheel)
      el.removeEventListener('pointerdown', onDown)
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
    }
  }, [map, pulse, points, heat, kick, open])

  return (
    <div className="relative">
      <canvas ref={canvas} className="block h-[520px] w-full cursor-grab touch-none active:cursor-grabbing" />
      <div className="pointer-events-none absolute bottom-3 left-3 flex flex-wrap gap-3 rounded-lg bg-bg/80 px-3 py-1.5 text-[11px] text-muted">
        {heat ? (
          <span>{points.length} flags plotted · colors match the check that fired</span>
        ) : (
          <>
            <span><span className="text-good">●</span> clean</span>
            <span><span className="text-accent">●</span> flagged</span>
            <span><span className="text-warn">●</span> suspect</span>
            <span><span className="text-bad">●</span> at kick</span>
            <span style={{ color: '#a78bfa' }}>● admin</span>
            <span>scroll to zoom · drag to pan · click a dot</span>
          </>
        )}
      </div>
    </div>
  )
}
