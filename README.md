# Silicanto

**Run Three.js as native code.**

Silicanto is an open-source compiler for turning supported Three.js applications into native Mac apps and Java desktop applications. Give it a JavaScript entry point and it translates the application and its local modules into editable Haxe. On Apple Silicon, choose C, C++ or Java and render the scene with Metal. The resulting app runs without a browser.

**General JavaScript frontend (experimental).** Compile an application's JS and transitive npm dependencies to Haxe with `--frontend generic`. The new path uses standard JavaScript and web APIs without library adapters. [Build and retarget a Canvas app](docs/general-javascript.md) · [Native desktop measurements for WebGL, CSS and 2,061 Phaser examples](docs/compatibility/native-desktop/README.md) · [Reproduce the multi-frame gallery](tests/phaser4/README.md).

### Native desktop support on Apple Silicon

The generic frontend compiles the application's JavaScript and its libraries into editable Haxe. The C++ executable and Java desktop build draw through ANGLE on Metal, play audio through AVFoundation and receive mouse and keyboard input from AppKit or AWT. HTTP, HTTPS and WebSocket traffic uses URLSession. The CSS renderer supports block, flex and grid layout. Local script resources can be compiled ahead of time, including scripts loaded by other scripts.

| Native test | Measured result |
| --- | --- |
| Phaser 4.1.0 gallery | Of 2,061 original examples, 1,925 produced frames 1, 4 and 12 on C++ and 1,929 did so on Java. Both targets produced identical pixels at all three marks for 944 examples. |
| WebGL 1 OGLES | All 178 shader build cases and 775 reference rendering comparisons passed on both targets. |
| CSS reference pairs | The C++ renderer completed 1,714 pairs. Of these, 630 matched with visible detail, 28 matched uniformly and 1,056 differed. |

WebGL 2 has a native ES 3 context. Full WebGL conformance and complete CSS layout remain open. The gallery records pixels at specific frames. Playability requires input and longer scenarios for each game. [Per-example outcomes, hashes and reproduction commands](docs/compatibility/native-desktop/README.md)

![A frame from the native Metal build of Nácar: a river of molten silicon runs between crystal spires beneath a ringed planet.](docs/nacar-metal.png)

*Nácar · Silicon Sea* starts as three JavaScript modules. The native executable generates the terrain, crystals and HDR reflection texture when it starts. Press **Space** to pause or resume the camera flight. [Download the C/Metal demo for macOS ARM64](https://github.com/chadvictor/Silicanto/releases/tag/v0.1.0) · [Explore the scene source](examples/nacar/world.mjs) · [See how the frames are compared](tests/nacar.mjs)

## Build your first native Three.js app

Use an Apple Silicon Mac with Node.js 22 or newer, npm, Python 3 and the Xcode Command Line Tools. Start from a checkout:

```sh
git clone https://github.com/chadvictor/Silicanto.git
cd Silicanto
npm ci
npm run setup:c
npx --no-install silicanto build examples/nacar/main.js --target c --name Nacar --out dist/nacar
open dist/nacar/Nacar.app
```

The setup downloads pinned versions of Haxe, HashLink, hxcpp and the Metal and window bindings into the checkout. The build produces the editable logic in `dist/nacar/haxe/Sample.hx`, generated C in `dist/nacar/c/`, and a self-contained, locally signed macOS app in `dist/nacar/Nacar.app`. The demo's build script runs the same pipeline. [Build script](examples/nacar/build-mac.sh)

## Build Nácar as a Java desktop app

[Download the prebuilt Java app, JAR and frame comparison](https://github.com/chadvictor/Silicanto/releases/tag/v0.2.0). The app includes its own JVM; unzip it and open `Nacar.app`.

On Apple Silicon, install a full **ARM64 JDK 17 or newer** and the Xcode Command Line Tools. From the checkout with npm dependencies installed:

```sh
npm run setup:mac    # Skip if Haxe 4.3.7 is already installed.
npm run setup:java
npx --no-install silicanto build examples/nacar/main.js --target java --name Nacar --out dist/nacar-java
open dist/nacar-java/Nacar.app
```

The app bundles its JVM. You also get editable Java sources in `dist/nacar-java/java/src/` and a standalone JAR you can run with `java -jar dist/nacar-java/java/Nacar.jar` on a Metal-capable Apple Silicon Mac with an ARM64 Java 17+ runtime. The JVM runs the terrain, materials and camera code generated from the original modules. Swing handles the window and keyboard; a small JNI library submits buffers to the same Metal shaders as the C and C++ builds. For a reproducible frame without opening a window, append `--time-ms 14000 --capture nacar.ppm` to the JAR command.

A program without graphics produces a portable Java 17 JAR without Swing bindings or native libraries. The Java graphics payload currently supports the cube and procedural scene profiles on macOS ARM64. Windows and Linux graphics, raw WebGL and packed ObjectLoader scenes need additional implementations.

## Translate JavaScript to Haxe, then choose a target

To inspect the translation, only Node.js and the npm dependencies are required. The first two commands below check the input and write a Haxe project. After native setup, the last two commands compile that same project to different targets. Each output path must be new.

```sh
npx --no-install silicanto check examples/nacar/main.js
npx --no-install silicanto emit examples/nacar/main.js --out dist/nacar-source
npx --no-install silicanto target dist/nacar-source --target cpp --out dist/nacar-cpp
npx --no-install silicanto target dist/nacar-source --target js --out dist/nacar-web
```

Run `./dist/nacar-cpp/cpp/Sample` to open the C++ build. For the web build, run `python3 -m http.server 8000 --directory dist/nacar-web/js` and open [localhost:8000](http://localhost:8000). You can edit the emitted Haxe and repeat `target` with another output directory; it only needs the generated project.

| CLI target | What you get | Tested use |
| --- | --- | --- |
| `haxe` | Editable Haxe sources and an input manifest | Inspect, change or hand off a translated application |
| `c` | HashLink/C sources compiled by Clang; macOS app bundle for graphics | Native Metal scenes on Apple Silicon, or command-line logic |
| `cpp` | C++ sources and an executable built with hxcpp | Native Metal scenes on Apple Silicon, or command-line logic |
| `js` | JavaScript and, for graphics, an HTML entry point | Browser rendering with Three.js r180 and WebGL 2 |
| `java` | Generated Java, a runnable JAR and, for graphics, a macOS app with a bundled JVM | Portable Java SE 17 logic; a Swing window with Metal rendering on Apple Silicon |
| `python` | A Python program | Application logic without a graphics host |

Run `npx --no-install silicanto targets` to list available payloads. Select a graphics route explicitly with, for example, `--target java --platform macos-arm64 --graphics metal`. Register new combinations with `--payload FILE.mjs` using the [target extension guide](docs/payloads.md). For another Haxe backend, pass `--target NAME --backend FILE.hxml` to `build` or `target`. The HXML file specifies the generator and its output. A graphical application also needs an implementation of its window, input and rendering APIs on that platform. [Haxe compiler targets](https://haxe.org/documentation/introduction/compiler-targets.html)

## Will my Three.js project compile?

Start with `silicanto check` on the JavaScript entry point. A supported subset of JavaScript, TypeScript and static ES modules is covered. The reference graphics version is **Three.js r180**. The runtime handles perspective cameras, groups and transforms, opaque basic and metallic-roughness materials, indexed buffer geometry, selected procedural primitives, directional and hemisphere lighting, exponential fog and cube-UV environment reflections.

The frontend reports the first unsupported construct it detects. Arbitrary WebGL calls, general browser DOM code, custom shaders and transparent materials are outside the current graphics coverage. For a useful compatibility report, share a small reproducer, the Three.js revision and the diagnostic. [Report a compatibility issue](https://github.com/chadvictor/Silicanto/issues/new?template=compatibility.yml)

## How rendering is verified

The test suite compares native output against the original JavaScript. It compiles official Three.js Fundamentals examples and captures the same frames in WebGL and Metal. For Nácar it compares the C or Java graphics output at three camera positions at 1280 × 720, at 0, 14 and 35 seconds. A separate test removes the original JavaScript, rebuilds from Haxe for multiple languages and verifies that editing the Haxe changes the result. The [Java isolation test](tests/java-target.mjs) runs an edited program from its JAR after removing both source trees. [Native and WebGL tests](tests/nacar.mjs) · [Cross-target tests](tests/haxe-targets.mjs)

## Contribute and license

To add a Three.js API, improve JavaScript translation or work on a new backend, start with the [contributor guide](CONTRIBUTING.md). It covers setup, source layout, test commands and what to include in a pull request. The [compiler specification](docs/specification.md) describes the compatibility contract and the roadmap.

Silicanto is distributed under the [MIT License](LICENSE). The geometry and shader code that follows Three.js conventions also carries the [Three.js MIT notice](licenses/three.txt).
