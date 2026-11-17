function check(v, message) {
  if (!v) throw new Error(message);
}
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
      remote === 1 && missing === 1 && aborted === 1,
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
