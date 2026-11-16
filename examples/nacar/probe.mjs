import * as T from "three";

// Linear HDR sky and the hot shoreline reflected by the silicon. Integrate the
// radiance into Three.js's cube-UV roughness levels during application startup.
export function twilightProbe() {
  const faceSize = 64,
    width = 336,
    height = 4 * faceSize;
  const pixels = new Float32Array(width * height * 4);
  const up = new T.Vector3(),
    tangent = new T.Vector3(),
    bitangent = new T.Vector3(),
    n = new T.Vector3();
  const key = new T.Vector3(-0.77, 0.16, -0.48).normalize(),
    blue = new T.Vector3(0.67, 0.54, 0.32).normalize();
  const golden = 2.399963229728653;
  const roughness = [1, 0.8, 0.667, 0.533, 0.4, 0.305, 0.21, 0.152, 0.108];
  for (let mip = -2; mip <= 6; mip++) {
    const size = Math.max(16, 2 ** mip),
      r = roughness[mip + 2],
      samples = 64;
    for (let face = 0; face < 6; face++)
      for (let y = 0; y < size; y++)
        for (let x = 0; x < size; x++) {
          const u = ((x + 0.5 - 1) / (size - 2)) * 2 - 1,
            v = ((y + 0.5 - 1) / (size - 2)) * 2 - 1;
          n.set(
            ...[
              [1, v, u],
              [-u, 1, -v],
              [-u, v, 1],
              [-1, v, -u],
              [-u, -1, v],
              [u, v, -1],
            ][face],
          ).normalize();
          up.set(0, Math.abs(n.y) > 0.98 ? 0 : 1, Math.abs(n.y) > 0.98 ? 1 : 0);
          tangent.crossVectors(up, n).normalize();
          bitangent.crossVectors(n, tangent);
          let red = 0,
            green = 0,
            blueChannel = 0,
            weight = 0;
          for (let j = 0; j < samples; j++) {
            const q = (j + 0.5) / samples,
              a = golden * j;
            const ny = Math.sqrt((1 - q) / (1 + (r ** 4 - 1) * q));
            const cosTheta = 2 * ny * ny - 1;
            if (cosTheta <= 0) continue;
            const radial = Math.sqrt(1 - cosTheta * cosTheta);
            const dx = radial * Math.cos(a),
              dy = radial * Math.sin(a);
            const X = n.x * cosTheta + tangent.x * dx + bitangent.x * dy;
            const Y = n.y * cosTheta + tangent.y * dx + bitangent.y * dy;
            const Z = n.z * cosTheta + tangent.z * dx + bitangent.z * dy;
            const horizon = Math.exp(-Math.abs(Y - 0.085) * 10),
              sky = Math.max(0, Y);
            const sun =
              8.5 * Math.exp((X * key.x + Y * key.y + Z * key.z - 1) * 44);
            const ice =
              3.6 * Math.exp((X * blue.x + Y * blue.y + Z * blue.z - 1) * 13);
            const stratum =
              Math.exp(
                -((Y + 0.18 + 0.11 * Math.sin(5 * X + 3 * Z)) ** 2) / 0.009,
              ) * Math.max(0, -Z);
            red +=
              (0.042 +
                0.14 * sky +
                0.72 * horizon +
                sun +
                0.44 * ice +
                0.85 * stratum) *
              cosTheta;
            green +=
              (0.035 +
                0.12 * sky +
                0.39 * horizon +
                0.62 * sun +
                0.6 * ice +
                0.23 * stratum) *
              cosTheta;
            blueChannel +=
              (0.078 +
                0.29 * sky +
                0.47 * horizon +
                0.4 * sun +
                ice +
                0.1 * stratum) *
              cosTheta;
            weight += cosTheta;
          }
          const ox = (face % 3) * size + Math.max(4 - mip, 0) * 48,
            oy = 4 * (faceSize - size) + (face >= 3 ? size : 0);
          const off = 4 * ((oy + y) * width + ox + x);
          pixels.set(
            [red / weight, green / weight, blueChannel / weight, 1],
            off,
          );
        }
  }
  const t = new T.DataTexture(pixels, width, height, T.RGBAFormat, T.FloatType);
  t.mapping = T.CubeUVReflectionMapping;
  t.minFilter = t.magFilter = T.LinearFilter;
  t.colorSpace = T.LinearSRGBColorSpace;
  t.needsUpdate = true;
  return t;
}
