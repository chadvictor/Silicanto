function check(v, message) {
  if (!v) throw new Error(message);
}
const uri = "Nácar 🌎/#";
check(
  encodeURIComponent(uri) === "N%C3%A1car%20%F0%9F%8C%8E%2F%23" &&
    decodeURIComponent(encodeURIComponent(uri)) === uri &&
    decodeURI("%2f%3F%23") === "%2f%3F%23",
  "URI Unicode and separators",
);
let badUri = false;
try {
  decodeURIComponent("%C0%AF");
} catch (e) {
  badUri = e instanceof URIError;
}
check(badUri, "invalid UTF-8 URI sequence");
function classicReceiver() {
  nativeClassicAssignment = 17;
  debugger;
  return (() => this)();
}
function strictReceiver() {
  "use strict";
  return this;
}
check(
  classicReceiver() === window &&
    classicReceiver.call(null) === window &&
    strictReceiver() === undefined &&
    strictReceiver.call(null) === null &&
    window.nativeClassicAssignment === 17,
  "strict and classic receivers",
);
const palette = document.createElement("canvas").getContext("2d");
palette.fillStyle = "LiMe";
palette.strokeStyle = "RebeccaPurple";
palette.fillStyle = "invalid-color";
palette.strokeStyle = "invalid-color";
check(
  palette.fillStyle === "#00ff00" && palette.strokeStyle === "#663399",
  "CSS color state",
);
palette.fillRect(0, 0, 1, 1);
check(
  palette.getImageData(0, 0, 1, 1).data.join(",") === "0,255,0,255",
  "named color raster",
);
const tile = document.createElement("canvas");
tile.width = 2;
tile.height = 1;
const tileCtx = tile.getContext("2d");
tileCtx.fillStyle = "red";
tileCtx.fillRect(0, 0, 1, 1);
const pat = palette.createPattern(tile, "repeat-x");
tileCtx.clearRect(0, 0, 2, 1);
pat.setTransform({ e: 1 });
palette.fillStyle = pat;
palette.fillRect(1, 0, 4, 2);
check(
  pat instanceof CanvasPattern &&
    palette.getImageData(3, 0, 1, 1).data.join(",") === "255,0,0,255" &&
    palette.getImageData(3, 1, 1, 1).data[3] === 0,
  "snapshot, transform and repeat-x pattern",
);
const canvas = document.getElementById("scene"),
  panel = document.getElementById("panel");
const gl = canvas.getContext("webgl2", { alpha: false, antialias: false });
check(
  gl instanceof WebGL2RenderingContext && canvas.getContext("webgl") === null,
  "ES3 context identity",
);
check(
  gl.getParameter(gl.VERSION).indexOf("WebGL 2.0") === 0,
  "actual ES3 version",
);
const vao = gl.createVertexArray();
gl.bindVertexArray(vao);
check(
  gl.isVertexArray(vao) && gl.getParameter(gl.VERTEX_ARRAY_BINDING) === vao,
  "vertex array",
);
const sampler = gl.createSampler();
gl.bindSampler(0, sampler);
gl.samplerParameteri(sampler, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
check(
  gl.getSamplerParameter(sampler, gl.TEXTURE_MIN_FILTER) === gl.NEAREST,
  "sampler state",
);
const buffer = gl.createBuffer();
gl.bindBuffer(gl.COPY_READ_BUFFER, buffer);
gl.bufferData(
  gl.COPY_READ_BUFFER,
  new Uint8Array([42, 11, 22, 33, 44]),
  gl.STATIC_DRAW,
  1,
  3,
);
const read = new Uint8Array([7, 7, 7, 7, 7]);
gl.getBufferSubData(gl.COPY_READ_BUFFER, 0, read, 1, 3);
check(read.join(",") === "7,11,22,33,7", "buffer subrange");
const tex = gl.createTexture();
gl.bindTexture(gl.TEXTURE_3D, tex);
gl.texStorage3D(gl.TEXTURE_3D, 1, gl.RGBA8, 1, 1, 1);
gl.texSubImage3D(
  gl.TEXTURE_3D,
  0,
  0,
  0,
  0,
  1,
  1,
  1,
  gl.RGBA,
  gl.UNSIGNED_BYTE,
  new Uint8Array([0, 31, 63, 127, 255]),
  1,
);
const fbo = gl.createFramebuffer();
gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
gl.framebufferTextureLayer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, tex, 0, 0);
check(
  gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE,
  "layered framebuffer",
);
const pixel = new Uint8Array(5);
gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel, 1);
check(pixel.join(",") === "0,31,63,127,255", "3D texture readback");
gl.bindFramebuffer(gl.FRAMEBUFFER, null);
function shader(type, src) {
  const s = gl.createShader(type);
  gl.shaderSource(s, src);
  gl.compileShader(s);
  check(gl.getShaderParameter(s, gl.COMPILE_STATUS), gl.getShaderInfoLog(s));
  return s;
}
const prog = gl.createProgram();
gl.attachShader(
  prog,
  shader(
    gl.VERTEX_SHADER,
    "#version 300 es\nvoid main(){float x=float((gl_VertexID<<1)&2);float y=float(gl_VertexID&2);gl_Position=vec4(x*2.-1.,y*2.-1.,0.,1.);}",
  ),
);
gl.attachShader(
  prog,
  shader(
    gl.FRAGMENT_SHADER,
    "#version 300 es\nprecision highp float; uniform uvec3 tint;out vec4 color;void main(){color=vec4(vec3(tint)/255.,1.);}",
  ),
);
gl.linkProgram(prog);
check(gl.getProgramParameter(prog, gl.LINK_STATUS), gl.getProgramInfoLog(prog));
gl.useProgram(prog);
const query = gl.createQuery();
gl.beginQuery(gl.ANY_SAMPLES_PASSED, query);
check(
  gl.getQuery(gl.ANY_SAMPLES_PASSED, gl.CURRENT_QUERY) === query,
  "query identity",
);
const tint = gl.getUniformLocation(prog, "tint");
gl.uniform3ui(tint, 0, 255, 0);
gl.drawArraysInstanced(gl.TRIANGLES, 0, 3, 1);
gl.endQuery(gl.ANY_SAMPLES_PASSED);
const sync = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
check(gl.isSync(sync), "native fence");
gl.deleteSync(sync);
check(gl.getError() === gl.NO_ERROR, "ES3 driver error");
const stageBox = document.getElementById("stage").getBoundingClientRect();
check(
  stageBox.width === 240 && stageBox.height === 80,
  "flex container bounds",
);
const grid = document.getElementById("tiles"),
  lead = document.getElementById("lead").getBoundingClientRect(),
  end = document.getElementById("end").getBoundingClientRect();
check(getComputedStyle(grid).display === "grid", "computed grid display");
check(
  lead.left === 0 &&
    lead.top === 80 &&
    lead.width === 158 &&
    end.left === 164 &&
    end.width === 76 &&
    end.height === 80,
  "named grid areas and fractional track geometry",
);
const tokenElement = document.createElement("div");
const tokens = tokenElement.classList;
tokenElement.setAttribute("class", "first second first");
tokens.add("third", "second");
tokens.replace("second", "next");
tokens.toggle("first", false);
check(
  tokens === tokenElement.classList &&
    tokens.length === 2 &&
    tokens.item(0) === "next" &&
    tokens.contains("third") &&
    tokenElement.getAttribute("class") === "next third",
  "live class token list",
);
tokenElement.className = "direct";
check(tokens.value === "direct", "class name updates token list");
const styleElement = document.createElement("style");
document.head.appendChild(styleElement);
styleElement.textContent = "#end { width: 55px; }";
const sheet = styleElement.sheet,
  rules = sheet.cssRules;
check(
  rules.length === 1 &&
    rules.item(0) === rules[0] &&
    rules[0].selectorText === "#end",
  "live stylesheet",
);
const ix = sheet.insertRule("#end { height: 44px; }", 1);
check(
  ix === 1 &&
    rules.length === 2 &&
    document.getElementById("end").getBoundingClientRect().height === 44,
  "CSSOM insertion changes native layout",
);
rules[1].style.height = "51px";
check(
  document.getElementById("end").getBoundingClientRect().height === 51,
  "live declaration changes layout",
);
sheet.deleteRule(1);
sheet.disabled = true;
check(
  rules.length === 1 &&
    document.getElementById("end").getBoundingClientRect().width === 76,
  "disable and remove native style rules",
);
document.head.removeChild(styleElement);
const stress = document.createElement("div");
stress.style =
  "display:grid;width:150px;height:20px;grid-template-columns:repeat(auto-fit,minmax(25px,auto))";
document.body.appendChild(stress);
const placed = document.createElement("div");
placed.style = "grid-column:-5/span 8;grid-row:2;height:10px";
stress.appendChild(placed);
check(
  placed.getBoundingClientRect().height === 10 &&
    stress.getBoundingClientRect().width === 150,
  "auto fit and negative implicit tracks",
);
document.body.removeChild(stress);
const bounds = panel.getBoundingClientRect();
check(
  bounds.left === 48 && bounds.width === 192 && bounds.height === 40,
  "stylesheet flex layout " +
    bounds.left +
    " " +
    bounds.width +
    " " +
    bounds.height,
);
check(
  document.querySelector("section > aside") === panel &&
    document.getElementById("stage").querySelectorAll("canvas").length === 1,
  "native CSS selectors",
);
check(
  getComputedStyle(panel).getPropertyValue("background-color") ===
    "rgb(250, 100, 10)" && getComputedStyle(panel).width === "192px",
  "resolved CSS from external stylesheet",
);
panel.style = "width:64px;flex:none;height:40px;background-color:#fa640a";
check(panel.getBoundingClientRect().width === 64, "dynamic layout");
let key = 0,
  click = 0,
  order = "",
  loaded = 0,
  ended = 0,
  played = 0,
  remote = 0,
  formPosted = 0,
  aborted = 0,
  missing = 0,
  frame = 0;
window.addEventListener("pointerdown", () => (order += "a"), true);
canvas.addEventListener("pointerdown", (e) => {
  check(e.clientX === 10 && e.buttons === 1, "pointer coordinates");
  order += "b";
  canvas.setPointerCapture(e.pointerId);
});
document.addEventListener("pointerdown", () => (order += "c"));
canvas.addEventListener("click", () => click++);
window.addEventListener("keydown", (e) => {
  if (e.code === "Space" && e.key === " ") key++;
});
const audio = new Audio("tone.wav");
audio.addEventListener(
  "canplay",
  () => {
    loaded++;
    audio.volume = 0.05;
    check(audio.duration > 0.05 && audio.duration < 0.4, "decoded duration");
    audio.play().then(() => played++);
  },
  { once: true },
);
audio.addEventListener("ended", () => ended++);
fetch(TEST_ORIGIN + "/echo", {
  method: "POST",
  headers: { "X-Client": "Silicanto" },
  body: "native-body",
})
  .then((r) => {
    check(
      r.status === 201 && r.headers.get("x-server") === "native",
      "HTTP status and headers",
    );
    return r.json();
  })
  .then((j) => {
    check(j.text === "native-body" && j.client === "Silicanto", "HTTP body");
    remote++;
  });
const params = new URLSearchParams("?b=x+y&a=%2B&b=%C3%A9");
check(
  params.getAll("b").join("|") === "x y|é" && params.get("a") === "+",
  "form decoding",
);
params.set("b", "two words");
params.append("a", "?");
params.sort();
fetch(TEST_ORIGIN + "/echo", { method: "POST", body: params })
  .then((r) => r.json())
  .then((j) => {
    check(
      j.text === "a=%2B&a=%3F&b=two+words" &&
        j.type === "application/x-www-form-urlencoded;charset=UTF-8",
      "form data transport",
    );
    formPosted++;
  });
const req = new XMLHttpRequest();
req.open("GET", TEST_ORIGIN + "/slow");
req.onabort = () => aborted++;
req.send();
req.abort();
const missingReq = new XMLHttpRequest();
missingReq.open("GET", TEST_ORIGIN + "/absent");
missingReq.onload = () => {
  check(missingReq.status === 404, "XHR status");
  missing++;
};
missingReq.send();
let receivedText = 0,
  receivedBinary = 0,
  socketClosed = 0;
const socket = new WebSocket(TEST_ORIGIN.replace("http:", "ws:"), "echo");
socket.binaryType = "arraybuffer";
socket.onopen = () => {
  check(
    socket.protocol === "echo" && socket.readyState === WebSocket.OPEN,
    "negotiated WebSocket",
  );
  socket.send("test");
};
socket.onmessage = (e) => {
  if (typeof e.data === "string") {
    check(e.data === "test", "text WebSocket");
    receivedText++;
    socket.send(new Uint8Array([4, 8, 16]));
  } else {
    check(new Uint8Array(e.data).join(",") === "4,8,16", "binary WebSocket");
    receivedBinary++;
  }
};
socket.onclose = (e) => {
  check(
    e.wasClean && e.code === 1000 && e.reason === "done",
    "WebSocket close",
  );
  socketClosed++;
};
function animate() {
  frame++;
  gl.uniform3ui(tint, frame % 256, 255, 0);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  if (frame === 1) {
    const u = gl.getUniform(gl.getParameter(gl.CURRENT_PROGRAM), tint);
    check(
      u instanceof Uint32Array && u.join(",") === "1,255,0",
      "unsigned uniform reflection",
    );
  }
  if (frame === 45) {
    check(
      loaded === 1 && played === 1 && ended === 1,
      "native audio lifecycle " + loaded + " " + played + " " + ended,
    );
    check(
      remote === 1 && formPosted === 1 && missing === 1 && aborted === 1,
      "native HTTP lifecycle",
    );
    check(
      receivedText === 1 && receivedBinary === 1 && socketClosed === 1,
      "WebSocket lifecycle " +
        receivedText +
        " " +
        receivedBinary +
        " " +
        socketClosed,
    );
    check(
      key === 1 && click === 1 && order === "abc",
      "input propagation " + key + " " + click + " " + order,
    );
    console.log("native contracts passed");
  }
  requestAnimationFrame(animate);
}
requestAnimationFrame(animate);
