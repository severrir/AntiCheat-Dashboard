import * as THREE from 'three'
import { SUPABASE_URL, type Rig, type RigPart } from '../lib/supabase'

const TEMPLATE_W = 585
type Rect = [number, number, number, number]

const TORSO = { up: [231, 8, 128, 64], front: [231, 74, 128, 128], px: [165, 74, 64, 128], nx: [361, 74, 64, 128], back: [427, 74, 128, 128], down: [231, 204, 128, 64] } as const
const RIGHT = { up: [217, 289, 64, 64], front: [217, 355, 64, 128], px: [151, 355, 64, 128], nx: [19, 355, 64, 128], back: [85, 355, 64, 128], down: [217, 485, 64, 64] } as const
const LEFT = { up: [308, 289, 64, 64], front: [308, 355, 64, 128], px: [506, 355, 64, 128], nx: [374, 355, 64, 128], back: [440, 355, 64, 128], down: [308, 485, 64, 64] } as const

type Chain = 'torso' | 'rarm' | 'larm' | 'rleg' | 'lleg' | 'head'
const CHAINS: Record<Exclude<Chain, 'head'>, string[][]> = {
  torso: [['UpperTorso', 'LowerTorso'], ['Torso']],
  rarm: [['RightUpperArm', 'RightLowerArm', 'RightHand'], ['Right Arm']],
  larm: [['LeftUpperArm', 'LeftLowerArm', 'LeftHand'], ['Left Arm']],
  rleg: [['RightUpperLeg', 'RightLowerLeg', 'RightFoot'], ['Right Leg']],
  lleg: [['LeftUpperLeg', 'LeftLowerLeg', 'LeftFoot'], ['Left Leg']],
}

function chainOf(name: string): { chain: Chain; links: string[] } | null {
  if (name === 'Head') return { chain: 'head', links: ['Head'] }
  for (const [chain, variants] of Object.entries(CHAINS) as [Exclude<Chain, 'head'>, string[][]][]) {
    for (const links of variants) if (links.includes(name)) return { chain, links }
  }
  return null
}

export const DEFAULT_RIG: Rig = {
  type: 'R6',
  hip: 0,
  root: [2, 2, 1],
  parts: [
    { n: 'Head', s: [2, 1, 1], r: [0, 1.5, 0, 0, 0, 0], c: 0xf5cd30 },
    { n: 'Torso', s: [2, 2, 1], r: [0, 0, 0, 0, 0, 0], c: 0x0d69ac },
    { n: 'Right Arm', s: [1, 2, 1], r: [1.5, 0, 0, 0, 0, 0], c: 0xf5cd30 },
    { n: 'Left Arm', s: [1, 2, 1], r: [-1.5, 0, 0, 0, 0, 0], c: 0xf5cd30 },
    { n: 'Right Leg', s: [1, 2, 1], r: [0.5, -2, 0, 0, 0, 0], c: 0xa4bd47 },
    { n: 'Left Leg', s: [1, 2, 1], r: [-0.5, -2, 0, 0, 0, 0], c: 0xa4bd47 },
  ],
}

const imageCache = new Map<number, Promise<ImageBitmap | null>>()

export function robloxImage(id: number | null | undefined): Promise<ImageBitmap | null> {
  if (!id) return Promise.resolve(null)
  let hit = imageCache.get(id)
  if (!hit) {
    hit = (async () => {
      for (let attempt = 0; attempt < 3; attempt++) {
        const res = await fetch(`${SUPABASE_URL}/functions/v1/avatar?asset=${id}`).catch(() => null)
        if (res?.status === 200) return createImageBitmap(await res.blob()).catch(() => null)
        if (res?.status !== 202) return null
        await new Promise((r) => setTimeout(r, 1500))
      }
      return null
    })()
    imageCache.set(id, hit)
  }
  return hit
}

function averageColor(img: ImageBitmap): THREE.Color | null {
  const c = document.createElement('canvas')
  c.width = c.height = 32
  const g = c.getContext('2d', { willReadFrequently: true })!
  g.drawImage(img, 0, 0, 32, 32)
  const d = g.getImageData(0, 0, 32, 32).data
  let r = 0, gr = 0, b = 0, n = 0
  for (let i = 0; i < d.length; i += 4) {
    if (d[i + 3] < 128) continue
    r += d[i]; gr += d[i + 1]; b += d[i + 2]; n++
  }
  return n ? new THREE.Color(r / n / 255, gr / n / 255, b / n / 255) : null
}

const hex = (c: number) => `#${c.toString(16).padStart(6, '0')}`

function faceCanvas(
  base: number,
  rect: Rect | null,
  slice: [number, number],
  layers: (ImageBitmap | null)[],
  extra?: (g: CanvasRenderingContext2D, size: number) => void,
) {
  const size = 128
  const c = document.createElement('canvas')
  c.width = c.height = size
  const g = c.getContext('2d')!
  g.fillStyle = hex(base)
  g.fillRect(0, 0, size, size)
  if (rect) {
    for (const img of layers) {
      if (!img) continue
      const k = img.width / TEMPLATE_W
      const [x, y, w, h] = rect
      g.drawImage(img, x * k, (y + h * slice[0]) * k, w * k, h * (slice[1] - slice[0]) * k, 0, 0, size, size)
    }
  }
  extra?.(g, size)
  const tex = new THREE.CanvasTexture(c)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = 4
  return tex
}

function drawFace(face: ImageBitmap | null) {
  return (g: CanvasRenderingContext2D, size: number) => {
    if (face) {
      g.drawImage(face, size * 0.1, size * 0.1, size * 0.8, size * 0.8)
      return
    }
    g.fillStyle = '#111'
    g.beginPath()
    g.ellipse(size * 0.36, size * 0.42, size * 0.045, size * 0.08, 0, 0, Math.PI * 2)
    g.ellipse(size * 0.64, size * 0.42, size * 0.045, size * 0.08, 0, 0, Math.PI * 2)
    g.fill()
    g.lineWidth = size * 0.035
    g.strokeStyle = '#111'
    g.lineCap = 'round'
    g.beginPath()
    g.arc(size * 0.5, size * 0.52, size * 0.2, Math.PI * 0.2, Math.PI * 0.8)
    g.stroke()
  }
}

export type Avatar = {
  group: THREE.Group
  update(root: THREE.Vector3, yaw: number, pos: Float32Array | null, rot: Float32Array | null, speed: number, t: number): void
  setFlagged(on: boolean): void
  dispose(): void
}

type Limb = { mesh: THREE.Mesh; rest: THREE.Matrix4; chain: Chain | null; restPos: THREE.Vector3; restQuat: THREE.Quaternion; half: number }

export function buildAvatar(rig: Rig, name: string): Avatar {
  const group = new THREE.Group()
  const disposables: { dispose(): void }[] = []
  const limbs: Limb[] = []
  const byName = new Map<string, Limb>()

  for (const part of rig.parts) {
    const geo = new THREE.BoxGeometry(part.s[0], part.s[1], part.s[2])
    const mats = Array.from({ length: 6 }, () => new THREE.MeshStandardMaterial({ color: part.c, roughness: 0.75 }))
    disposables.push(geo, ...mats)
    const mesh = new THREE.Mesh(geo, mats)
    mesh.castShadow = true
    mesh.matrixAutoUpdate = false
    group.add(mesh)
    const restPos = new THREE.Vector3(part.r[0], part.r[1], part.r[2])
    const restQuat = new THREE.Quaternion().setFromEuler(new THREE.Euler(part.r[3], part.r[4], part.r[5], 'XYZ'))
    const rest = new THREE.Matrix4().compose(restPos, restQuat, new THREE.Vector3(1, 1, 1))
    const limb = { mesh, rest, chain: chainOf(part.n)?.chain ?? null, restPos, restQuat, half: part.s[1] / 2 }
    limbs.push(limb)
    byName.set(part.n, limb)
  }

  const sizeOf = new Map(rig.parts.map((p) => [p.n, p.s] as const))
  const ball = new THREE.SphereGeometry(0.5, 14, 10)
  const block = new THREE.BoxGeometry(1, 1, 1)
  disposables.push(ball, block)
  for (const a of rig.acc ?? []) {
    const limb = byName.get(a.l)
    const ls = sizeOf.get(a.l)
    if (!limb || !ls || a.w) continue
    const mat = new THREE.MeshStandardMaterial({ color: a.c, roughness: 0.85 })
    disposables.push(mat)
    const fit = (i: number, k: number) => Math.min(a.s[i], ls[i] * k)
    const inside = (i: number, k: number) => THREE.MathUtils.clamp(a.o[i], -ls[i] * k, ls[i] * k)
    let m: THREE.Mesh
    if (a.l === 'Head') {
      const H = ls[1] / 2
      if (a.o[1] > ls[1] * 0.9) {
        m = new THREE.Mesh(block, mat)
        m.scale.set(fit(0, 1.2), fit(1, 1.2), fit(2, 1.2))
        m.position.set(0, inside(1, 1.1), 0)
      } else {
        m = new THREE.Mesh(block, mat)
        m.scale.set(ls[0] * 1.1, H * 0.75 + 0.1, ls[2] * 1.1)
        m.position.set(0, (H * 0.25 + H + 0.1) / 2, 0)
        const back = new THREE.Mesh(block, mat)
        back.scale.set(ls[0] * 1.1, H * 1.5, ls[2] * 0.2)
        back.position.set(0, H * 0.25, ls[2] * 0.5)
        back.castShadow = true
        limb.mesh.add(back)
      }
    } else if (/Torso$/.test(a.l)) {
      m = new THREE.Mesh(block, mat)
      m.scale.set(fit(0, 1.08), fit(1, 1.04), fit(2, 1.35))
      m.position.set(inside(0, 0.1), inside(1, 0.1), inside(2, 0.25))
    } else {
      m = new THREE.Mesh(ball, mat)
      m.scale.set(fit(0, 1.3), fit(1, 1.3), fit(2, 1.3))
      m.position.set(inside(0, 0.5), inside(1, 0.5), inside(2, 0.5))
      m.rotation.set(a.o[3], a.o[4], a.o[5], 'XYZ')
    }
    m.castShadow = true
    limb.mesh.add(m)
    if (a.t) {
      robloxImage(a.t).then((img) => {
        const c = img && averageColor(img)
        if (c) mat.color.copy(c)
      })
    }
  }

  const clothes = rig.clothes
  Promise.all([robloxImage(clothes?.shirt), robloxImage(clothes?.pants), robloxImage(clothes?.tshirt), robloxImage(clothes?.face)]).then(
    ([shirt, pants, tee, face]) => {
      for (const part of rig.parts) {
        const limb = byName.get(part.n)
        const info = chainOf(part.n)
        if (!limb || !info) continue
        paint(limb, part, info, rig, { shirt, pants, tee, face })
      }
    },
  )

  const tag = document.createElement('canvas')
  tag.width = 256
  tag.height = 64
  const tagTex = new THREE.CanvasTexture(tag)
  tagTex.colorSpace = THREE.SRGBColorSpace
  const drawTag = (flagged: boolean) => {
    const g = tag.getContext('2d')!
    g.clearRect(0, 0, 256, 64)
    g.font = '600 30px Inter, system-ui, sans-serif'
    g.textAlign = 'center'
    g.lineWidth = 6
    g.strokeStyle = 'rgba(0,0,0,0.65)'
    g.strokeText(name, 128, 42)
    g.fillStyle = flagged ? '#fb7185' : '#ffffff'
    g.fillText(name, 128, 42)
    tagTex.needsUpdate = true
  }
  drawTag(false)
  const tagMat = new THREE.SpriteMaterial({ map: tagTex, depthTest: false, transparent: true })
  const sprite = new THREE.Sprite(tagMat)
  sprite.scale.set(4, 1, 1)
  sprite.renderOrder = 10
  const head = byName.get('Head')
  const top = head ? head.restPos.y + (rig.parts.find((p) => p.n === 'Head')?.s[1] ?? 1) / 2 + 1.1 : 3.5
  sprite.position.set(0, top, 0)
  group.add(sprite)
  disposables.push(tagTex, tagMat)

  const pivotM = new THREE.Matrix4(), rotM = new THREE.Matrix4(), backM = new THREE.Matrix4()
  const local = new THREE.Matrix4(), q = new THREE.Quaternion(), v = new THREE.Vector3()
  const one = new THREE.Vector3(1, 1, 1)
  let flagged = false

  return {
    group,
    update(root, yaw, pos, rot, speed, t) {
      group.position.copy(root)
      group.rotation.set(0, yaw, 0)
      group.updateMatrix()
      for (let i = 0; i < limbs.length; i++) {
        const limb = limbs[i]
        if (pos && rot && pos.length >= (i + 1) * 3) {
          v.set(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
          q.set(rot[i * 4], rot[i * 4 + 1], rot[i * 4 + 2], rot[i * 4 + 3])
          local.compose(v, q, one)
        } else {
          local.copy(limb.rest)
          const sign = limb.chain === 'rarm' || limb.chain === 'lleg' ? 1 : limb.chain === 'larm' || limb.chain === 'rleg' ? -1 : 0
          if (sign !== 0) {
            const swing = Math.min(1, speed / 16) * Math.sin(t * 9) * 0.7 * sign
            const py = limb.restPos.y + limb.half
            pivotM.makeTranslation(limb.restPos.x, py, limb.restPos.z)
            rotM.makeRotationX(swing)
            backM.makeTranslation(-limb.restPos.x, -py, -limb.restPos.z)
            local.copy(pivotM).multiply(rotM).multiply(backM).multiply(limb.rest)
          }
        }
        limb.mesh.matrix.copy(local)
        limb.mesh.matrixWorldNeedsUpdate = true
      }
    },
    setFlagged(on) {
      if (on === flagged) return
      flagged = on
      drawTag(on)
    },
    dispose() {
      disposables.forEach((d) => d.dispose())
      for (const limb of limbs) {
        for (const m of limb.mesh.material as THREE.MeshStandardMaterial[]) m.map?.dispose()
      }
    },
  }
}

function paint(
  limb: Limb,
  part: RigPart,
  info: { chain: Chain; links: string[] },
  rig: Rig,
  img: { shirt: ImageBitmap | null; pants: ImageBitmap | null; tee: ImageBitmap | null; face: ImageBitmap | null },
) {
  const mats = limb.mesh.material as THREE.MeshStandardMaterial[]
  const set = (i: number, tex: THREE.Texture) => {
    mats[i].map = tex
    mats[i].color.set(0xffffff)
    mats[i].needsUpdate = true
  }

  if (info.chain === 'head') {
    set(5, faceCanvas(part.c, null, [0, 1], [], drawFace(img.face)))
    return
  }

  const heights = info.links.map((n) => rig.parts.find((p) => p.n === n)?.s[1] ?? 0)
  const total = heights.reduce((a, b) => a + b, 0) || 1
  const idx = info.links.indexOf(part.n)
  const from = heights.slice(0, idx).reduce((a, b) => a + b, 0) / total
  const slice: [number, number] = [from, from + heights[idx] / total]
  const first = idx === 0, last = idx === info.links.length - 1

  const layout = info.chain === 'torso' ? TORSO : info.chain === 'rarm' || info.chain === 'rleg' ? RIGHT : LEFT
  const legs = info.chain === 'rleg' || info.chain === 'lleg'
  const arms = info.chain === 'rarm' || info.chain === 'larm'
  const layers = [!arms ? img.pants : null, !legs ? img.shirt : null]
  if (!layers[0] && !layers[1]) return

  const teeOnFront =
    info.chain === 'torso' && first && img.tee
      ? (g: CanvasRenderingContext2D, size: number) => g.drawImage(img.tee!, size * 0.2, size * 0.1, size * 0.6, size * 0.6)
      : undefined

  set(0, faceCanvas(part.c, layout.px as unknown as Rect, slice, layers))
  set(1, faceCanvas(part.c, layout.nx as unknown as Rect, slice, layers))
  set(4, faceCanvas(part.c, layout.back as unknown as Rect, slice, layers))
  set(5, faceCanvas(part.c, layout.front as unknown as Rect, slice, layers, teeOnFront))
  if (first) set(2, faceCanvas(part.c, layout.up as unknown as Rect, [0, 1], layers))
  if (last) set(3, faceCanvas(part.c, layout.down as unknown as Rect, [0, 1], layers))
}
