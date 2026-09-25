import { useEffect, useMemo, useRef, useState } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { loadMap, supabase, type MapPart, type Replay } from '../lib/supabase'
import { caseFile } from '../lib/caseFile'
import { CHECK_COLORS, ago, robloxProfile } from '../lib/format'
import { Button } from '../components/ui'

type Props = { id: number; back: () => void; openPlayer: (id: number) => void }

const SPEEDS = [0.25, 0.5, 1, 2]

// position at time t, interpolated between recorded samples
function sampleAt(samples: Replay['samples'], t: number) {
  let i = 1
  while (i < samples.length - 1 && samples[i][0] < t) i++
  const a = samples[i - 1], b = samples[i]
  const span = b[0] - a[0]
  // a snapback is instant, don't slide the ghost across it
  const k = b[5] === 1 || span <= 0 ? (t >= b[0] ? 1 : 0) : Math.min(1, Math.max(0, (t - a[0]) / span))
  const yawDelta = Math.atan2(Math.sin(b[4] - a[4]), Math.cos(b[4] - a[4]))
  return {
    x: a[1] + (b[1] - a[1]) * k,
    y: a[2] + (b[2] - a[2]) * k,
    z: a[3] + (b[3] - a[3]) * k,
    yaw: a[4] + yawDelta * k,
    index: i,
  }
}

function toLuau(r: Replay, label: 'legit' | 'cheat') {
  const rows = r.samples.map(
    (s) => `\t\t{ t = ${s[0]}, x = ${s[1]}, y = ${s[2]}, z = ${s[3]}, grounded = ${s[6] === 1} },`,
  )
  return [
    `-- replay #${r.id} (${r.kind}) exported from the anticheat dashboard`,
    `return {`,
    `\tname = "replay#${r.id}",`,
    `\tlabel = "${label}",`,
    `\tkind = "recorded",`,
    `\twalkSpeed = ${Number(r.meta.walkSpeed ?? 16)},`,
    `\tsamples = {`,
    ...rows,
    `\t},`,
    `}`,
    ``,
  ].join('\n')
}

function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/plain' }))
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.click()
  URL.revokeObjectURL(url)
}

export default function ReplayViewer({ id, back, openPlayer }: Props) {
  const mount = useRef<HTMLDivElement>(null)
  const [replay, setReplay] = useState<Replay | null>(null)
  const [parts, setParts] = useState<MapPart[] | null>(null)
  const [error, setError] = useState('')
  const [time, setTime] = useState(0)
  const [playing, setPlaying] = useState(true)
  const [speed, setSpeed] = useState(1)
  const [follow, setFollow] = useState(true)

  const timeRef = useRef(0)
  const playingRef = useRef(true)
  const speedRef = useRef(1)
  const followRef = useRef(true)
  playingRef.current = playing
  speedRef.current = speed
  followRef.current = follow

  useEffect(() => {
    let alive = true
    supabase
      .from('replays')
      .select('*')
      .eq('id', id)
      .maybeSingle()
      .then(async ({ data, error }) => {
        if (!alive) return
        if (error || !data) {
          setError('Replay not found.')
          return
        }
        const r = data as Replay
        setReplay(r)
        timeRef.current = r.samples[0]?.[0] ?? 0
        const map = await loadMap(r.place_id, r.map_version)
        if (alive) setParts(map?.parts ?? [])
      })
    return () => {
      alive = false
    }
  }, [id])

  const start = replay?.samples[0]?.[0] ?? 0
  const end = replay?.samples[replay.samples.length - 1]?.[0] ?? 0

  const file = useMemo(
    () =>
      replay &&
      caseFile({
        name: String(replay.meta.name ?? replay.user_id),
        events: replay.events,
        samples: replay.samples,
        score: Number(replay.meta.score ?? 0),
        kickScore: Number(replay.meta.kickScore ?? 100),
        walkSpeed: Number(replay.meta.walkSpeed ?? 16),
        kind: replay.kind,
      }),
    [replay],
  )

  // the whole three.js scene lives in here
  useEffect(() => {
    const el = mount.current
    if (!el || !replay || parts === null || replay.samples.length < 2) return
    const samples = replay.samples

    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(el.clientWidth, el.clientHeight)
    renderer.shadowMap.enabled = false
    el.appendChild(renderer.domElement)

    const scene = new THREE.Scene()
    scene.background = new THREE.Color('#07090d')
    scene.fog = new THREE.Fog('#07090d', 180, 700)

    const camera = new THREE.PerspectiveCamera(55, el.clientWidth / el.clientHeight, 0.5, 3000)
    const controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping = true
    controls.maxPolarAngle = Math.PI * 0.49

    scene.add(new THREE.HemisphereLight('#bcd7ff', '#1a1f2a', 1.1))
    const sun = new THREE.DirectionalLight('#ffffff', 1.4)
    sun.position.set(80, 160, 60)
    scene.add(sun)

    const disposables: { dispose(): void }[] = []
    const track = <T extends { dispose(): void }>(x: T) => {
      disposables.push(x)
      return x
    }

    // path bounds, used for camera + fallback ground
    const box = new THREE.Box3()
    for (const s of samples) box.expandByPoint(new THREE.Vector3(s[1], s[2], s[3]))
    const center = box.getCenter(new THREE.Vector3())

    // the map: every exported part as an instanced box / ball / cylinder
    const shapes: Record<number, THREE.BufferGeometry> = {
      0: track(new THREE.BoxGeometry(1, 1, 1)),
      1: track(new THREE.SphereGeometry(0.5, 16, 12)),
      2: track(new THREE.CylinderGeometry(0.5, 0.5, 1, 16).rotateZ(Math.PI / 2)),
      3: track(new THREE.BoxGeometry(1, 1, 1)),
    }
    const material = track(new THREE.MeshStandardMaterial({ roughness: 0.85, metalness: 0.05 }))
    const byShape = new Map<number, MapPart[]>()
    for (const p of parts) {
      const shape = p[10] in shapes ? p[10] : 0
      if (!byShape.has(shape)) byShape.set(shape, [])
      byShape.get(shape)!.push(p)
    }
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), color = new THREE.Color()
    for (const [shape, list] of byShape) {
      const mesh = new THREE.InstancedMesh(shapes[shape], material, list.length)
      list.forEach((p, i) => {
        e.set(p[6], p[7], p[8], 'XYZ')
        q.setFromEuler(e)
        m.compose(new THREE.Vector3(p[0], p[1], p[2]), q, new THREE.Vector3(p[3], p[4], p[5]))
        mesh.setMatrixAt(i, m)
        color.setHex(p[9]).multiplyScalar(0.8)
        mesh.setColorAt(i, color)
      })
      scene.add(mesh)
    }
    if (parts.length === 0) {
      const grid = new THREE.GridHelper(600, 60, '#1d2531', '#121821')
      grid.position.set(center.x, box.min.y - 3, center.z)
      scene.add(grid)
    }

    // trail: cyan, red around detections, amber for our snapbacks
    const hot = replay.events.map((ev) => ev[0])
    const trailPos: number[] = [], trailCol: number[] = []
    const cyan = new THREE.Color('#22d3ee'), red = new THREE.Color('#f43f5e'), amber = new THREE.Color('#fbbf24')
    for (const s of samples) {
      trailPos.push(s[1], s[2] - 2.5, s[3])
      const c = s[5] === 1 ? amber : hot.some((h) => Math.abs(h - s[0]) < 0.35) ? red : cyan
      trailCol.push(c.r, c.g, c.b)
    }
    const trailGeo = track(new THREE.BufferGeometry())
    trailGeo.setAttribute('position', new THREE.Float32BufferAttribute(trailPos, 3))
    trailGeo.setAttribute('color', new THREE.Float32BufferAttribute(trailCol, 3))
    const trailMat = track(new THREE.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.9 }))
    scene.add(new THREE.Line(trailGeo, trailMat))

    // snapback rings
    const ringGeo = track(new THREE.TorusGeometry(1.4, 0.15, 8, 24).rotateX(Math.PI / 2))
    const ringMat = track(new THREE.MeshBasicMaterial({ color: '#fbbf24' }))
    for (const s of samples) {
      if (s[5] === 1) {
        const ring = new THREE.Mesh(ringGeo, ringMat)
        ring.position.set(s[1], s[2] - 2.9, s[3])
        scene.add(ring)
      }
    }

    // a beam of light wherever something fired
    const beamGeo = track(new THREE.CylinderGeometry(0.12, 0.12, 14, 8))
    for (const ev of replay.events) {
      if (ev[0] < samples[0][0] || ev[0] > samples[samples.length - 1][0]) continue
      const p = sampleAt(samples, ev[0])
      const mat = track(
        new THREE.MeshBasicMaterial({ color: CHECK_COLORS[ev[1]] ?? '#94a3b8', transparent: true, opacity: 0.7 }),
      )
      const beam = new THREE.Mesh(beamGeo, mat)
      beam.position.set(p.x, p.y + 4, p.z)
      scene.add(beam)
    }

    // the ghost
    const ghostMat = track(
      new THREE.MeshStandardMaterial({ color: '#22d3ee', emissive: '#0a3a44', transparent: true, opacity: 0.85 }),
    )
    const ghost = new THREE.Group()
    const body = new THREE.Mesh(track(new THREE.CapsuleGeometry(1, 3, 6, 16)), ghostMat)
    const nose = new THREE.Mesh(track(new THREE.ConeGeometry(0.45, 1.2, 12).rotateX(-Math.PI / 2)), ghostMat)
    nose.position.set(0, 1.2, -1.3)
    ghost.add(body, nose)
    scene.add(ghost)

    const size = box.getSize(new THREE.Vector3())
    const dist = Math.max(40, Math.max(size.x, size.z) * 0.9)
    camera.position.set(center.x + dist * 0.6, center.y + dist * 0.7, center.z + dist * 0.6)
    controls.target.copy(center)

    const onResize = () => {
      renderer.setSize(el.clientWidth, el.clientHeight)
      camera.aspect = el.clientWidth / el.clientHeight
      camera.updateProjectionMatrix()
    }
    const observer = new ResizeObserver(onResize)
    observer.observe(el)

    let last = performance.now()
    let raf = 0
    let uiTick = 0
    const loop = (now: number) => {
      const dt = Math.min(0.1, (now - last) / 1000)
      last = now
      if (playingRef.current) {
        timeRef.current += dt * speedRef.current
        if (timeRef.current > samples[samples.length - 1][0]) timeRef.current = samples[0][0]
      }
      const t = timeRef.current
      const p = sampleAt(samples, t)
      ghost.position.set(p.x, p.y, p.z)
      ghost.rotation.y = p.yaw
      const flagged = hot.some((h) => Math.abs(h - t) < 0.35)
      ghostMat.color.set(flagged ? '#f43f5e' : '#22d3ee')
      ghostMat.emissive.set(flagged ? '#4a0f1c' : '#0a3a44')

      if (followRef.current) {
        const goal = new THREE.Vector3(p.x, p.y, p.z)
        const shift = goal.clone().sub(controls.target).multiplyScalar(0.08)
        controls.target.add(shift)
        camera.position.add(shift)
      }
      controls.update()
      renderer.render(scene, camera)

      // react state only ~10x a second, the scene itself runs every frame
      if (now - uiTick > 100) {
        uiTick = now
        setTime(t)
      }
      raf = requestAnimationFrame(loop)
    }
    raf = requestAnimationFrame(loop)

    return () => {
      cancelAnimationFrame(raf)
      observer.disconnect()
      controls.dispose()
      disposables.forEach((d) => d.dispose())
      scene.traverse((o) => {
        if (o instanceof THREE.InstancedMesh) o.dispose()
      })
      renderer.dispose()
      renderer.domElement.remove()
    }
  }, [replay, parts])

  const seek = (t: number) => {
    timeRef.current = t
    setTime(t)
  }

  if (error) {
    return (
      <div className="grid min-h-full place-items-center p-6 text-center">
        <div>
          <p className="text-muted">{error}</p>
          <div className="mt-4">
            <Button onClick={back}>Back</Button>
          </div>
        </div>
      </div>
    )
  }

  const span = Math.max(end - start, 0.001)
  const name = String(replay?.meta.name ?? replay?.user_id ?? '')

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-bg lg:flex-row">
      <div className="relative min-h-[55vh] flex-1">
        <div ref={mount} className="absolute inset-0" />
        {!replay || parts === null ? (
          <div className="absolute inset-0 grid place-items-center text-sm text-muted">Loading replay…</div>
        ) : null}

        <div className="pointer-events-none absolute left-4 top-4 flex items-center gap-3">
          <button onClick={back} className="pointer-events-auto rounded-lg border border-line bg-panel/90 px-3 py-1.5 text-sm hover:border-muted/50">
            ← Back
          </button>
          {replay && (
            <div className="rounded-lg border border-line bg-panel/90 px-3 py-1.5 backdrop-blur">
              <span className="font-semibold">{name}</span>
              <span className="ml-2 font-mono text-xs text-muted">
                replay #{replay.id} · {replay.kind} · {ago(replay.created_at)}
              </span>
            </div>
          )}
        </div>

        {replay && (
          <div className="absolute inset-x-4 bottom-4 rounded-xl border border-line bg-panel/90 p-3 backdrop-blur">
            <div className="relative mb-2 h-3">
              {replay.events.map((ev, i) => (
                <button
                  key={i}
                  title={`${ev[1]} · ${ev[2]}`}
                  onClick={() => seek(ev[0])}
                  className="absolute top-0 h-3 w-1.5 -translate-x-1/2 rounded-full"
                  style={{ left: `${((ev[0] - start) / span) * 100}%`, background: CHECK_COLORS[ev[1]] ?? '#94a3b8' }}
                />
              ))}
            </div>
            <input
              type="range"
              min={start}
              max={end}
              step={0.01}
              value={time}
              onChange={(e) => seek(Number(e.target.value))}
              className="w-full accent-cyan-400"
            />
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button tone="accent" onClick={() => setPlaying((p) => !p)}>
                {playing ? 'Pause' : 'Play'}
              </Button>
              {SPEEDS.map((s) => (
                <button
                  key={s}
                  onClick={() => setSpeed(s)}
                  className={`rounded-md px-2 py-1 font-mono text-xs ${speed === s ? 'bg-accent/15 text-accent' : 'text-muted hover:text-text'}`}
                >
                  {s}×
                </button>
              ))}
              <label className="ml-2 flex items-center gap-1.5 text-xs text-muted">
                <input type="checkbox" checked={follow} onChange={(e) => setFollow(e.target.checked)} className="accent-cyan-400" />
                follow
              </label>
              <span className="ml-auto font-mono text-xs text-muted">
                {end - time < 0.05 ? (replay.kind === 'kick' ? 'kick' : 'end') : `${(end - time).toFixed(1)}s before ${replay.kind === 'kick' ? 'kick' : 'end'}`}
              </span>
            </div>
          </div>
        )}
      </div>

      <aside className="max-h-[45vh] w-full overflow-y-auto border-t border-line bg-panel p-5 lg:max-h-none lg:w-96 lg:border-l lg:border-t-0">
        {file && replay ? (
          <div className="space-y-5">
            <div>
              <div className="text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">Case file</div>
              <h2 className="mt-1 text-lg font-semibold">{name}</h2>
              <div className="mt-1 flex gap-3 text-xs">
                <button onClick={() => openPlayer(replay.user_id)} className="text-accent hover:underline">
                  Player record
                </button>
                <a href={robloxProfile(replay.user_id)} target="_blank" rel="noopener noreferrer" className="text-accent hover:underline">
                  Roblox profile ↗
                </a>
              </div>
            </div>
            <ul className="space-y-3">
              {file.lines.map((line, i) => (
                <li key={i} className="flex gap-3 text-sm leading-relaxed">
                  <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />
                  <span>{line}</span>
                </li>
              ))}
            </ul>
            <p className="rounded-lg border border-line bg-panel-2 px-3 py-2 text-sm text-muted">{file.verdict}</p>

            <div>
              <div className="mb-2 text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">Timeline</div>
              <ul className="space-y-1">
                {replay.events.map((ev, i) => (
                  <li key={i}>
                    <button onClick={() => seek(ev[0])} className="flex w-full items-center gap-2 rounded px-2 py-1 text-left text-xs hover:bg-panel-2">
                      <span className="h-2 w-2 rounded-full" style={{ background: CHECK_COLORS[ev[1]] ?? '#94a3b8' }} />
                      <span className="font-mono text-muted">{ev[0].toFixed(1)}s</span>
                      <span>{ev[1]}</span>
                      <span className="text-muted">{ev[2]}</span>
                    </button>
                  </li>
                ))}
                {replay.events.length === 0 && <li className="text-xs text-muted">No detections in this window.</li>}
              </ul>
            </div>

            <div className="border-t border-line pt-4">
              <div className="mb-2 text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">Test suite</div>
              <p className="mb-2 text-xs text-muted">Add this recording to the automatic tests in roblox/tests/recorded.</p>
              <div className="flex gap-2">
                <Button onClick={() => download(`session_${replay.id}.luau`, toLuau(replay, 'legit'))}>As legit play</Button>
                <Button tone="danger" onClick={() => download(`session_${replay.id}.luau`, toLuau(replay, 'cheat'))}>
                  As cheat
                </Button>
              </div>
            </div>
          </div>
        ) : (
          <div className="text-sm text-muted">Loading…</div>
        )}
      </aside>
    </div>
  )
}
