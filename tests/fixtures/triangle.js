const canvas = document.createElement("canvas");
canvas.width = 80;
canvas.height = 40;
const gl = canvas.getContext("webgl2");
const vertices = [];
for (let i = 0; i < 3; i++) {
  const angle = Math.PI * (0.5 + (i * 2) / 3);
  vertices.push(Math.cos(angle), Math.sin(angle));
}
function shader(type, code) {
  const s = gl.createShader(type);
  gl.shaderSource(s, code);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS))
    throw Error(gl.getShaderInfoLog(s));
  return s;
}
const p = gl.createProgram();
gl.attachShader(
  p,
  shader(
    gl.VERTEX_SHADER,
    "#version 300 es\nlayout(location=0) in vec2 v; void main(){gl_Position=vec4(v,0.,1.);}",
  ),
);
gl.attachShader(
  p,
  shader(
    gl.FRAGMENT_SHADER,
    "#version 300 es\nprecision highp float; out vec4 pixel; void main(){pixel=vec4(0.,1.,0.,1.);}",
  ),
);
gl.linkProgram(p);
if (!gl.getProgramParameter(p, gl.LINK_STATUS))
  throw Error(gl.getProgramInfoLog(p));
gl.useProgram(p);
gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STATIC_DRAW);
gl.enableVertexAttribArray(0);
gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
gl.clearColor(0, 0, 0, 1);
gl.clear(gl.COLOR_BUFFER_BIT);
gl.drawArrays(gl.TRIANGLES, 0, 3);
