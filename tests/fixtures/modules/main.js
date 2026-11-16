import { sampleHeight } from "./height.js";

const heights = [];
for (let i = 0; i < 5; ++i) heights.push(sampleHeight(i / 4, 0));
const vertices = new Float32Array(heights);
const shift = (height, offset) => height + offset;
let sum = 0;
for (let i = 0; i < vertices.length; ++i) {
  vertices[i] = shift(vertices[i], 0.125);
  sum += vertices[i];
}
console.log(sum);
