import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import * as T from "three";

// Lower the static, opaque portion of a Three.js ObjectLoader document. All camera logic
// remains in the normal source-to-source compiler and is evaluated by the executable.
export function packScene(filename) {
  const bytes = readFileSync(filename);
  const document = JSON.parse(bytes);
  if (document.object?.type !== "Scene" || document.animations?.length)
    throw Error("E-SCENE: expected a static Scene with untextured geometry");
  if (
    (document.images ?? []).some(
      (i) => !i.url?.data || i.url.type !== "Float32Array",
    ) ||
    (document.textures ?? []).some(
      (t) =>
        t.uuid !== document.object.environment ||
        t.mapping !== T.CubeUVReflectionMapping,
    )
  )
    throw Error(
      "E-TEXTURE: only an embedded float cube-UV environment is supported",
    );
  for (const m of document.materials ?? []) {
    if (
      !["MeshStandardMaterial", "MeshBasicMaterial"].includes(m.type) ||
      m.transparent ||
      m.wireframe ||
      m.opacity < 1 ||
      m.depthTest === false ||
      m.depthWrite === false
    )
      throw Error(
        "E-MATERIAL: expected an opaque basic or metallic-roughness material: " +
          m.type,
      );
  }
  const scene = new T.ObjectLoader().parse(document);
  if (
    (scene.fog && !scene.fog.isFogExp2) ||
    (scene.background && !scene.background.isColor)
  )
    throw Error("E-SCENE: expected a solid background and optional FogExp2");
  scene.updateMatrixWorld(true);
  const lights = [],
    meshes = [];
  let hemi;
  scene.traverseVisible((o) => {
    if (o.isMesh) {
      if (
        o.isInstancedMesh ||
        o.isSkinnedMesh ||
        o.morphTargetInfluences?.length ||
        Array.isArray(o.material)
      )
        throw Error("E-MESH: expected a static mesh with one material");
      meshes.push(o);
    } else if (o.isDirectionalLight) {
      if (lights.length === 32)
        throw Error("E-LIGHT: at most four directional lights");
      const direction = o
        .getWorldPosition(new T.Vector3())
        .sub(o.target.getWorldPosition(new T.Vector3()))
        .normalize();
      lights.push(
        ...direction.toArray(),
        0,
        ...o.color.clone().multiplyScalar(o.intensity).toArray(),
        0,
      );
    } else if (o.isHemisphereLight && !hemi) {
      hemi = [
        ...o.getWorldPosition(new T.Vector3()).normalize().toArray(),
        0,
        ...o.color.clone().multiplyScalar(o.intensity).toArray(),
        0,
        ...o.groundColor.clone().multiplyScalar(o.intensity).toArray(),
        0,
      ];
    } else if (!(o.isScene || o.isGroup || o.type === "Object3D"))
      throw Error("E-SCENE: unsupported object " + o.type);
  });
  const chunks = [];
  for (const o of meshes) {
    const g = o.geometry,
      m = o.material,
      positions = g.getAttribute("position"),
      normals = g.getAttribute("normal"),
      colors = g.getAttribute("color");
    const count = g.index?.count ?? positions.count;
    if (
      !normals ||
      (m.vertexColors && (!colors || colors.itemSize !== 3)) ||
      g.drawRange.start !== 0 ||
      g.drawRange.count < count ||
      count % 3
    )
      throw Error(
        "E-GEOMETRY: expected complete triangles with positions, normals and optional RGB",
      );
    const data = new Float32Array(count * 16);
    const matrix = new T.Matrix3().getNormalMatrix(o.matrixWorld);
    const points = [new T.Vector3(), new T.Vector3(), new T.Vector3()];
    const normal = new T.Vector3(),
      face = new T.Vector3(),
      edge = new T.Vector3(),
      color = new T.Color();
    const ids = [0, 0, 0],
      emissive =
        m.emissive?.clone().multiplyScalar(m.emissiveIntensity) ??
        new T.Color(0);
    const reverse = o.matrixWorld.determinant() < 0;
    for (let i = 0; i < count; i += 3) {
      for (let j = 0; j < 3; j++) {
        const k = i + (reverse && j !== 0 ? 3 - j : j);
        ids[j] = g.index ? g.index.getX(k) : k;
        points[j]
          .fromBufferAttribute(positions, ids[j])
          .applyMatrix4(o.matrixWorld);
      }
      if (m.flatShading)
        face
          .subVectors(points[1], points[0])
          .cross(edge.subVectors(points[2], points[0]))
          .normalize();
      for (let j = 0; j < 3; j++) {
        const ix = ids[j],
          start = (i + j) * 16;
        if (m.flatShading) normal.copy(face);
        else normal.fromBufferAttribute(normals, ix).applyNormalMatrix(matrix);
        color.copy(m.color);
        if (m.vertexColors) {
          color.r *= colors.getX(ix);
          color.g *= colors.getY(ix);
          color.b *= colors.getZ(ix);
        }
        points[j].toArray(data, start);
        data[start + 3] = m.isMeshStandardMaterial ? m.roughness : -1;
        normal.toArray(data, start + 4);
        data[start + 7] = m.metalness ?? 0;
        color.toArray(data, start + 8);
        data[start + 11] = m.side;
        emissive.toArray(data, start + 12);
        data[start + 15] = m.fog ? 1 : 0;
      }
    }
    chunks.push(Buffer.from(data.buffer));
  }
  if (!chunks.length) throw Error("E-SCENE: empty triangle data");
  const bg = (scene.background ?? new T.Color(0)).clone().convertLinearToSRGB();
  const fog = (scene.fog?.color ?? new T.Color(0))
    .clone()
    .convertLinearToSRGB();
  const uniforms = [
    ...fog.toArray(),
    scene.fog?.density ?? 0,
    ...(hemi ?? Array(12).fill(0)),
    ...lights,
    ...Array(32 - lights.length).fill(0),
  ];
  const env = scene.environment?.image;
  if (
    env &&
    (env.height < 64 ||
      !Number.isInteger(Math.log2(env.height / 4)) ||
      env.width !== 3 * Math.max(env.height / 4, 112) ||
      env.data?.length !== 4 * env.width * env.height)
  )
    throw Error("E-PROBE: invalid Three.js cube-UV atlas");
  uniforms.push(
    env?.width ?? 0,
    env?.height ?? 0,
    env ? Math.log2(env.height / 4) : 0,
    scene.environmentIntensity,
  );
  const triangles = Buffer.concat(chunks);
  return {
    probe: env
      ? Buffer.from(env.data.buffer, env.data.byteOffset, env.data.byteLength)
      : null,
    data: deflateSync(triangles, { level: 3 }),
    metadata: {
      name: scene.name,
      vertexCount: triangles.length / 64,
      background: bg.toArray(),
      uniforms,
    },
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };
}
