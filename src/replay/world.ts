import * as THREE from 'three'
import type { MapData, MapPart, Sky, Terrain } from '../lib/supabase'

// the place, rebuilt from what the game exported: parts in their real shape, color, material and
// transparency, terrain from a heightmap in the place's own terrain colors, and the sky at the
// time of day the server was running

// roblox wedge: slopes down toward the front (-Z), tall at the back
function wedgeGeometry() {
  const g = new THREE.BufferGeometry()
  const v = [
    // bottom
    -0.5, -0.5, -0.5, 0.5, -0.5, -0.5, 0.5, -0.5, 0.5, -0.5, -0.5, -0.5, 0.5, -0.5, 0.5, -0.5, -0.5, 0.5,
    // back
    -0.5, -0.5, 0.5, 0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5, 0.5, 0.5,
    // slope
    -0.5, -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, 0.5, 0.5, -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5, -0.5,
    // sides
    -0.5, -0.5, -0.5, -0.5, -0.5, 0.5, -0.5, 0.5, 0.5, 0.5, -0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5, 0.5,
  ]
  g.setAttribute('position', new THREE.Float32BufferAttribute(v, 3))
  g.computeVertexNormals()
  return g
}

// roblox corner wedge: a pyramid with its peak over the front right corner (+X, -Z)
function cornerWedgeGeometry() {
  const a = [-0.5, -0.5, -0.5], b = [0.5, -0.5, -0.5], c = [0.5, -0.5, 0.5], d = [-0.5, -0.5, 0.5], p = [0.5, 0.5, -0.5]
  const tris = [a, b, c, a, c, d, b, p, c, a, p, b, c, p, d, d, p, a]
  const g = new THREE.BufferGeometry()
  g.setAttribute('position', new THREE.Float32BufferAttribute(tris.flat(), 3))
  g.computeVertexNormals()
  return g
}

// material code from the game -> how it looks here
function surface(code: number) {
  switch (code) {
    case 1: return { roughness: 1, metalness: 0, emissive: true } // neon
    case 2: return { roughness: 0.05, metalness: 0.1, opacity: 0.35 } // glass
    case 3: return { roughness: 0.8, metalness: 0 } // wood
    case 4: return { roughness: 0.35, metalness: 0.7 } // metal
    case 9: return { roughness: 0.15, metalness: 0, opacity: 0.85 } // ice
    case 10: return { roughness: 1, metalness: 0, opacity: 0.3, emissive: true } // forcefield
    case 12: return { roughness: 0.35, metalness: 0 } // smooth plastic
    case 5: case 6: case 7: case 8: case 11: return { roughness: 0.95, metalness: 0 }
    default: return { roughness: 0.7, metalness: 0 }
  }
}

export type World = { sunDir: THREE.Vector3; sun: THREE.DirectionalLight; dispose(): void }

export function buildWorld(scene: THREE.Scene, map: MapData | null, center: THREE.Vector3, floorY: number): World {
  const disposables: { dispose(): void }[] = []
  const track = <T extends { dispose(): void }>(x: T) => (disposables.push(x), x)

  const sky = skyLook(map?.sky ?? null)
  scene.background = sky.horizon.clone()
  scene.fog = new THREE.Fog(sky.fog, sky.fogNear, sky.fogFar)

  // gradient dome, follows nothing: it's big enough
  const dome = new THREE.Mesh(
    track(new THREE.SphereGeometry(2500, 32, 16)),
    track(
      new THREE.ShaderMaterial({
        side: THREE.BackSide,
        depthWrite: false,
        fog: false,
        uniforms: { top: { value: sky.top }, horizon: { value: sky.horizon }, bottom: { value: sky.ground } },
        vertexShader: 'varying vec3 p; void main(){ p = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
        fragmentShader:
          'uniform vec3 top; uniform vec3 horizon; uniform vec3 bottom; varying vec3 p; void main(){ float h = p.y; vec3 c = h > 0.0 ? mix(horizon, top, pow(h, 0.55)) : mix(horizon, bottom, pow(-h, 0.4)); gl_FragColor = vec4(c,1.0); }',
      }),
    ),
  )
  dome.position.copy(center)
  scene.add(dome)

  scene.add(new THREE.HemisphereLight(sky.top, sky.groundLight, sky.hemi))
  const sun = new THREE.DirectionalLight(sky.sunColor, sky.sunIntensity)
  sun.castShadow = true
  sun.shadow.mapSize.set(2048, 2048)
  sun.shadow.camera.left = -70
  sun.shadow.camera.right = 70
  sun.shadow.camera.top = 70
  sun.shadow.camera.bottom = -70
  sun.shadow.camera.near = 1
  sun.shadow.camera.far = 600
  sun.shadow.bias = -0.0005
  sun.shadow.normalBias = 0.05
  scene.add(sun, sun.target)

  const parts = map?.parts ?? []
  buildParts(scene, parts, track)
  if (map?.terrain) buildTerrain(scene, map.terrain, track)

  // nothing exported yet: a floor so the replay isn't floating in space
  if (parts.length === 0 && !map?.terrain) {
    const floor = new THREE.Mesh(
      track(new THREE.PlaneGeometry(2000, 2000).rotateX(-Math.PI / 2)),
      track(new THREE.MeshStandardMaterial({ color: 0x3b4252, roughness: 1 })),
    )
    floor.position.set(center.x, floorY, center.z)
    floor.receiveShadow = true
    scene.add(floor)
    const grid = new THREE.GridHelper(600, 150, 0x566074, 0x4a5366)
    grid.position.set(center.x, floorY + 0.02, center.z)
    scene.add(grid)
  }

  return { sunDir: sky.sunDir, sun, dispose: () => disposables.forEach((d) => d.dispose()) }
}

function buildParts(scene: THREE.Scene, parts: MapPart[], track: <T extends { dispose(): void }>(x: T) => T) {
  const shapes: Record<number, THREE.BufferGeometry> = {
    0: track(new THREE.BoxGeometry(1, 1, 1)),
    1: track(new THREE.SphereGeometry(0.5, 20, 14)),
    2: track(new THREE.CylinderGeometry(0.5, 0.5, 1, 20).rotateZ(Math.PI / 2)),
    3: track(wedgeGeometry()),
    4: track(new THREE.BoxGeometry(1, 1, 1)),
    5: track(cornerWedgeGeometry()),
    6: track(new THREE.BoxGeometry(1, 1, 1)),
  }

  // one instanced mesh per shape + material + transparency step
  const groups = new Map<string, MapPart[]>()
  for (const p of parts) {
    const shape = p[10] in shapes ? p[10] : 0
    const mat = p.length > 11 ? p[11] : 0
    const alpha = p.length > 12 ? Math.round(p[12] / 25) * 25 : 0 // 0, 25, 50, 75
    const key = `${shape}|${mat}|${shape === 6 ? 50 : alpha}`
    let list = groups.get(key)
    if (!list) groups.set(key, (list = []))
    list.push(p)
  }

  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), color = new THREE.Color()
  const pos = new THREE.Vector3(), scale = new THREE.Vector3()
  for (const [key, list] of groups) {
    const [shape, matCode, alpha] = key.split('|').map(Number)
    const look = surface(matCode)
    const opacity = Math.min(look.opacity ?? 1, 1 - alpha / 100)
    const see = { transparent: opacity < 0.99, opacity, depthWrite: opacity >= 0.99 }
    // neon ignores lighting and shows its own color at full strength, like in game
    const material = track(
      look.emissive
        ? new THREE.MeshBasicMaterial({ ...see, toneMapped: false })
        : new THREE.MeshStandardMaterial({ ...see, roughness: look.roughness, metalness: look.metalness }),
    )
    const mesh = new THREE.InstancedMesh(shapes[shape], material, list.length)
    list.forEach((p, i) => {
      e.set(p[6], p[7], p[8], 'XYZ')
      q.setFromEuler(e)
      m.compose(pos.set(p[0], p[1], p[2]), q, scale.set(p[3], p[4], p[5]))
      mesh.setMatrixAt(i, m)
      // setHex takes srgb, three converts to its linear working space itself
      color.setHex(p[9])
      mesh.setColorAt(i, color)
    })
    mesh.castShadow = opacity > 0.6 && !look.emissive
    mesh.receiveShadow = true
    scene.add(mesh)
  }
}

function buildTerrain(scene: THREE.Scene, t: Terrain, track: <T extends { dispose(): void }>(x: T) => T) {
  const grid = (heights: number[], colorOf: (i: number) => THREE.Color) => {
    const positions: number[] = [], colors: number[] = [], index: number[] = []
    const vert = new Int32Array(t.cols * t.rows).fill(-1)
    let n = 0
    for (let row = 0; row < t.rows; row++) {
      for (let col = 0; col < t.cols; col++) {
        const i = row * t.cols + col
        if (heights[i] <= -99990) continue
        positions.push(t.x0 + (col + 0.5) * t.step, heights[i], t.z0 + (row + 0.5) * t.step)
        const c = colorOf(i)
        colors.push(c.r, c.g, c.b)
        vert[i] = n++
      }
    }
    for (let row = 0; row < t.rows - 1; row++) {
      for (let col = 0; col < t.cols - 1; col++) {
        const a = vert[row * t.cols + col], b = vert[row * t.cols + col + 1]
        const c = vert[(row + 1) * t.cols + col], d = vert[(row + 1) * t.cols + col + 1]
        if (a >= 0 && c >= 0 && b >= 0) index.push(a, c, b)
        if (b >= 0 && c >= 0 && d >= 0) index.push(b, c, d)
      }
    }
    if (index.length === 0) return null
    const g = track(new THREE.BufferGeometry())
    g.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
    g.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3))
    g.setIndex(index)
    g.computeVertexNormals()
    return g
  }

  const palette = new Map<number, THREE.Color>()
  const colorFor = (m: number) => {
    let c = palette.get(m)
    if (!c) {
      c = new THREE.Color(t.palette[String(m)] ?? 0x6a7f3f)
      palette.set(m, c)
    }
    return c
  }

  const ground = grid(t.h, (i) => colorFor(t.m[i]))
  if (ground) {
    const mesh = new THREE.Mesh(ground, track(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, flatShading: false })))
    mesh.receiveShadow = true
    mesh.castShadow = true
    scene.add(mesh)
  }
  const waterColor = colorFor(22)
  const water = grid(t.w, () => waterColor)
  if (water) {
    const mesh = new THREE.Mesh(
      water,
      track(
        new THREE.MeshStandardMaterial({
          vertexColors: true,
          roughness: 0.1,
          metalness: 0.2,
          transparent: true,
          opacity: Math.max(0.35, 1 - t.water * 0.8),
          depthWrite: false,
        }),
      ),
    )
    mesh.receiveShadow = true
    scene.add(mesh)
  }
}

// roblox lighting -> sky colors, sun and fog
function skyLook(sky: Sky | null) {
  const sunDir = new THREE.Vector3(...(sky?.sun ?? [0.45, 0.75, 0.3])).normalize()
  const day = THREE.MathUtils.clamp(sunDir.y * 3 + 0.35, 0, 1)
  const dusk = THREE.MathUtils.clamp(1 - Math.abs(sunDir.y) * 5, 0, 1)
  const mix = (a: string, b: string, k: number) => new THREE.Color(a).lerp(new THREE.Color(b), k)

  const top = mix('#0b1230', '#3f8fe6', day)
  const horizon = mix('#1c2448', '#bcdcff', day).lerp(new THREE.Color('#f5a45c'), dusk * 0.45 * day + dusk * 0.15)
  if (sky?.haze != null && (sky.density ?? 0) > 0.2) horizon.lerp(new THREE.Color(sky.haze), Math.min(0.6, sky.density!))
  const ground = mix('#0d1018', '#8a95a3', day)
  const fogEnd = sky?.fogEnd && sky.fogEnd < 5000 ? sky.fogEnd : 900 + (1 - (sky?.density ?? 0.3)) * 900
  const fog = sky?.fogEnd && sky.fogEnd < 5000 && sky.fog != null ? new THREE.Color(sky.fog) : horizon.clone()
  const brightness = sky?.brightness ?? 2

  // below the horizon the "sun" is the moon: dim and blue, from the other side
  const lightDir = sunDir.y > -0.05 ? sunDir.clone() : sunDir.clone().negate()
  return {
    top,
    horizon,
    ground,
    groundLight: new THREE.Color(sky?.ambient ?? 0x80868f).multiplyScalar(0.6 + day * 0.4),
    hemi: 0.45 + day * 0.55,
    sunDir: lightDir,
    sunColor: sunDir.y > -0.05 ? mix('#ffc38a', '#fff8ec', THREE.MathUtils.clamp(sunDir.y * 4, 0, 1)) : new THREE.Color('#8fa8ff'),
    sunIntensity: sunDir.y > -0.05 ? 0.9 + Math.min(brightness, 5) * 0.35 * day : 0.25,
    fog,
    fogNear: Math.min(fogEnd * 0.35, 400),
    fogFar: Math.max(fogEnd, 200),
  }
}
