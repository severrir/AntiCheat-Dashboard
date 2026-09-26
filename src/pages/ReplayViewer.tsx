import { useEffect, useMemo, useRef, useState } from 'react'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { loadMap, supabase, type MapData, type Replay } from '../lib/supabase'
import { caseFile } from '../lib/caseFile'
import { CHECK_COLORS, ago, robloxProfile } from '../lib/format'
import { Button } from '../components/ui'
import { buildAvatar, DEFAULT_RIG } from '../replay/avatar'
import { buildWorld } from '../replay/world'
import { recordCanvas, videoSupported } from '../replay/video'

type Props = { id: number; back: () => void; openPlayer: (id: number, game?: number) => void }

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
    k,
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


type CamMode = 'chase' | 'orbit' | 'top'
const CAMS: { key: CamMode; label: string }[] = [
  { key: 'chase', label: 'Chase' },
  { key: 'orbit', label: 'Free' },
  { key: 'top', label: 'Top' },
]

// every recorded pose as limb offsets + quaternions, so playback can blend between samples smoothly
function preparePoses(replay: Replay) {
  const rig = replay.rig
  if (!rig || !replay.poses) return null
  const n = rig.parts.length
  const e = new THREE.Euler(), q = new THREE.Quaternion()
  return replay.poses.map((p) => {
    if (!p || p.length < n * 6) return null
    const pos = new Float32Array(n * 3), rot = new Float32Array(n * 4)
    for (let i = 0; i < n; i++) {
      pos[i * 3] = p[i * 6]
      pos[i * 3 + 1] = p[i * 6 + 1]
      pos[i * 3 + 2] = p[i * 6 + 2]
      q.setFromEuler(e.set(p[i * 6 + 3], p[i * 6 + 4], p[i * 6 + 5], 'XYZ'))
      rot.set([q.x, q.y, q.z, q.w], i * 4)
    }
    return { pos, rot }
  })
}

export default function ReplayViewer({ id, back, openPlayer }: Props) {
  const mount = useRef<HTMLDivElement>(null)
  const [replay, setReplay] = useState<Replay | null>(null)
  const [map, setMap] = useState<MapData | null | undefined>(undefined)
  const [error, setError] = useState('')
  const [time, setTime] = useState(0)
  const [playing, setPlaying] = useState(true)
  const [speed, setSpeed] = useState(1)
  const [cam, setCam] = useState<CamMode>('chase')
  const [recording, setRecording] = useState(false)

  const timeRef = useRef(0)
  const playingRef = useRef(true)
  const speedRef = useRef(1)
  const camRef = useRef<CamMode>('chase')
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const recordRef = useRef<{ done: () => void } | null>(null)
  playingRef.current = playing
  speedRef.current = speed
  camRef.current = cam

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
        const m = await loadMap(r.place_id, r.map_version)
        if (alive) setMap(m)
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
    if (!el || !replay || map === undefined || replay.samples.length < 2) return
    const samples = replay.samples
    const rig = replay.rig ?? DEFAULT_RIG
    const poses = preparePoses(replay)

    const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: false })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(el.clientWidth, el.clientHeight)
    renderer.shadowMap.enabled = true
    renderer.shadowMap.type = THREE.PCFSoftShadowMap
    renderer.toneMapping = THREE.ACESFilmicToneMapping
    renderer.toneMappingExposure = 1.05
    el.appendChild(renderer.domElement)
    canvasRef.current = renderer.domElement

    const scene = new THREE.Scene()
    const camera = new THREE.PerspectiveCamera(70, el.clientWidth / el.clientHeight, 0.3, 5000)
    const controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping = true
    controls.maxPolarAngle = Math.PI * 0.49

    const disposables: { dispose(): void }[] = []
    const track = <T extends { dispose(): void }>(x: T) => (disposables.push(x), x)

    // path bounds, used for the camera and the fallback floor
    const box = new THREE.Box3()
    for (const s of samples) box.expandByPoint(new THREE.Vector3(s[1], s[2], s[3]))
    const center = box.getCenter(new THREE.Vector3())
    const legs = rig.hip + rig.root[1] / 2 // root to feet
    const floorY = box.min.y - (rig.type === 'R6' ? 3 : legs)

    const world = buildWorld(scene, map, center, floorY)

    // trail at their feet: cyan, red around detections, amber for our snapbacks
    const hot = replay.events.map((ev) => ev[0])
    const feet = rig.type === 'R6' ? 2.9 : legs - 0.1
    const trailPos: number[] = [], trailCol: number[] = []
    const cyan = new THREE.Color('#22d3ee'), red = new THREE.Color('#f43f5e'), amber = new THREE.Color('#fbbf24')
    for (const s of samples) {
      trailPos.push(s[1], s[2] - feet, s[3])
      const c = s[5] === 1 ? amber : hot.some((h) => Math.abs(h - s[0]) < 0.35) ? red : cyan
      trailCol.push(c.r, c.g, c.b)
    }
    const trailGeo = track(new THREE.BufferGeometry())
    trailGeo.setAttribute('position', new THREE.Float32BufferAttribute(trailPos, 3))
    trailGeo.setAttribute('color', new THREE.Float32BufferAttribute(trailCol, 3))
    scene.add(new THREE.Line(trailGeo, track(new THREE.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.8 }))))

    // snapback rings on the ground
    const ringGeo = track(new THREE.TorusGeometry(1.4, 0.12, 8, 24).rotateX(Math.PI / 2))
    const ringMat = track(new THREE.MeshBasicMaterial({ color: '#fbbf24' }))
    for (const s of samples) {
      if (s[5] !== 1) continue
      const ring = new THREE.Mesh(ringGeo, ringMat)
      ring.position.set(s[1], s[2] - feet + 0.1, s[3])
      scene.add(ring)
    }

    // a thin pillar of light wherever something fired
    const beamGeo = track(new THREE.CylinderGeometry(0.08, 0.08, 16, 8))
    for (const ev of replay.events) {
      if (ev[0] < samples[0][0] || ev[0] > samples[samples.length - 1][0]) continue
      const p = sampleAt(samples, ev[0])
      const beam = new THREE.Mesh(
        beamGeo,
        track(new THREE.MeshBasicMaterial({ color: CHECK_COLORS[ev[1]] ?? '#94a3b8', transparent: true, opacity: 0.55 })),
      )
      beam.position.set(p.x, p.y - feet + 8, p.z)
      scene.add(beam)
    }

    const avatar = buildAvatar(rig, String(replay.meta.name ?? replay.user_id))
    scene.add(avatar.group)

    const size = box.getSize(new THREE.Vector3())
    const dist = Math.max(40, Math.max(size.x, size.z) * 0.9)
    camera.position.set(center.x + dist * 0.6, center.y + dist * 0.5, center.z + dist * 0.6)
    controls.target.copy(center)

    const onResize = () => {
      renderer.setSize(el.clientWidth, el.clientHeight)
      camera.aspect = el.clientWidth / el.clientHeight
      camera.updateProjectionMatrix()
    }
    const observer = new ResizeObserver(onResize)
    observer.observe(el)

    // scratch space for blending two poses
    const n = rig.parts.length
    const pos = new Float32Array(n * 3), rot = new Float32Array(n * 4)
    const qa = new THREE.Quaternion(), qb = new THREE.Quaternion()
    const blend = (index: number, k: number) => {
      if (!poses) return false
      const a = poses[index - 1], b = poses[index]
      const from = a ?? b, to = b ?? a
      if (!from || !to) return false
      for (let i = 0; i < n * 3; i++) pos[i] = from.pos[i] + (to.pos[i] - from.pos[i]) * k
      for (let i = 0; i < n; i++) {
        qa.fromArray(from.rot, i * 4)
        qb.fromArray(to.rot, i * 4)
        qa.slerp(qb, k).toArray(rot, i * 4)
      }
      return true
    }

    const root = new THREE.Vector3(), look = new THREE.Vector3(), want = new THREE.Vector3(), eye = new THREE.Vector3()
    let camYaw = sampleAt(samples, timeRef.current).yaw
    let first = true
    let last = performance.now()
    let raf = 0
    let uiTick = 0
    const loop = (now: number) => {
      const dt = Math.min(0.1, (now - last) / 1000)
      last = now
      if (playingRef.current) {
        timeRef.current += dt * speedRef.current
        if (timeRef.current > samples[samples.length - 1][0]) {
          if (recordRef.current) {
            timeRef.current = samples[samples.length - 1][0]
            recordRef.current.done()
            recordRef.current = null
          } else {
            timeRef.current = samples[0][0]
          }
        }
      }
      const t = timeRef.current
      const p = sampleAt(samples, t)
      root.set(p.x, p.y, p.z)
      const a = samples[p.index - 1], b = samples[p.index]
      const dtS = Math.max(0.01, b[0] - a[0])
      const moving = b[5] === 1 ? 0 : Math.hypot(b[1] - a[1], b[3] - a[3]) / dtS
      const posed = blend(p.index, p.k)
      avatar.update(root, p.yaw, posed ? pos : null, posed ? rot : null, moving, t)
      avatar.setFlagged(hot.some((h) => Math.abs(h - t) < 0.35))

      // cameras
      const mode = camRef.current
      controls.enabled = mode === 'orbit'
      const smooth = first ? 1 : 1 - Math.exp(-dt * 5)
      look.set(p.x, p.y + 1.5, p.z)
      if (mode === 'chase') {
        // roblox's default camera: behind and a little above, turning with them
        const d = Math.atan2(Math.sin(p.yaw - camYaw), Math.cos(p.yaw - camYaw))
        camYaw += d * (first ? 1 : 1 - Math.exp(-dt * 3))
        want.set(Math.sin(camYaw) * 12, 4.5, Math.cos(camYaw) * 12).add(root)
        camera.position.lerp(want, smooth)
        eye.lerp(look, first ? 1 : 1 - Math.exp(-dt * 10))
        camera.lookAt(eye)
      } else if (mode === 'top') {
        want.set(p.x, p.y + 70, p.z + 0.01)
        camera.position.lerp(want, smooth)
        eye.lerp(look, first ? 1 : 1 - Math.exp(-dt * 10))
        camera.lookAt(eye)
      } else {
        const shift = look.clone().sub(controls.target).multiplyScalar(0.08)
        controls.target.add(shift)
        camera.position.add(shift)
        controls.update()
      }
      if (mode !== 'orbit') controls.target.copy(eye)
      first = false

      // the sun's shadow box follows the action
      world.sun.position.copy(root).addScaledVector(world.sunDir, 150)
      world.sun.target.position.copy(root)

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
      avatar.dispose()
      world.dispose()
      disposables.forEach((d) => d.dispose())
      scene.traverse((o) => {
        if (o instanceof THREE.InstancedMesh) o.dispose()
      })
      renderer.dispose()
      renderer.domElement.remove()
      canvasRef.current = null
    }
  }, [replay, map])

  const seek = (t: number) => {
    timeRef.current = t
    setTime(t)
  }

  // plays the replay once from the start and saves what the camera saw
  async function saveVideo() {
    const canvas = canvasRef.current
    if (!canvas || !replay || recording) return
    const rec = recordCanvas(canvas)
    if (!rec) return
    setRecording(true)
    seek(start)
    setPlaying(true)
    await new Promise<void>((resolve) => {
      recordRef.current = { done: resolve }
    })
    const blob = await rec.stop()
    setRecording(false)
    setPlaying(false)
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `replay-${replay.id}-${String(replay.meta.name ?? replay.user_id)}.${rec.ext}`
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 5000)
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
      <div className="relative min-h-[65vh] flex-1">
        <div ref={mount} className="absolute inset-0" />
        {!replay || map === undefined ? (
          <div className="absolute inset-0 grid place-items-center text-sm text-muted">Loading replay…</div>
        ) : null}
        {recording && (
          <div className="pointer-events-none absolute right-4 top-4 flex items-center gap-2 rounded-lg border border-bad/40 bg-panel/90 px-3 py-1.5 text-sm text-bad">
            <span className="live-dot h-2 w-2 rounded-full bg-bad" /> Recording video… {Math.round(((time - start) / span) * 100)}%
          </div>
        )}

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
              <span className="ml-2 flex overflow-hidden rounded-md border border-line">
                {CAMS.map((c) => (
                  <button
                    key={c.key}
                    onClick={() => setCam(c.key)}
                    className={`px-2 py-1 text-xs ${cam === c.key ? 'bg-accent/15 text-accent' : 'text-muted hover:text-text'}`}
                  >
                    {c.label}
                  </button>
                ))}
              </span>
              {videoSupported() && (
                <Button onClick={saveVideo} disabled={recording || map === undefined}>
                  {recording ? 'Recording…' : '⬇ Save video'}
                </Button>
              )}
              <span className="ml-auto font-mono text-xs text-muted">
                {end - time < 0.05 ? (replay.kind === 'kick' ? 'kick' : 'end') : `${(end - time).toFixed(1)}s before ${replay.kind === 'kick' ? 'kick' : 'end'}`}
              </span>
            </div>
          </div>
        )}
      </div>

      <aside className="max-h-[35vh] w-full overflow-y-auto border-t border-line bg-panel p-5 lg:max-h-none lg:w-96 lg:border-l lg:border-t-0">
        {file && replay ? (
          <div className="space-y-5">
            <div>
              <div className="text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">Case file</div>
              <h2 className="mt-1 text-lg font-semibold">{name}</h2>
              <div className="mt-1 flex gap-3 text-xs">
                <button onClick={() => openPlayer(replay.user_id, replay.game_id)} className="text-accent hover:underline">
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
