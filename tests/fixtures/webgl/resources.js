// Verify resource and query results while an offscreen framebuffer is bound.
const probe = document.createElement("canvas");
const gpu = probe.getContext("webgl", { antialias: false });
const tex = gpu.createTexture();
gpu.bindTexture(gpu.TEXTURE_2D, tex);
gpu.texParameteri(gpu.TEXTURE_2D, gpu.TEXTURE_MIN_FILTER, gpu.NEAREST);
const backing = new Uint8Array([17, 33, 50, 255, 0, 255, 0, 255]);
gpu.texImage2D(
  gpu.TEXTURE_2D,
  0,
  gpu.RGBA,
  1,
  1,
  0,
  gpu.RGBA,
  gpu.UNSIGNED_BYTE,
  backing.subarray(4),
);
const frameBuffer = gpu.createFramebuffer();
gpu.bindFramebuffer(gpu.FRAMEBUFFER, frameBuffer);
gpu.framebufferTexture2D(
  gpu.FRAMEBUFFER,
  gpu.COLOR_ATTACHMENT0,
  gpu.TEXTURE_2D,
  tex,
  0,
);
if (
  gpu.checkFramebufferStatus(gpu.FRAMEBUFFER) !== gpu.FRAMEBUFFER_COMPLETE ||
  gpu.getParameter(gpu.FRAMEBUFFER_BINDING) !== frameBuffer ||
  gpu.getFramebufferAttachmentParameter(
    gpu.FRAMEBUFFER,
    gpu.COLOR_ATTACHMENT0,
    gpu.FRAMEBUFFER_ATTACHMENT_OBJECT_NAME,
  ) !== tex
)
  throw new Error("framebuffer attachment identity");
const output = new Uint8Array([9, 9, 9, 9, 0, 0, 0, 0]);
gpu.readPixels(0, 0, 1, 1, gpu.RGBA, gpu.UNSIGNED_BYTE, output.subarray(4));
if (
  output.join(",") !== "9,9,9,9,0,255,0,255" ||
  gpu.getError() !== gpu.NO_ERROR
)
  throw new Error("typed texture upload or readback offset");
gpu.deleteFramebuffer(frameBuffer);
gpu.deleteTexture(tex);
const tint = gl.getUniform(program, gl.getUniformLocation(program, "tint"));
if (
  !(tint instanceof Float32Array) ||
  tint.join(",") !== "1,0,0,1" ||
  gl.getAttachedShaders(program).length !== 2 ||
  gl.getVertexAttrib(p, gl.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING) !== buffer ||
  gl.getVertexAttribOffset(p, gl.VERTEX_ATTRIB_ARRAY_POINTER) !== 0
)
  throw new Error("program or attribute query");

const xml = new DOMParser().parseFromString(
  '<?xml version="1.0"?><font><glyph id="42">A&amp;B</glyph><glyph id="7"/></font>',
  "application/xml",
);
const glyphs = xml.getElementsByTagName("glyph");
if (
  glyphs.length !== 2 ||
  glyphs[0].parentNode !== xml.documentElement ||
  glyphs[0].ownerDocument !== xml ||
  glyphs[0].getAttribute("id") !== "42" ||
  glyphs[1].hasAttribute("missing") ||
  glyphs[0].textContent !== "A&B" ||
  xml.firstChild !== xml.documentElement ||
  !new DOMParser()
    .parseFromString("<a></b>", "text/xml")
    .getElementsByTagName("parsererror").length
)
  throw new Error("XML document tree");
if (
  (1.005).toFixed(2) !== "1.00" ||
  (2.55).toFixed(1) !== "2.5" ||
  (2.5).toFixed() !== "3" ||
  (-0.005).toFixed(2) !== "-0.01" ||
  (1.25).toFixed(20) !== "1.25000000000000000000"
)
  throw new Error("IEEE-754 decimal rounding");
