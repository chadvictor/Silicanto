# Native desktop compatibility

These measurements were taken on Apple Silicon. The C++ programs run as arm64 executables. The Java programs run as JVM bytecode and call the same native macOS graphics and media services through JNI. The application, its JavaScript dependencies and the test scripts are translated to Haxe. Frame capture reads the application's own framebuffer.

## Phaser 4.1.0

The input was the original Phaser distribution and the 2,061 entries in the pinned example catalog. Each example ran in its own process. The runner saved dimensions, a uniform-color flag and an RGBA SHA-256 at frames **1, 4 and 12**. The complete matrix below was measured at [59e1ab2](https://github.com/chadvictor/Silicanto/commit/59e1ab25706a60ecccb309e5db1df3d6f0735953). [Pinned gallery](https://github.com/phaserjs/examples/tree/eb87db8355861ae222d0c5cd13aae54c2d7d72ae)

| Outcome | C++ | Java |
| --- | ---: | ---: |
| Produced all three frames | 1,925 | 1,929 |
| Changed between sampled frames | 876 | 887 |
| Uniform color at every sampled frame | 63 | 60 |
| Failed | 136 | 132 |

Of the 1,925 entries observed on both targets, 944 produced exactly the same pixels at all three marks. Matching outputs can include blank scenes. Independent renderers, timed events and game randomness can produce different hashes. These results give no playability judgment for a particular game. Four captures interrupted by storage errors were rerun at the same revision. The original diagnostics accompany the successful retries. [Per-example table](phaser4/matrix.tsv) · [Hashes and failures](phaser4/frames.json.gz) · [Summary](phaser4/summary.json)

A separate run at 4b16e12 revisited the same 151 historically failing entries. C++ produced three frames for 17 and Java for 20. Two JVM cases exceeded an explicitly capped heap, then produced all three frames when repeated with the default heap. The recheck stores both attempts. [151-entry recheck](phaser4-recheck.json.gz)

The original `animation/animation from png sequence.js` was also built as a standalone application and captured at frames 4, 12, 20, 30 and 48. The animation changed over time and its C++ and Java pixels agreed at each mark. [Five-frame hashes](phaser-animation.json) · [Run the gallery](../../../tests/phaser4/README.md)

## WebGL on Metal

ANGLE executes GLSL ES and drawing commands on Metal. A dedicated integration test checks the analytic pixel result of a triangle, context loss and restoration, and WebGL 2 operations against a real ES 3 context. Two independent Khronos measurements exercise the WebGL 1 OGLES group. [Pinned Khronos suite](https://github.com/KhronosGroup/WebGL/tree/39443210f7f81db4773eb104facadfb85d05dfa4/sdk/tests)

| Upstream checks | C++ | Java |
| --- | ---: | ---: |
| Required WebGL 1 method names callable | 136 / 136 | 136 / 136 |
| Required numeric WebGL 1 constants | 296 / 296 | 296 / 296 |
| OGLES shader compilation and linkage cases | 178 / 178 | 178 / 178 |
| OGLES shader rendering comparisons | 775 / 775 | 775 / 775 |

The render runner reads pixels from the Metal-backed framebuffer and applies each upstream reference comparison. Rendering results use 59e1ab2. Shader build and API results use 4b16e12. The API inventory checks callability and enumerant values. [Build and API results](gles-build.json.gz) · [C++ rendering results](gles-render-cpp.json.gz) · [Java rendering results](gles-render-java.json.gz)

The full page runner loads the original upstream scripts and listens for their assertion and completion callbacks. In the initial C++ sweep, 914 of 970 WebGL 1 pages stopped during translation and 56 stopped during execution. For WebGL 2, 2,808 of 2,865 stopped during translation and 57 stopped during execution. No page completed that first sweep. The shared JavaScript harness itself used features the compiler did not yet implement. [WebGL 1 page diagnostics](webgl-native-before-async-1.0.4.json.gz) · [WebGL 2 page diagnostics](webgl-native-before-async-2.0.1.json.gz)

After native async lowering, the compiler emitted Haxe for **933 / 970** WebGL 1 pages and **2,063 / 2,865** WebGL 2 pages at [6def5e8](https://github.com/chadvictor/Silicanto/commit/6def5e8b66bca46cfb97a676043548c00068ad74). This step tests translation only. Full WebGL conformance requires every applicable upstream page to execute and meet its assertions. [WebGL 1 translation census](webgl-frontend-1.0.4.json.gz) · [WebGL 2 translation census](webgl-frontend-2.0.1.json.gz)

## CSS layout and painting

The C++ renderer laid out and painted both sides of 1,714 WPT `rel=match` pairs. The runner selects static, self-contained HTML from seven directories and compares the entire rendered viewport. It excludes pages requiring scripting, external stylesheets, Ahem, SVG or external image assets. The run at 59e1ab2 finished every pair with **630 exact nonuniform matches, 28 exact uniform matches and 1,056 differences**. The earlier layout produced 813 nonuniform matches, 40 uniform matches and 861 differences on the same inputs. The new grid path passed 60 previously differing pairs, while the total number of matches fell. Grid placement, subgrid and table layout have outstanding differences. [WPT revision](https://github.com/web-platform-tests/wpt/tree/92d37954de77c1594899db93bc2e81dcff661460/css) · [Pixel hashes per pair](wpt-css.json.gz)

| WPT directory | Nonuniform match | Uniform match | Different |
| --- | ---: | ---: | ---: |
| CSS2 normal flow | 18 | 0 | 14 |
| CSS2 floats | 20 | 0 | 16 |
| CSS2 tables | 0 | 0 | 6 |
| CSS display | 8 | 0 | 30 |
| Flexbox | 339 | 14 | 149 |
| Grid | 217 | 14 | 782 |
| CSS tables | 28 | 0 | 59 |

## Audio, input and networking

The 45-frame desktop test decodes a WAV through AVFoundation, starts playback and waits for the media element's ended event on both targets. AppKit and AWT queue native mouse and keyboard events. An independent event trace tests DOM dispatch, focus and pointer capture. HTTP tests start a loopback server and check status, headers, body bytes, a form POST, failure, abort and timeout. WebSocket tests exchange text and binary frames and close the connection. Separate native C++ and Java programs fetched and verified a public HTTPS response. Web Audio graphs, streaming Fetch bodies and the full set of browser APIs remain outside this coverage. [Native desktop integration](../../../tests/desktop-targets.mjs) · [JavaScript fixture](../../../tests/fixtures/desktop/verify.js)

## Reproduce on Apple Silicon

Use Node.js 22 or newer, the Xcode Command Line Tools, npm and an Apple Silicon Mac with a Metal device. The scripts fetch the pinned Haxe, Java, shader tests and native payloads as needed. Run the commands from the repository root. Complete corpus runs can require several gigabytes of compiler cache and temporary artifacts. Use a scratch volume for `TMPDIR` and `HXCPP_COMPILE_CACHE` when appropriate.

```sh
npm ci
npm run setup:c
npm run setup:java
npm ci --prefix tests/phaser4
mkdir -p dist
npm run test:async
npm run test:desktop
npm run test:webgl-conformance -- --out dist/gles-build.json
npm run test:webgl-render -- --target cpp --out dist/gles-cpp.json
npm run test:webgl-render -- --target java --out dist/gles-java.json
npm run test:webgl-pages -- --target cpp --version 1.0.4 --out dist/webgl1.json
npm run test:webgl-pages -- --target cpp --version 2.0.1 --out dist/webgl2.json
npm run test:css -- --out dist/wpt-css.json
```

The CSS and WebGL page runners return a failing status when comparisons or assertions fail. The JSON reports retain those outcomes.
