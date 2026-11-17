<h1 align="center">Silicanto</h1>
<p align="center"><strong>Run Three.js as native code.</strong></p>
<p align="center">Compile JavaScript to editable Haxe. Build a native executable or a Java desktop app from the same project.</p>

<p align="center">
  <a href="https://github.com/chadvictor/Silicanto/actions/workflows/ci.yml"><img alt="Compiler checks on main" src="https://github.com/chadvictor/Silicanto/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  &nbsp; <a href="https://github.com/chadvictor/Silicanto/releases">Releases</a>
  &nbsp; · &nbsp; <a href="#build-on-apple-silicon">Quickstart</a>
  &nbsp; · &nbsp; <a href="docs/compatibility/native-desktop/README.md">Compatibility</a>
  &nbsp; · &nbsp; <a href="docs/roadmap-1.0.md">Road to 1.0</a>
</p>

<p align="center">
  <a href="docs/nacar-flight.mp4">
    <picture>
      <source media="(prefers-reduced-motion: no-preference)" srcset="docs/nacar-flight.webp">
      <img width="100%" src="docs/nacar-metal.png" alt="Nácar on Metal. A molten silicon river passes between crystal spires beneath a ringed planet. Open the four-second native flythrough.">
    </picture>
  </a>
</p>

<p align="center"><strong>Nácar · Silicon Sea</strong><br>
Three JavaScript modules generate the terrain, crystal geometry and HDR reflections in this native Metal scene.<br>
<a href="docs/nacar-flight.mp4">Watch the native flythrough</a> · <a href="examples/nacar/world.mjs">Explore the scene source</a></p>

## Try the native demo

On an Apple Silicon Mac, download a ZIP, unzip it and open <code>Nacar.app</code>. Press **Space** to pause or resume the camera flight.

| Download | Inside |
| --- | --- |
| [Nácar for macOS arm64 · C/Metal](https://github.com/chadvictor/Silicanto/releases/download/v0.1.0/Nacar-macOS-arm64.zip) | Native executable and Metal renderer. [Release and checksums](https://github.com/chadvictor/Silicanto/releases/tag/v0.1.0) |
| [Nácar for macOS arm64 · Java/Metal](https://github.com/chadvictor/Silicanto/releases/download/v0.2.0/Nacar-java-macOS-arm64.zip) | Desktop app with its own JVM. A standalone JAR and frame comparison are also available. [Release and checksums](https://github.com/chadvictor/Silicanto/releases/tag/v0.2.0) |

## What can I compile?

**Three.js scenes.** The scene compiler handles a supported subset of Three.js r180, including perspective cameras, indexed geometry, opaque metallic-roughness materials, lights, fog and environment reflections. Nácar uses this path. Run `silicanto check` on your entry point to get a source diagnostic. [Scene specification](docs/specification.md)

**General JavaScript applications.** On `main`, `--frontend generic` follows the application's statically discoverable imports and installed npm dependencies, then translates their source to Haxe. Native host implementations provide the DOM, Canvas, WebGL, audio, input and network APIs. This experimental path compiles the original Phaser engine along with the application. Each target needs implementations of the APIs that application uses. [JavaScript compiler guide](docs/general-javascript.md) · [Known gaps](docs/roadmap-1.0.md)

## Build on Apple Silicon

Install Node.js 22+, npm, Python 3 and the Xcode Command Line Tools. From a fresh checkout:

```sh
git clone https://github.com/chadvictor/Silicanto.git
cd Silicanto
npm ci
npm run setup:c

npx --no-install silicanto build examples/nacar/main.js \
  --target c --name Nacar --out dist/nacar
open dist/nacar/Nacar.app
```

The output contains an app bundle, generated C in `dist/nacar/c/` and editable Haxe in `dist/nacar/haxe/`. Use a fresh destination for each build.

<details>
<summary><strong>Build the same scene for Java</strong></summary>

Install a full arm64 JDK 17+ on the Mac, then run these commands from the configured checkout.

```sh
npm run setup:java
npx --no-install silicanto build examples/nacar/main.js \
  --target java --name Nacar --out dist/nacar-java
open dist/nacar-java/Nacar.app
```

The JVM runs the generated application logic. Swing hosts the window and JNI submits geometry and materials to Metal. The build includes Java sources and `dist/nacar-java/java/Nacar.jar`. Pass `--time-ms 14000 --capture nacar.ppm` to the JAR to capture a fixed camera position.

</details>

## Emit Haxe once, choose the target later

This example starts with an HTML page, ES modules, CommonJS and a PNG. The first command writes the translated sources and dependency manifest. The second compiles that project for C++. At runtime the app reads its image asset and opens a native window.

```sh
npx --no-install silicanto emit tests/fixtures/general/index.html \
  --frontend generic --out dist/source
npx --no-install silicanto target dist/source --target cpp --out dist/desktop
dist/desktop/cpp/Sample --asset-root tests/fixtures/general --window
```

After Java setup, run `npx --no-install silicanto target dist/source --target java --out dist/jvm` to build a JAR from the same Haxe. A desktop integration test moves the source tree offline before running the generated apps with only a WAV in their asset directory. [Integration test](tests/desktop-targets.mjs)

| Output | Available uses |
| --- | --- |
| **Haxe** | Inspect or edit the translated project and hand it to another Haxe backend. |
| **C / C++** | Compile with HashLink/C and Clang or with hxcpp. Both have a software Canvas. The Three.js scene path supports Metal on Apple Silicon. The generic desktop WebGL host is available on C++. |
| **Java** | Generate Java sources and a runnable JAR. Use portable Java 17 logic, Java 2D, or the Metal-backed desktop host on Apple Silicon. |
| **Neko** | Run application logic and software Canvas programs as Neko VM bytecode. |
| **JavaScript / Python** | Use the JavaScript scene or logic payload, or generate a Python program for supported application logic. |

Run `npx --no-install silicanto targets` for the registered target, platform and graphics combinations. Add a payload with `--payload FILE.mjs` or select another Haxe generator with `--backend FILE.hxml`. [Target extension guide](docs/payloads.md)

## Native desktop support on Apple Silicon

The C++ and Java desktop hosts draw through ANGLE on Metal, play audio through AVFoundation, and receive mouse and keyboard events through AppKit or AWT. URLSession handles HTTP(S) and WebSocket traffic. The CSS renderer uses litehtml and Taffy for layout.

| Original workload | Observed result |
| --- | --- |
| **2,061 Phaser 4.1.0 examples** | C++ captured frames 1, 4 and 12 for **1,925** entries. Java captured them for **1,929**. Of the 1,925 entries observed on both, **944** matched pixel-for-pixel at all three marks. |
| **WebGL 1 shaders** | Both targets passed **178/178** OGLES shader build cases and **775/775** reference rendering comparisons. |
| **WebGL context behavior** | Both targets passed **6/21** WebGL 1 context pages and **8/9** WebGL 2 context pages. Full conformance remains open. |
| **CSS layout and paint** | C++ completed **1,714** WPT pairs. **630** matched with visible detail, **28** matched uniformly and **1,056** differed. |
| **Full WebGL page lists** | The compiler emitted Haxe for **964/970** WebGL 1 entries and **2,856/2,865** WebGL 2 entries. This count measures translation only. |

The report records the compiler and upstream revision for each measurement. It includes individual failures, frame hashes and reproduction commands. Gallery captures measure selected moments. Playability still needs input and longer-running checks for individual games. [Read the native report](docs/compatibility/native-desktop/README.md) · [Browse the gallery matrix](docs/compatibility/native-desktop/phaser4/matrix.tsv) · [Run the gallery](tests/phaser4/README.md)

## Contribute

Each open work item has a reproduction and an acceptance criterion. Start with a failing original input, fix the language or platform operation it exercises, then retest the original application. [1.0 backlog and GitHub issues](docs/roadmap-1.0.md) · [Contributor guide](CONTRIBUTING.md) · [Report a compatibility issue](https://github.com/chadvictor/Silicanto/issues/new?template=compatibility.yml)

Silicanto is open source under the MIT License. [License](LICENSE) · [Three.js notice](licenses/three.txt)
