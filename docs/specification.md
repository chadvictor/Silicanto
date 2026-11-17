# Silicanto compiler specification

**Run Three.js as native code.** Revision 0.8, November 16, 2026.

Silicanto takes a web JavaScript entry point and emits a readable, editable Haxe project containing the application and the modules it uses. Each target builds from that same project. Three.js applications were the first use case. The 1.0 goal is to compile applications without any prior knowledge of their libraries. The JavaScript frontend owns language semantics and the module graph; target payloads own the web and operating-system services an application uses. The goal does not establish current compatibility.

## Product contract

1. Accept the original application entry point. Resolve its modules, identify the operations it uses and translate them to Haxe.
2. The emitted Haxe must be sufficient to rebuild for another target after removing the original JavaScript. Changing a formula in the Haxe must change the result in the executable.
3. If the application creates geometry, evaluates lighting or animates a camera, the delivered application must perform that work at runtime. Existing input assets may remain data.
4. Each output language needs a generator. Each platform service used by the program, such as a WebGL canvas, network or audio, needs an implementation on the target. Diagnostics should distinguish an unsupported JavaScript construct from a missing platform implementation.

## 1.0 release gate: unmodified web applications

- Resolve the entire statically discoverable dependency graph from the application entry and installed dependency tree, including dependencies of dependencies. Preserve module identity, order of side effects and observable exports. If an input depends on code that cannot be resolved, identify the edge; do not silently drop it.
- Compile the implementation of each application library from its source. No opt-in adapter, package-name switch, substitute framework implementation, embedded browser, or JavaScript interpreter qualifies. The legacy Three.js path can remain available independently.
- Translate to one editable Haxe project and retarget it without the input JavaScript. Only advertise a target/platform pair for which the declared host services can actually be supplied.
- Use the [upstream Phaser gallery](../tests/phaser4/README.md) as an external consumer. For the pinned catalog, account for every entry on C++ and Java. Each must build, initialize, and demonstrate the behavior of its web reference. A native process that starts, a blank frame, or a source-only compilation is insufficient.
- For visual scenes, compare real output with the browser. For input, audio, timing or nonvisual logic, add a repeatable scenario with observable assertions. A missing reference or an unavailable service remains an open case. Passing this catalog would establish compatibility for the tested revision and targets; other frameworks still need independent evidence.

The [case-by-case measurements](compatibility/phaser4/README.md) are the current baseline. The 1.0 release criterion **has not been met**.

## Current evidence

| Workload | Reference | Verified behavior |
| --- | --- | --- |
| Application logic with modules | A JavaScript program imports functions from the real Three.js r180 MathUtils module, constructs a class and manipulates vertex data | The original JavaScript and the C, C++, Java, JavaScript and Python outputs agree on the computation. Editing the Haxe changes the result. Custom HXML can select another backend. [Java JAR isolation](../tests/java-target.mjs) · [Other targets](../tests/haxe-targets.mjs) |
| General web application | Classic script, ES modules, CommonJS, JSON, local XHR and PNG drawn to a Canvas | The original Chromium image matches C, C++, Java and Neko pixel for pixel. [Fixture and test](../tests/generic-targets.mjs) |
| Unmodified Phaser 4 catalog | The published UMD engine and the original sources and assets | [Native results by example](compatibility/phaser4/README.md); source emission, execution and visual checks are separate. |
| Haxe-to-JavaScript round trip | A projection calculation compiled by Haxe 4.3.7 to both ES5 and ES6 | Both complete scripts translate back to Haxe and produce the reference result in JS and native C. The corpus includes handwritten JavaScript and the recurrence used by the Nácar terrain. [Test](../tests/haxe-js-roundtrip.mjs) |
| Official Three.js samples | The static and animated Fundamentals examples from r180 | Compare the original WebGL frames to the regenerated web program and to the C/Metal and Java/Metal programs. Preserve the original dimensions and options. [Test](../tests/metal.mjs) · [Upstream examples](https://github.com/mrdoob/three.js/tree/r180/manual/examples) |
| Nácar procedural world | Three original JavaScript modules generate the scene and move the camera; Three.js WebGLRenderer supplies the browser reference | The native ARM64 app generates geometry and an HDR environment at startup. At 1280 × 720, compare original WebGL, regenerated WebGL and C/Metal or Java/Metal at 0, 14 and 35 seconds. Metal passes if mean channel error is below 4/255 and more than 92% of pixels have every RGB channel within eight levels of the reference. [Test](../tests/nacar.mjs) |

Compatibility is measured for an **entry point, its dependency graph, the dependency revisions, the host services and an output target**. Support for a mesh type alone says little about an application that also loads assets or uses browser UI. The CLI currently reports the first translation error it detects. The engineering requirements below describe both implemented behavior and goals for later releases.

## What the upstream Haxe compiler can tell us

The reference implementation is Haxe 4.3.7 at commit `e0b355c6be312c1b17382603f018cf52522ec651`. The Haxe compiler type-checks the input, runs filters and dispatches to its JavaScript generator. Each typed expression carries its operation, type and source position. The typed tree distinguishes static, instance and dynamic field access and captured methods. Some of this information disappears in the emitted JavaScript. [Typed tree](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/core/tType.ml#L161-L204) · [Compiler pipeline](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/compiler/compiler.ml#L309-L349) · [Target dispatch](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/compiler/generate.ml#L63-L96)

| Upstream behavior | Consequence for JavaScript to Haxe |
| --- | --- |
| `gen_expr`, `gen_value` and `gen_call` emit operations, values and calls. Indexed access uses square brackets. | Resolve the receiver and the index and preserve evaluation order. The same syntax can address an array, a typed array or an object property. [Expressions and access](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/generators/genjs.ml#L615-L713) |
| `generate_class` emits constructors and prototypes for pre-ES6 targets and class syntax for ES6+. | Recognize structural forms in the JS syntax tree, emit constructors and methods, preserve initialization and diagnose unsupported mutations. [Class generation](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/generators/genjs.ml#L1326-L1627) |
| Iteration can become an index loop. Filters can eliminate dead code. | Preserve the visible loop. Recovering the original syntax or discarded declarations would require additional information. [Loops](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/typing/forLoop.ml) · [Dead code](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/filters/filters.ml#L718-L745) |
| Bound methods can use `$bind`. Enums have several representations. Some casts disappear and others become runtime checks. | Test receiver identity, function identity, representation and failure behavior before advertising support. [Bindings](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/generators/genjs.ml#L666-L685) · [Casts](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/generators/genjs.ml#L903-L910) · [Enums](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/generators/genjs.ml#L1628-L1654) |
| The generator emits wrappers, feature-dependent helpers and an entry call. The standard library declares browser APIs as externs. | Check the wrapper structure and its arguments before opening its scope. The output platform must provide the host operations. [Outer scope](https://github.com/HaxeFoundation/haxe/blob/4.3.7/src/generators/genjs.ml#L1930-L1984) · [WebGL 2 extern](https://github.com/HaxeFoundation/haxe/blob/4.3.7/std/js/html/webgl/WebGL2RenderingContext.hx) |

Two Haxe implementations of `twice(x) = x + x`, one using `Int` and the other `Float`, generated byte-identical JavaScript. Observable behavior is therefore the equivalence criterion. Infer types from operations and their uses in the incoming program. Upstream output provides a test corpus even when several Haxe reconstructions are valid.

## A minimal acceptance program

The camera sits five units from a rotating cube. Space toggles the animation. The keyboard and frame callbacks must capture the same mutable variable.

```js
import * as THREE from 'three';

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(50, 640 / 480, 0.1, 100);
camera.position.z = 5;
const cube = new THREE.Mesh(
  new THREE.BoxGeometry(1, 1, 1),
  new THREE.MeshBasicMaterial({ color: 0x3984ff })
);
scene.add(cube);

const renderer = new THREE.WebGLRenderer({ antialias: false });
renderer.setSize(640, 480);
document.body.appendChild(renderer.domElement);
let playing = true;
window.addEventListener('keydown', (event) => {
  if (event.code === 'Space' && !event.repeat) playing = !playing;
});
renderer.setAnimationLoop(() => {
  if (playing) cube.rotation.y += 0.01;
  renderer.render(scene, camera);
});
```

Save as `src/main.js` in a project with the pinned Three.js dependency. From the Silicanto checkout, `npx --no-install silicanto emit /path/to/src/main.js --out dist/cube-source` emits Haxe. After native setup, `npx --no-install silicanto target dist/cube-source --target cpp --out dist/cube` builds the C++ executable.

## Compatibility contract

The web reference is Three.js **0.180.0 (r180)** with WebGLRenderer and WebGL 2. The macOS process explicitly selects Metal. The initial cube profile and the procedural profile have different coverage. In particular, the latter adds selected physically based materials and lighting. [Pinned package](https://raw.githubusercontent.com/mrdoob/three.js/r180/package.json) · [WebGLRenderer](https://threejs.org/docs/pages/WebGLRenderer)

| Surface | Initial scope | Examples outside that scope |
| --- | --- | --- |
| Modules | JS or supported TS entry, acyclic static ES imports, namespaces and named imports with aliases | Dynamic import, CommonJS and external modules lacking an implementation |
| Language | Bindings, assignment, functions, closures, branches, numeric arithmetic, Boolean operations and comparisons | General implicit coercion, eval, arbitrary prototype mutations and unrestricted dynamic property access |
| Scene | Scene, group and mesh identity, hierarchy, position, Euler rotation and scale | Skeletal animation, instanced rendering and arbitrary matrix mutation |
| Camera and material | Perspective camera and opaque basic cube; procedural profile adds supported indexed geometry, opaque metal/roughness materials, environment reflections, fog and lights | General textures, transparency, user shaders and onBeforeCompile |
| Frames and window | One window, antialiasing option, explicit size, render and animation callbacks; stopping a callback with null is an acceptance goal | Multiple canvases, WebXR, WebGPU and post-processing |
| Browser services | A recognized canvas or document.body mount, keydown events with code and repeat | General selectors, CSS UI, fetch, web storage and addon controls |

Record supported signatures, defaults and option keys for each target. TypeScript annotations can inform type selection. JavaScript must work when operations and call sites provide enough information. An extern declaration describes an interface; the target still needs its implementation.

## Architecture and interop

1. **Read the input.** The general frontend parses JavaScript with the TypeScript compiler API and uses the [dependency resolver](../src/frontend/graph.mjs) to follow imports and literal require calls into package sources. Only the legacy path binds Three.js imports to the supported scene API; local classes keep their identity. Source maps connect bundled locations to the original modules. [Module graph](../src/module-graph.mjs) · [TypeScript compiler API](https://github.com/microsoft/TypeScript/wiki/Using-the-Compiler-API)
2. **Preserve behavior.** Track functions, control flow, captured state and source locations while lowering. A shared typed intermediate representation is a design goal. In the cube program, giving each callback a separate copy of `playing` would break pause.
3. **Emit Haxe.** Emit the application and the required compatibility code into a portable project. Keep supported JavaScript numbers at 64-bit precision on the CPU and narrow data when preparing typed arrays or GPU buffers.
4. **Build the target.** Haxe 4.3.7 generates HashLink/C through `--hl c/main.c`; Clang builds and links the executable. hxcpp builds C++ output. The Java payload uses hxjava 4.2.0 and Haxe’s Java source generator, then compiles with `javac --release 17`. A platform registry selects a payload by target, platform, graphics API and project profile. [Payload contract](payloads.md) [HashLink/C](https://haxe.org/manual/target-hl-c-compilation.html) · [C++](https://haxe.org/manual/target-cpp-getting-started.html) · [Java](https://haxe.org/manual/target-java-getting-started.html)
5. **Draw and present.** The general Canvas host draws to a software surface that C++ can present with AppKit and Java can present with Swing. The legacy Three.js native host uses hx-n for the Metal device, pipeline, textures, command queue, window and input events. The rendering path can present a frame or capture it for comparison. Native bindings and linkage depend on the target; the Java desktop payload uses Swing for presentation and input, and JNI to submit the same scene buffers and shaders to Metal. The graphics JAR contains its JNI library; the app bundle also includes a JVM. [Metal bindings](https://github.com/hx-n/hxn-gpu-metal) · [Window bindings](https://github.com/hx-n/hxn-window) · [Haxe externs](https://haxe.org/manual/lf-externs.html)

## Engineering requirements

These requirements define the intended product. See the evidence table and linked tests for current coverage.

| ID | Verifiable requirement |
| --- | --- |
| FR-01 | Check the entry point, target language, graphics API, installed revision and import graph without executing user code or opening a window. |
| FR-02 | Identify unsupported uses with a stable code, file, line, column, symbol, target and actionable explanation. Collect independent failures and provide both text and JSON diagnostics. |
| FR-03 | Use the same translation checks for check and emit. Return a nonzero status for incompatible inputs and preserve a previous successful output on failure. |
| FR-04 | Deliver Haxe sources, requested target sources, dependencies, shaders, build commands and required versions. A separate checkout with those dependencies must be able to rebuild them. |
| FR-05 | Preserve object identity, execution order, closure capture and composed transforms. Aliases of a mesh must observe the same changes. |
| FR-06 | Apply the requested window size, dispatch input, execute callbacks in order and release window and GPU resources on exit. Identify the active API in logs and explain initialization failures. |
| FR-07 | Declare operating systems, dependencies and supported features for each target and graphics pair. Diagnose unavailable combinations before source emission. |
| NFR-01 | Identical input, options and tool versions should give identical sources and manifests across directories. Store project-relative input paths. |
| NFR-02 | Compare state and pixels against the recorded web reference. A regression in an advertised feature blocks that target's release. |

For example, a future diagnostic for `src/menu.ts:18:12` could identify the unsupported DOM selector, explain that the Metal host offers a window and keyboard events, and suggest keeping the HTML menu in a web-specific module. Current diagnostics use codes such as `E-SUBSET`.

## Acceptance plan

Keep the settings and dimensions of upstream samples. The synthetic cube suite uses a 640 × 480 canvas, pixel ratio 1, sRGB output, opaque black background and no antialiasing. Record the browser, compiler, OS, GPU and backend. Advance frames and input events deterministically.

| Case | Proposed acceptance criteria |
| --- | --- |
| A1 · Distribution | Rebuild the emitted project in a clean environment. Open the distributed package on a second machine with only runtime prerequisites and interact with the cube. Repeat for each supported target pair. |
| A2 · Execution | Advance 20 frames, press Space and advance 10, then resume and advance 10 more. Y rotation must be 0.20, 0.20 and 0.30 radians within 0.000001. A repeated key event during pause must leave the state intact. Repeat with JS and TS input. |
| A3 · Visual equivalence | Test two camera angles and overlapping differently colored cubes under a transformed parent. Per object, require silhouette intersection over union ≥ 0.99. Excluding one edge pixel, ≥ 99% of interior pixels must differ by at most three levels per 8-bit RGB channel. Retain frames and difference maps on failure. |
| A4 · Diagnostics | Translate a locally imported function and an aliased Mesh import. Introduce an unsupported selector, material option, dynamic import and custom shader separately; verify location, diagnostic, exit status and preservation of previous output. |
| A5 · Resource lifetime | Confirm the requested backend in the log. Open, render and close a scene 100 times. Live graphics resources must return to baseline after each cycle. |
| A6 · Editable sources | Repeat emission and compare hashes. Remove the original JS, change the rotation increment in Haxe, rebuild for two targets and observe the new value in A2. |

The original r180 cube ran in Chromium 158.0.8127.18 using WebGL 2 with SwiftShader. The recorded rotations rounded to 0.20, 0.20 and 0.30. The center pixel stayed RGB (57, 132, 255). Measure performance separately from correctness: record median and p95 frame time after warm-up for 1, 100 and 1,000 cubes, including resolution and synchronization settings, before setting a public FPS target.

## Roadmap

| Milestone | Exit criterion |
| --- | --- |
| M0 · Haxe and Metal | Rebuild the two official Fundamentals samples for ARM64 from Haxe and compare the native frames against the browser. |
| M1 · macOS compatibility | Expand the supported language, module, hierarchy and depth behavior; pass A1–A6 and publish the tested API matrix. |
| M2 · OpenGL | Implement a desktop OpenGL host and run the same samples and acceptance suite with backend verification. |
| M3 · Direct3D | Validate Windows x64 rendering with the same depth, clipping, color and face ordering tests. |
| M4 · Java | Implemented for portable JVM logic and macOS ARM64 graphics. Expand graphical support by adding a platform payload and passing the same image comparison. |
| M5 · Models and textures | Add the upstream webgl_geometry_cube sample and a local model viewer. Verify asset packaging, UV orientation, color and interaction against the web reference. |

The original compiler and runtime use the MIT license. Preserve dependency notices in distributions. Generic frontend changes should identify the language or web behavior, include a small independent reproducer and compare observable results. Legacy scene API changes should include a recognized signature, runtime implementation and expected behavior, including unsupported parameters. [Contributor guide](../CONTRIBUTING.md)
