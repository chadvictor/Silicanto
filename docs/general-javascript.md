# The general JavaScript compiler

Silicanto has an experimental source compiler for applications whose libraries are not known in advance. It resolves the application and its dependencies, lowers their JavaScript to Haxe functions and module initializers, and lets a payload compile that project. It does not embed Node, a browser, a JavaScript VM, or a copy of the original scripts in the native application.

```sh
npm ci
npm run setup:c
npm run setup:java
npx --no-install silicanto graph tests/fixtures/general/index.html
npx --no-install silicanto emit tests/fixtures/general/index.html --frontend generic --out dist/source
npx --no-install silicanto target dist/source --target cpp --out dist/desktop
dist/desktop/cpp/Sample --asset-root tests/fixtures/general --window
# For a deterministic capture without a window:
dist/desktop/cpp/Sample --asset-root tests/fixtures/general --frames 4 --capture frame.ppm
npx --no-install silicanto target dist/source --target java --out dist/jvm
java -jar dist/jvm/java/Sample.jar --asset-root tests/fixtures/general --window
```

The compiler also accepts a single JS entry, ES modules, CommonJS, and local HTML pages with multiple scripts. Install the application's dependencies using its lockfile before building. Use `--web-root DIR` when relative JS import URLs at a mounted directory's boundary should resolve as they do on a web server. The CLI never installs arbitrary app dependencies. Look at `manifest.json` for module edges, input hashes, host profile and payload; look at `haxe/JsModule*.hx` and `haxe/JsUnit*.hx` for the application and its libraries. Copying the generated project to a new directory and running `silicanto target` requires no original JavaScript.

| Component | Responsibility |
| --- | --- |
| [HTML input](../src/frontend/document.mjs) | Parse script order, inline and external sources, module roots and simple import maps. |
| [Dependency graph](../src/frontend/graph.mjs) | Resolve static import and literal require edges using browser package resolution, including nested dependencies and package exports. |
| [Haxe emitter](../src/frontend/javascript.mjs) | Lower expressions, classes, closures and control flow. Preserve receiver bindings and evaluate JS operands in order. |
| [Compilation units](../src/frontend/units.mjs) | Split large closed functions and literal tables so the JVM and native compilers can consume bundled libraries. |
| [ECMAScript runtime](../runtime/ecmascript/) | Values, objects and prototypes, properties and descriptors, module initialization, typed arrays and collections. |
| [Web host](../runtime/web/) | A DOM/Canvas subset, bitmap, animation frames, local XHR, blobs and image decoding. |
| [Payload registry](../src/targets.mjs) | Select the backend according to the required host capabilities. Canvas uses the software raster payload; Metal is used by the legacy scene payloads. |
| [Legacy Three.js path](../src/legacy/three/) | Retain previous typed builds, packed scenes and the Metal renderer. `--frontend generic` bypasses this code, including for a package named `three`. |

A library is source code; a browser API is a platform service. New language features belong in the compiler or ECMAScript runtime. New drawing, input and resource APIs belong in the web host. A game, library name or upstream filename does not belong in any of those places.

The same canvas can run offscreen or in a desktop window. `--window` presents its pixels via AppKit on native macOS C++ or Swing on Java. Close the window to stop; add `--frames N` for a finite run. C and Neko currently use the offscreen surface. Supply `--asset-root DIR` to mount local files as the application’s origin; XHR supports GET, text/JSON, blobs and array buffers. PNG decoding works on all four tested targets; JPEG uses ImageIO on C++/macOS and Java. WebGL, network transport, audio playback, keyboard/pointer interaction and full CSS layout are still missing. Canvas supports a subset of paths, images and transforms. Curves, text and browser-accurate antialiasing are incomplete. Dynamic imports, unbounded runtime dependency discovery, eval, async functions/generators, return or break across finally and full ES module cycle semantics are incomplete. Retargeting does not supply the missing services. A successful translation is not evidence that a game runs.

Run `npm run test:generic` after installing the [native tools](../README.md) and `npx playwright install chromium`. The test bundles only the browser reference. The native builds consume the original classic script, ES modules, CommonJS and JSON through the general compiler. A local PNG is loaded through XHR, turned into a blob URL and drawn into the scene. All four targets are compared with Chromium byte for byte.
