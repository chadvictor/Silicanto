# Contributing to Silicanto

A useful starting point is a small JavaScript program with an observable result: an imported value changes, a bitmap is decoded, or a sprite advances. Keep the JavaScript entry point as the reference and compare the generated program against it.

If an unmodified library fails, find its row in the [compatibility matrix](docs/compatibility/phaser4/README.md), reproduce it with the [suite filter](tests/phaser4/README.md), then reduce the failure to a language or web API test. Fix it in the compiler, standard runtime or platform payload and rerun the original example. Do not change an upstream example or select a native implementation based on its library name.

## Set up a development checkout

Fork [Silicanto](https://github.com/chadvictor/Silicanto) and clone your fork. Install Node.js 22 or newer and run the following in the repository root:

```sh
npm ci
npm test
npx --no-install silicanto emit tests/fixtures/modules/main.js --out dist/first-translation
```

Open `dist/first-translation/haxe/Sample.hx` to inspect the result. The frontend runs under Node.js and the unit tests do not need a graphics device.

For native development, use an Apple Silicon Mac with Xcode Command Line Tools and Python 3. Run `npm run setup:c` in the checkout. For visual comparisons, also run `npx --no-install playwright install chromium`. Run setup again if you move the checkout: Haxe library registrations contain absolute local paths. The source checkout, toolchain and generated output may live on a path containing spaces.

## Find the code

| Area | Files | Responsibility |
| --- | --- | --- |
| Entry point | [CLI](src/cli.mjs) and [module graph](src/module-graph.mjs) | Parse commands, resolve static imports, map errors to source and write a portable Haxe project |
| Language frontend | [Source graph](src/frontend/graph.mjs), [JS lowering](src/frontend/javascript.mjs), [legacy Three.js](src/legacy/three/) | Lower JavaScript syntax and preserve evaluation order, values and callback state |
| General runtime | [ECMAScript](runtime/ecmascript/), [web host](runtime/web/) and [desktop presentation](payloads/canvas/) | Implement language and web behavior independent of package names. |
| Legacy graphics runtime | [Scene graph](runtime/legacy/three/SceneGraph.hx), [geometry](runtime/legacy/three/GeometryData.hx), [scene upload](runtime/legacy/three/SceneUpload.hx) and [Metal surface](runtime/legacy/three/MetalSurface.hx) | Implement the supported Three.js operations and send geometry and materials to Metal |
| Legacy scene bindings | [Procedural API](runtime/legacy/three/ProcApi.hx), [browser host](runtime/legacy/three/BrowserHost.hx) and [native host](runtime/legacy/three/Host.hx) | Bind the generated Haxe to the web renderer or the native window and event loop |
| Target extension API | [Registry](src/targets.mjs), [contract](docs/payloads.md) and [Neko example](examples/payloads/neko.mjs) | Register a generator and platform payload without changing JS translation |
| Java desktop | [Java payload](payloads/java/build.sh), [JVM display](payloads/java/src/org/silicanto/desktop/MetalDisplay.java) and [JNI renderer](payloads/java/native/MetalDisplay.mm) | Generate real Java sources, compile a runnable JAR and bundle the JVM on macOS |
| Target builds | [Target driver](scripts/haxe-target.sh) and [HashLink/C linker](scripts/link-hlc.sh) | Generate the target sources, link the binary and package runtime libraries |
| Acceptance examples | [Nácar](examples/nacar/main.js) and [pinned upstream samples](scripts/samples.mjs) | Exercise the application entry point end to end; downloaded upstream samples are checksum-verified |

The older Static Hermes experiment is available through `scripts/experimental-hermes.mjs` and the scripts containing `aot`. Product builds and their acceptance tests use JavaScript → Haxe → target.

## Run the checks relevant to your change

| Command | What it checks | Environment |
| --- | --- | --- |
| `npm test` | Translation, diagnostics and simple scene semantics | Node.js |
| `npm run test:generic` | Mixed modules, local assets and analytic pixel output on C, C++, Java and Neko | Native setup, JDK |
| `npm run test:source-libraries` | Computations in original library sources on C++, Java and Neko | Native setup, JDK, pinned test dependencies |
| [Full upstream suite](tests/phaser4/README.md) | Original engine and native RGBA timelines for 2,061 entries | Native setup, JDK, pinned sources and assets |
| `npm run test:roundtrip` | ES5 and ES6 inputs plus handwritten JS through Haxe to JS and C | Native setup |
| `npm run test:haxe` | Source removal, code edits and custom HXML backends across C, C++, JS and Python | Native setup |
| `npm run test:haxe-graphics` | Official Three.js sample frames against WebGL and the native C/Metal backend | Native setup, Metal, Chromium and network for initial sample download |
| `npm run test:java` | Edit standalone Haxe and run the resulting logic JAR away from its inputs | Haxe 4.3.7, JDK 17+ and `npm run setup:java` |
| `npm run test:java-graphics` | Verify both upstream Fundamentals samples via the bundled Java app against WebGL | Apple Silicon, ARM64 JDK, Java and native setup, Metal, Chromium |
| `npm run test:nacar-java` | Compare the original Nácar to the runnable Java/Metal JAR at three camera times | Same as above |
| `npm run test:nacar` | Full procedural world, original WebGL, regenerated WebGL and packaged Metal app | Native setup, Metal and Chromium |

For a single official scene, `npm run samples` fetches the pinned r180 sources into `samples/r180/`. To inspect the full-world comparison, find the `comparison/` folder under the native build in `dist/nacar-test-*/native/`. It contains captured frames and a JSON report with pixel differences. Use a fresh output directory when rerunning a build.

## Propose a change

The 1.0 backlog links current failures to GitHub issues with reproduction commands and acceptance criteria. [Choose an open work item](docs/roadmap-1.0.md)

Open an [issue](https://github.com/chadvictor/Silicanto/issues) with the smallest input that demonstrates the behavior. Include the dependency revisions, target, operating system and architecture, exact command, expected result and actual output. For a visual mismatch, include the camera time and the original and native frames if available.

In a pull request, describe the user-visible change and the checks you ran. For a language feature, exercise its normal JavaScript entry point. For a graphics feature, cover the frontend signature, target implementation and a reference scene. For a target change, verify that it works from an emitted Haxe project after the original JavaScript is removed. Keep generated builds, downloaded dependencies and toolchains out of commits. Changes to supported APIs or targets should update the coverage in the [README](README.md) and [specification](docs/specification.md).
