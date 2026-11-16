import assert from "node:assert/strict";
import { test } from "node:test";
import { compile } from "../src/compiler.mjs";

const preamble = "import * as T from 'three';\n";
test("imports, camera values and captured animation remain in the emitted program", () => {
  const hx = compile(
    "app.ts",
    "import {PerspectiveCamera as Camera} from 'three';\nconst z:number=2; const cam=new Camera(75,2,0.1,5); cam.position.z=z; function frame(t:number) { cam.position.z=t/1000; requestAnimationFrame(frame); } requestAnimationFrame(frame);",
  );
  assert.match(hx, /new PerspectiveCamera\(75.0, 2.0, 0.1, 5.0\)/);
  assert.match(hx, /v_cam.position.z = \(v_t \/ 1000.0\)/);
  assert.match(hx, /Host.requestFrame\(v_frame\)/);
});
test("reports unsupported constructors, options, DOM and imports at the source", () => {
  for (const line of [
    "new T.ShaderMaterial();",
    "new T.WebGLRenderer({alpha:true});",
    "document.querySelector('#menu');",
    "import('other');",
  ])
    assert.throws(
      () => compile("main.js", preamble + line),
      /main.js:2:\d+ E-SUBSET/,
    );
});
test("recognizes the actual canvas id and locates errors inside the original HTML", () => {
  const wrap = (selector) =>
    '<canvas id="view"></canvas>\n<script type="module">\nconst c=document.querySelector("' +
    selector +
    '");\n</script>';
  assert.match(compile("input.html", wrap("#view")), /var v_c:Bool/);
  assert.throws(() => compile("input.html", wrap("#c")), /input.html:3:/);
});
test("enforces the single mesh profile and rejects implicit coercion", () => {
  assert.throws(
    () =>
      compile(
        "mesh.js",
        preamble +
          "const s=new T.Scene(); const g=new T.BoxGeometry(1,1,1); const m=new T.MeshBasicMaterial(); const a=new T.Mesh(g,m); s.add(a); s.add(a);",
      ),
    /one opaque mesh/,
  );
  assert.throws(() => compile("bad.js", "const s='1'+2;"), /expected Float/);
});
test("keyboard and animation callbacks capture the same variable", () => {
  const hx = compile(
    "app.js",
    preamble +
      "const r=new T.WebGLRenderer(); let play=true; window.addEventListener('keydown',e=>{if(e.code==='Space' && !e.repeat) play=!play;}); r.setAnimationLoop(()=>{if(play) play=false;});",
  );
  assert.equal((hx.match(/var v_play:/g) ?? []).length, 1);
  assert.match(hx, /Host.onKey/);
  assert.match(hx, /Host.loop/);
});

test("static ObjectLoader scenes share the camera compiler and keep their geometry immutable", () => {
  const application = `import * as T from 'three';
import model from './rock.json' with { type:'json' };
const scene=new T.ObjectLoader().parse(model);
const c=new T.PerspectiveCamera(50,1,0.1,100);
c.position.set(Math.sin(1),2,3);
c.lookAt(0,0,0);
const r=new T.WebGLRenderer();
r.render(scene,c);`;
  const hx = compile("world.js", application, (p) => {
    assert.equal(p, "./rock.json");
    return "resource1";
  });
  assert.match(hx, /Scene\.fromAsset\("resource1"\)/);
  assert.match(hx, /Math.sin\(1.0\)/);
  assert.throws(
    () =>
      compile(
        "world.js",
        application + "\nscene.add(scene);",
        () => "resource1",
      ),
    /unsupported call/,
  );
});
