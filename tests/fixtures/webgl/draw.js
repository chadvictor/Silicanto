const canvas = document.getElementById("view");
const gl = canvas.getContext("webgl", {
  alpha: false,
  antialias: false,
  preserveDrawingBuffer: true,
});
if (!gl || canvas.getContext("2d") !== null)
  throw new Error("context selection");
function shader(type, source) {
  const s = gl.createShader(type);
  gl.shaderSource(s, source);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS))
    throw new Error(gl.getShaderInfoLog(s));
  return s;
}
const program = gl.createProgram();
gl.attachShader(
  program,
  shader(
    gl.VERTEX_SHADER,
    "attribute vec2 p; void main(){gl_Position=vec4(p,0.,1.);}",
  ),
);
gl.attachShader(
  program,
  shader(
    gl.FRAGMENT_SHADER,
    "precision mediump float; uniform vec4 tint; void main(){gl_FragColor=tint;}",
  ),
);
gl.linkProgram(program);
if (!gl.getProgramParameter(program, gl.LINK_STATUS))
  throw new Error(gl.getProgramInfoLog(program));
gl.useProgram(program);
const buffer = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
gl.bufferData(
  gl.ARRAY_BUFFER,
  new Float32Array([-1, -1, 1, -1, -1, 1]),
  gl.STATIC_DRAW,
);
const p = gl.getAttribLocation(program, "p");
gl.enableVertexAttribArray(p);
gl.vertexAttribPointer(p, 2, gl.FLOAT, false, 0, 0);
const tint = gl.getUniformLocation(program, "tint");
let rejected = false;
try { gl.uniform4fv(tint, 1); } catch (err) { rejected = err instanceof TypeError; }
if (!rejected || gl.getError() !== gl.NO_ERROR) throw Error("uniform sequence conversion");
gl.uniform4f(tint, 1, 0, 0, 1);
gl.clearColor(0, 0, 1, 1);
gl.clear(gl.COLOR_BUFFER_BIT);
gl.drawArrays(gl.TRIANGLES, 0, 3);
const pixel = new Uint8Array(4);
gl.readPixels(1, 1, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
if (pixel[0] !== 255 || pixel[2] !== 0 || gl.getError() !== gl.NO_ERROR)
  throw new Error("draw/readPixels");

const textSurface = document.createElement("canvas");
textSurface.width = 100;
textSurface.height = 42;
const context = textSurface.getContext("2d");
context.font = "24px Arial";
const metrics = context.measureText("Silicon");
if (
  metrics.width < 40 ||
  metrics.width > 100 ||
  metrics.actualBoundingBoxAscent < 10
)
  throw new Error("glyph metrics");
context.fillStyle = "#fff";
context.fillText("Silicon", 0, 32);
const bitmap = context.getImageData(0, 0, 100, 42).data;
let ink = 0;
for (let i = 3; i < bitmap.length; i += 4) if (bitmap[i] > 0) ink++;
if (ink < 90 || ink > 1400) throw new Error("glyph coverage");

const array = Array.from(new Uint8Array([1, 2, 3]).subarray(1), (x) => x * 2);
const object = JSON.parse('{"a":1,"b":2}', (key, value) =>
  key === "a" ? value + 1 : value,
);
if (
  JSON.stringify([array, object.b]) !== "[[4,6],2]" ||
  Object.entries(object).length !== 2 ||
  !array.hasOwnProperty(0) ||
  !Number.isInteger(object.a) ||
  btoa(atob("YWJj")) !== "YWJj" ||
  "12".replace(/./g, (value) => Number(value).toString(16)) !== "12"
)
  throw new Error("standard library");
