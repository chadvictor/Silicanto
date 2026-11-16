// Authoring source for NÁCAR. Generates the same Three.js scene used on the web and on Metal.
import * as T from "three";
import { twilightProbe } from "./probe.mjs";

const scene = new T.Scene();
scene.name = "Nácar · Silicon Sea";
scene.background = new T.Color(0x956b82);
scene.fog = new T.FogExp2(0xab8297, 0.0105);
const { sin, cos, exp, abs, pow, max, min, floor, PI } = Math;
const tau = 2 * PI;
let seed = 473817;
function rand() {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed / 4294967296;
}
function range(a, b) {
  return a + (b - a) * rand();
}
function hash(x, y) {
  const n = sin(x * 127.1 + y * 311.7) * 43758.5453;
  return n - floor(n);
}
const mix = (a, b, t) => a + (b - a) * t;
const sat = (x) => max(0, min(1, x));
const smooth = (x) => x * x * (3 - 2 * x);
function noise(x, y) {
  const a = floor(x),
    b = floor(y),
    u = smooth(x - a),
    v = smooth(y - b);
  return mix(
    mix(hash(a, b), hash(a + 1, b), u),
    mix(hash(a, b + 1), hash(a + 1, b + 1), u),
    v,
  );
}
function fbm(x, y) {
  return (
    0.54 * noise(x, y) +
    0.27 * noise(x * 2.08 + 7, y * 2.08) +
    0.13 * noise(x * 4.3, y * 4.3 + 8) +
    0.06 * noise(x * 8.9, y * 8.9)
  );
}
function rgb(hex) {
  return new T.Color(hex);
}
function standard(color, metalness, roughness, more = {}) {
  return new T.MeshStandardMaterial({ color, metalness, roughness, ...more });
}
function basic(color, more = {}) {
  return new T.MeshBasicMaterial({ color, ...more });
}
function mesh(g, m, name) {
  const o = new T.Mesh(g, m);
  o.name = name;
  scene.add(o);
  return o;
}
function dataGeometry(positions, colors, indices) {
  const g = new T.BufferGeometry();
  g.setAttribute("position", new T.Float32BufferAttribute(positions, 3));
  if (colors) g.setAttribute("color", new T.Float32BufferAttribute(colors, 3));
  if (indices) g.setIndex(indices);
  g.computeVertexNormals();
  return g;
}
function colorPush(a, c) {
  a.push(c.r, c.g, c.b);
}
function grid(nx, ny, vertex) {
  const p = [],
    c = [],
    i = [];
  for (let y = 0; y <= ny; y++)
    for (let x = 0; x <= nx; x++) {
      const [vx, vy, vz, color] = vertex(x / nx, y / ny);
      p.push(vx, vy, vz);
      colorPush(c, color);
      if (x < nx && y < ny) {
        const a = y * (nx + 1) + x,
          b = a + 1,
          d = a + nx + 1;
        i.push(a, b, d, b, d + 1, d);
      }
    }
  return dataGeometry(p, c, i);
}

// A sky painted by scattering bands and interstellar dust. Its distant geometry carries the parallax.
const zenith = rgb(0x12142f),
  dusk = rgb(0x48315e),
  haze = rgb(0xe0a394);
const sky = grid(150, 88, (u, v) => {
  const x = mix(-340, 340, u),
    y = mix(-58, 205, v);
  const h = sat((y + 2) / 128);
  const c = haze
    .clone()
    .lerp(dusk, 1 - exp(-3.6 * h))
    .lerp(zenith, smooth(sat(h * 1.1)));
  const w = fbm(x * 0.031, y * 0.095),
    wisps = pow(sat((w - 0.35) * 2.4), 2);
  const belt = exp(-pow((y - 42 - 0.21 * x - 7 * sin(x * 0.025)) / 13, 2));
  const dust = fbm(x * 0.065 + 41, y * 0.105 + 22);
  c.lerp(rgb(0xe7b3c3), belt * wisps * 0.62);
  c.lerp(rgb(0x75669c), 0.34 * exp(-pow((y - 53 - 0.19 * x) / 6, 2)) * dust);
  c.multiplyScalar(1 - 0.27 * belt * pow(1 - dust, 2));
  c.lerp(
    rgb(0xf9c6a3),
    0.32 * exp(-pow((x + 145) / 78, 2) - pow((y - 7) / 23, 2)),
  );
  return [x, y, -220, c];
});
mesh(
  sky,
  basic(0xffffff, { vertexColors: true, fog: false, side: T.DoubleSide }),
  "Twilight halo",
);

const starP = [],
  starC = [];
function star(x, y, z, r, col, stretch = 1) {
  const xy = [
    [0, r * stretch],
    [-r, 0],
    [0, -r * stretch],
    [r, 0],
  ];
  for (const idx of [0, 1, 2, 0, 2, 3]) {
    starP.push(x + xy[idx][0], y + xy[idx][1], z);
    colorPush(starC, col);
  }
}
for (let i = 0; i < 3600; i++) {
  const x = range(-220, 220),
    y = range(1, 145),
    r = 0.024 + pow(rand(), 5) * 0.16;
  const c = rgb(0xdad8ff)
    .lerp(rgb(0xffdab3), rand())
    .multiplyScalar(range(0.28, 1.1) * sat(y / 14));
  star(x, y, -203, r, c);
  if (r > 0.173 && i % 4 === 0) star(x, y, -202.99, r * 0.34, c, 4.3);
}
mesh(
  dataGeometry(starP, starC),
  basic(0xffffff, { vertexColors: true, fog: false, side: T.DoubleSide }),
  "Stardust",
);

// A ringed body with cloud belts, a soft terminator and a scattering rim.
const planetCenter = new T.Vector3(-41, 27, -103),
  radius = 11.8;
const planet = new T.SphereGeometry(radius, 140, 88),
  planetColors = [];
const axis = new T.Vector3(-0.35, 0.92, 0.08).normalize(),
  sun = new T.Vector3(-0.68, 0.52, 0.48).normalize();
for (let i = 0; i < planet.attributes.position.count; i++) {
  const n = new T.Vector3().fromBufferAttribute(planet.attributes.normal, i);
  const lat = n.dot(axis),
    perturb =
      0.009 * sin(n.x * 7 + lat * 9) +
      0.009 * sin(n.z * 8 - lat * 19) +
      0.021 * fbm(n.x * 3 + lat * 5, n.z * 3);
  const bands =
    0.5 +
    0.5 * sin(42 * (lat + perturb) + 2 * sin(lat * 9)) * 0.73 +
    0.12 * sin(lat * 147 + n.x * 4);
  const base = rgb(0x91687f)
    .lerp(rgb(0xf3ba94), sat(bands))
    .lerp(rgb(0xffe1b7), 0.2 * noise(lat * 45, n.x * 5));
  const light = smooth(sat((n.dot(sun) + 0.16) / 1.16));
  base
    .multiplyScalar(0.2 + light * 0.82)
    .lerp(rgb(0xb398b5), 0.22 * pow(1 - abs(n.z), 3));
  colorPush(planetColors, base);
}
planet.setAttribute("color", new T.Float32BufferAttribute(planetColors, 3));
mesh(
  new T.BufferGeometry().copy(planet),
  basic(0xffffff, { vertexColors: true, fog: false }),
  "Nácar Major",
).position.copy(planetCenter);
const ring = grid(182, 125, (u, v) => {
  const r = radius * (1.17 + v * 1.22),
    a = tau * u;
  const opacity = sat(
    0.16 +
      0.48 * pow(0.5 + 0.5 * cos(v * 48), 0.6) +
      0.24 * sin(v * 191) +
      0.13 * sin(v * 353),
  );
  const c = rgb(0x806580)
    .lerp(rgb(0xe6bbaa), opacity)
    .multiplyScalar(0.77 + 0.16 * cos(a + 0.7));
  return [r * cos(a), 0, r * sin(a), c];
});
// Cut narrow gaps in the rings rather than painting black stripes across the sky.
const ringIndices = [];
for (let row = 0; row < 125; row++) {
  const t = (row + 0.5) / 125;
  if (
    t < 0.035 ||
    (t > 0.38 && t < 0.475) ||
    (t > 0.79 && t < 0.83) ||
    (t > 0.91 && row % 3 !== 0)
  )
    continue;
  for (let j = 0; j < 182; j++) {
    const a = row * 183 + j;
    ringIndices.push(a, a + 1, a + 183, a + 1, a + 184, a + 183);
  }
}
ring.setIndex(ringIndices);
const rings = mesh(
  ring,
  basic(0xffffff, { vertexColors: true, fog: false, side: T.DoubleSide }),
  "Dust rings",
);
rings.position.copy(planetCenter);
rings.rotation.order = "ZXY";
rings.rotation.z = 0.46;
rings.rotation.x = -0.095;

// Far basalt escarpments recede into the dusty atmosphere.
for (let k = 0; k < 3; k++) {
  const z = -82 + k * 15;
  const ridge = grid(200, 12, (u, v) => {
    const x = mix(-140, 140, u);
    const crest =
      2.0 +
      10 * fbm(x * 0.075, k * 7) +
      4.7 * pow(noise(x * 0.2, k + 3), 2) +
      1.6 * sin(x * 0.18 + k);
    const corrugation = fbm(x * 0.25, v * 5 + k);
    const y = mix(-3, crest, v) + 4.6 * sin(PI * v) * (corrugation - 0.35);
    const col = rgb(0x372c48).lerp(
      rgb(0xa17b88),
      sat(0.2 + 0.6 * v + 0.25 * noise(x * 0.2, v * 3)),
    );
    return [x, y, z - (v * 13 + 3.9 * noise(x * 0.14 + v, k)), col];
  });
  mesh(
    ridge,
    standard(0xffffff, 0.14, 0.79, {
      vertexColors: true,
      side: T.DoubleSide,
      flatShading: true,
    }),
    "Escarpment " + k,
  );
}
const riverX = (z) =>
  -2 + 3.1 * sin(z * 0.105 + 0.45) + 1.7 * sin(z * 0.225 - 1);
const riverWidth = (z) => 1.9 + 0.45 * sin(z * 0.112);
function height(x, z) {
  const d = abs(x - riverX(z)) / riverWidth(z);
  const h =
    (fbm(x * 0.155, z * 0.145) - 0.39) * 1.55 + 0.28 * sin(z * 0.45 + x * 0.32);
  return (
    -0.49 + smooth(sat((d - 0.52) / 1.22)) * (0.72 + h + max(0, d - 4) * 0.065)
  );
}
const ground = grid(200, 178, (u, v) => {
  const x = mix(-48, 48, u),
    z = mix(28, -65, v),
    h = height(x, z);
  const d = abs(x - riverX(z)),
    n = fbm(x * 0.49, z * 0.5);
  const cleavage = pow(0.5 + 0.5 * sin(x * 5.5 - z * 1.4 + 8 * n), 9);
  const c = rgb(0x211e35)
    .lerp(rgb(0x645c77), sat((n - 0.24) * 1.7))
    .lerp(rgb(0x9a9ba3), cleavage * 0.25);
  c.lerp(rgb(0xa86858), 0.22 * exp(-d * 0.22));
  return [x, h, z, c];
});
mesh(
  ground,
  standard(0xffffff, 0.42, 0.57, { vertexColors: true, flatShading: true }),
  "Silicon crust",
);

// Streams of annealed silicon and fine hot fractures in the crust.
const channel = grid(20, 290, (u, v) => {
  const z = mix(28, -62, v),
    x = riverX(z) + mix(-1, 1, u) * riverWidth(z) * 1.3;
  const w = fbm(x * 0.9, z * 1.4),
    ribbon = pow(sat(0.5 + 0.5 * sin(29 * u + z * 0.46 + w * 4.9)), 4);
  const c = rgb(0x5d3145)
    .lerp(rgb(0xd47857), w * 0.88)
    .lerp(rgb(0xffc27c), ribbon * 0.76);
  return [x, -0.19 + 0.015 * sin(z * 3 + x), z, c];
});
mesh(
  channel,
  standard(0xffffff, 0.39, 0.41, { vertexColors: true, emissive: 0x482125 }),
  "Glass estuary",
);
const seamP = [],
  seamC = [];
for (let s = 0; s < 110; s++) {
  let z = range(-57, 18),
    x = riverX(z) + range(-5, 5),
    angle = range(0, tau),
    width = range(0.012, 0.044);
  for (let j = 0; j < 12; j++) {
    angle += range(-0.45, 0.45);
    const nx = x + sin(angle) * 0.29,
      nz = z + cos(angle) * 0.29;
    const c = rgb(j % 4 === 0 ? 0xf5a56f : 0xc87b67);
    for (const [xx, zz] of [
      [x - width, z],
      [nx - width, nz],
      [x + width, z],
      [x + width, z],
      [nx - width, nz],
      [nx + width, nz],
    ]) {
      seamP.push(xx, max(-0.178, height(xx, zz) + 0.018), zz);
      colorPush(seamC, c);
    }
    x = nx;
    z = nz;
  }
}
mesh(
  dataGeometry(seamP, seamC),
  basic(0xffffff, { vertexColors: true, side: T.DoubleSide }),
  "Incandescent seams",
);

// Faceted, twinned silicon columns. Each facet has a distinct growth pattern and basal bevel.
const columnsP = [],
  columnsC = [],
  occluders = [];
const palette = [
  "#343551",
  "#625575",
  "#8a7caa",
  "#69678f",
  "#bca3aa",
  "#405976",
  "#9f809f",
  "#d2a899",
].map(rgb);
function column(cx, cz, r, h, leanX, leanZ, phase) {
  occluders.push({ cx, cz, r, h, leanX, leanZ });
  const n = 6 + floor(rand() * 2),
    base = height(cx, cz) - 0.32,
    mats = [];
  const radii = Array.from({ length: n }, () => range(0.85, 1.12));
  for (let i = 0; i < n; i++)
    mats.push(
      palette[(i + floor(rand() * palette.length)) % palette.length].clone(),
    );
  const levels = [
    [0, 0.83],
    [0.12, 1],
    [0.73, 0.96],
    [0.85, 0.85],
    [1, 0.08],
  ];
  const rings = levels.map(([y, rad], j) =>
    Array.from({ length: n }, (_, i) => {
      const a = phase + (i * tau) / n;
      return new T.Vector3(
        cx + leanX * y + cos(a) * r * radii[i] * rad,
        base + h * y + (j === 3 ? 0.065 * h * cos(a - 0.7) : 0),
        cz + leanZ * y + sin(a) * r * radii[i] * rad,
      );
    }),
  );
  function tri(a, b, c, color) {
    for (const v of [a, b, c]) {
      columnsP.push(v.x, v.y, v.z);
      colorPush(columnsC, color);
    }
  }
  for (let i = 0; i < n; i++) {
    const k = (i + 1) % n;
    for (let j = 0; j < 4; j++) {
      const a = rings[j][i],
        b = rings[j][k],
        c = rings[j + 1][k],
        d = rings[j + 1][i];
      const color = mats[i].clone().multiplyScalar([0.46, 0.9, 1.1, 1.37][j]);
      if (j === 1 && h > 2) {
        // Successive growth terraces catch the sky at slightly different angles.
        const bands = 12,
          radial = new T.Vector3()
            .crossVectors(d.clone().sub(a), b.clone().sub(a))
            .normalize();
        const rows = [];
        for (let q = 0; q <= bands; q++) {
          const t = q / bands,
            ridge = (q % 4 === 2 ? 0.022 : 0) * r;
          rows.push([
            a.clone().lerp(d, t).addScaledVector(radial, ridge),
            b.clone().lerp(c, t).addScaledVector(radial, ridge),
          ]);
        }
        for (let q = 0; q < bands; q++) {
          const [l0, r0] = rows[q],
            [l1, r1] = rows[q + 1];
          const band = color
            .clone()
            .multiplyScalar(
              0.69 + (0.27 * q) / bands + 0.17 * sin(q * 2.1 + i),
            );
          tri(l0, l1, r0, band);
          tri(l1, r1, r0, band);
        }
      } else {
        tri(a, d, b, color);
        tri(d, c, b, color);
      }
      // Thin, irregular twin lamellae lie flush with selected crystal faces.
      if (j === 1 && i % 3 !== 0) {
        const stripes = 3 + floor(rand() * 8);
        for (let s = 0; s < stripes; s++) {
          const t = range(0.06, 0.94),
            span = range(0.12, 0.88),
            v = range(0.001, 0.007);
          const normal = new T.Vector3()
            .crossVectors(d.clone().sub(a), b.clone().sub(a))
            .normalize()
            .multiplyScalar(0.004);
          const point = (u, v) =>
            a.clone().lerp(b, u).lerp(d.clone().lerp(c, u), v).add(normal);
          const tint = color.clone().lerp(rgb(0xd3bbcc), range(0.16, 0.52));
          tri(
            point(0, t),
            point(span, t + v + 0.034 * span),
            point(span, t + 0.034 * span),
            tint,
          );
          tri(
            point(0, t),
            point(0, t + v),
            point(span, t + v + 0.034 * span),
            tint,
          );
        }
      }
    }
    tri(
      rings[4][i],
      new T.Vector3(cx + leanX, base + h * 1.012, cz + leanZ),
      rings[4][k],
      mats[i],
    );
  }
}
function cluster(x, z, h, r, count) {
  const phase = range(0, tau);
  column(x, z, r, h, h * 0.14, h * 0.018, phase);
  for (let i = 0; i < count; i++) {
    const a = phase + i * 2.4,
      f = range(0.28, 0.76),
      distance = r * range(0.6, 1.65);
    column(
      x + cos(a) * distance,
      z + sin(a) * distance,
      r * range(0.3, 0.68),
      h * f,
      cos(a) * h * f * 0.38,
      sin(a) * h * f * 0.29,
      range(0, tau),
    );
  }
}
cluster(6, -7, 10.5, 1.32, 12);
cluster(-7, 1.7, 6.3, 1.03, 9);
cluster(-12, -14, 8.1, 1.08, 10);
cluster(12, 5, 7.9, 1.48, 11);
cluster(3.7, -28, 8.6, 0.99, 9);
for (let i = 0; i < 123; i++) {
  const x = range(-32, 32),
    z = range(-54, 15);
  if (abs(x - riverX(z)) < riverWidth(z) * 1.38 || (abs(x) < 5 && z > -2))
    continue;
  const h = range(0.55, 4.6) * (z > 6 ? 0.62 : 1);
  cluster(x, z, h, h * range(0.1, 0.22), 2 + floor(rand() * 4));
}
mesh(
  dataGeometry(columnsP, columnsC),
  standard(0xffffff, 0.76, 0.24, { vertexColors: true, flatShading: true }),
  "Single-crystal gardens",
);

// Baked horizon occlusion under each crystal grounds it in the static landscape.
const soil = ground.getAttribute("color"),
  terrain = ground.getAttribute("position");
for (let i = 0; i < terrain.count; i++) {
  const x = terrain.getX(i),
    z = terrain.getZ(i);
  let shade = 0;
  for (const o of occluders) {
    const dx = x - o.cx,
      dz = z - o.cz,
      reach = o.h * 1.25;
    if (dx < -2 * o.r || dx > reach + o.r * 3 || abs(dz) > reach + o.r * 3)
      continue;
    const sx = o.leanX / o.h + 0.97,
      sz = o.leanZ / o.h + 0.47;
    const t = sat((dx * sx + dz * sz) / (o.h * (sx * sx + sz * sz)));
    const distance = Math.hypot(dx - sx * t * o.h, dz - sz * t * o.h);
    const penumbra = o.r * (1.25 - 0.47 * t) + 0.22;
    shade = max(shade, smooth(sat(1 - distance / penumbra)) * (1 - 0.45 * t));
  }
  const factor = 1 - 0.74 * shade;
  soil.setXYZ(
    i,
    soil.getX(i) * factor,
    soil.getY(i) * factor,
    soil.getZ(i) * (1 - 0.6 * shade),
  );
}

// A fractured toroid of polished silicon hangs over the channel. Each arc is an actual
// bevelled solid with radial cut faces and an electroluminescent layer on its inner wall.
const relic = new T.Group();
relic.name = "The growth ring";
scene.add(relic);
relic.position.set(-0.8, 4.9, -13);
relic.rotation.set(-0.15, -0.38, -0.16);
const shellMat = standard(0x9987a5, 0.81, 0.23, { flatShading: true });
const coreMat = standard(0xffd591, 0.24, 0.34, {
  emissive: 0xf39a47,
  emissiveIntensity: 0.66,
});
for (let j = 0; j < 15; j++) {
  const a = (j * tau) / 15,
    length = tau / 15 - (j % 4 === 0 ? 0.067 : 0.028);
  const radial = j % 4 === 0 ? 0.1 : 0,
    radius = 3.53 + radial;
  const segment = new T.Mesh(
    new T.TorusGeometry(radius, 0.28, 6, 12, length),
    shellMat,
  );
  segment.rotation.z = a;
  segment.position.z = 0.045 * sin(j * 2.1);
  relic.add(segment);
  const fillet = new T.Mesh(
    new T.TorusGeometry(radius - 0.22, 0.035, 6, 12, length),
    coreMat,
  );
  fillet.rotation.z = a;
  fillet.position.z = 0.15;
  relic.add(fillet);
}
const seedCrystal = new T.Mesh(
  new T.OctahedronGeometry(0.7),
  standard(0xcbd0cb, 0.62, 0.2, { emissive: 0x302334 }),
);
seedCrystal.scale.set(0.75, 2.0, 0.74);
seedCrystal.rotation.set(0.11, 0.7, -0.12);
relic.add(seedCrystal);

// Fragments deposited along the shoreline, mostly flattened octahedra.
const chipsP = [],
  chipsC = [];
const oct = new T.OctahedronGeometry(1),
  vp = oct.attributes.position;
for (let i = 0; i < 1800; i++) {
  const z = range(-39, 21),
    x = range(-27, 27),
    h = height(x, z);
  if (h < -0.19) continue;
  const r = 0.035 + pow(rand(), 3) * 0.33,
    orient = range(0, tau),
    y = h + r * 0.16;
  const c = palette[floor(rand() * palette.length)]
    .clone()
    .multiplyScalar(range(0.36, 1.05));
  for (let j = 0; j < vp.count; j++) {
    const u = vp.getX(j) * r,
      v = vp.getZ(j) * r * 1.6;
    chipsP.push(
      x + u * cos(orient) - v * sin(orient),
      y + vp.getY(j) * r * 0.49,
      z + u * sin(orient) + v * cos(orient),
    );
    colorPush(chipsC, c);
  }
}
mesh(
  dataGeometry(chipsP, chipsC),
  standard(0xffffff, 0.47, 0.42, { vertexColors: true, flatShading: true }),
  "Cleavage fragments",
);
scene.add(new T.HemisphereLight(0xffdfed, 0x9096ca, 1.04));
for (const [color, power, pos] of [
  [0xffdec0, 2.8, [-18, 15, -9]],
  [0xb7d7ff, 1.8, [12, 8, 10]],
  [0xffa5a2, 1.1, [3, 5, -18]],
]) {
  const l = new T.DirectionalLight(color, power);
  l.position.set(...pos);
  scene.add(l);
}
scene.environment = twilightProbe();
scene.environmentIntensity = 0.94;
scene.updateMatrixWorld(true);
export default scene;
