// UI-independent hooks used by the upstream OGLES test runner.
const sourceRequest = new XMLHttpRequest();
sourceRequest.open("GET", "case.json", false);
sourceRequest.send();
const descriptor = JSON.parse(sourceRequest.responseText);
const result = { passes: 0, errors: [] };
function debug() {}
function description() {}
function quietMode() {
  return true;
}
function testPassed() {
  result.passes++;
}
function testFailed(message) {
  result.errors.push(String(message));
}
function finishTest() {
  console.log(JSON.stringify(result));
}
const WebGLTestUtils = {
  create3DContext(canvas) {
    return canvas.getContext("webgl", { antialias: false });
  },
  loadTextFileAsync(path, cb) {
    const text = descriptor.sources[path];
    cb(typeof text === "string", text);
  },
  loadShader(gl, source, type) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS))
      throw Error(gl.getShaderInfoLog(shader));
    return shader;
  },
  createProgram(gl, v, f) {
    const p = gl.createProgram();
    gl.attachShader(p, v);
    gl.attachShader(p, f);
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS))
      throw Error(gl.getProgramInfoLog(p));
    return p;
  },
  glErrorShouldBe(gl, expected, message) {
    const code = gl.getError();
    if (code !== expected) testFailed(message + " (" + code + ")");
  },
  glEnumToString(gl, n) {
    return String(n);
  },
  // Quiet mode reports the upstream pixel comparisons and skips its HTML image previews.
  makeImageFromCanvas() {
    return null;
  },
};
