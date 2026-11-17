// Run upstream shader sources and expectations through the application's own WebGL API.
const gl = document
  .getElementById("gpu")
  .getContext("webgl", { antialias: false });
const xhr = new XMLHttpRequest();
xhr.open("GET", "cases.json", false);
xhr.send();
if (xhr.status !== 200) throw Error("Could not load Khronos descriptors");
const data = JSON.parse(xhr.responseText);
const cases = data.cases;
for (const name of data.methods) {
  if (typeof gl[name] !== "function") throw Error("Missing context method " + name);
}
for (const name of Object.keys(data.constants)) {
  if (gl[name] !== data.constants[name]) throw Error("Wrong context constant " + name);
}
const results = [];
function compile(kind, source) {
  const shader = gl.createShader(kind);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  return shader;
}
for (let i = 0; i < cases.length; i++) {
  const test = cases[i];
  const v = compile(gl.VERTEX_SHADER, test.vertex),
    f = compile(gl.FRAGMENT_SHADER, test.fragment);
  const compiled =
    gl.getShaderParameter(v, gl.COMPILE_STATUS) &&
    gl.getShaderParameter(f, gl.COMPILE_STATUS);
  let linked = null,
    log = "";
  if (test.compile) {
    const p = gl.createProgram();
    gl.attachShader(p, v);
    gl.attachShader(p, f);
    gl.linkProgram(p);
    linked = gl.getProgramParameter(p, gl.LINK_STATUS);
    if (linked !== test.link) log = gl.getProgramInfoLog(p);
    gl.deleteProgram(p);
  }
  const passed =
    compiled === test.compile && (!test.compile || linked === test.link);
  if (!passed) log += gl.getShaderInfoLog(v) + gl.getShaderInfoLog(f);
  results.push({
    name: test.name,
    compiled: compiled,
    linked: linked,
    passed: passed,
    log: log,
  });
  gl.deleteShader(v);
  gl.deleteShader(f);
}
console.log(JSON.stringify(results));
