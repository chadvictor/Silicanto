import { clamp, lerp } from "three/src/math/MathUtils.js";
class Elevation {
  constructor(ceiling) {
    this.ceiling = ceiling;
  }
  interpolate(t) {
    return this.ceiling * t;
  }
}
const elevation = new Elevation(4);

export function sampleHeight(radius, altitude) {
  return 1 + elevation.interpolate(lerp(0, 1, clamp(radius + altitude, 0, 1)));
}
