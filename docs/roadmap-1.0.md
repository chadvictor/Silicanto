# What remains for Silicanto 1.0

**Release gate: open.** A contributor should be able to hand Silicanto an unmodified application, compile its JavaScript dependencies into editable Haxe and rebuild for each supported target with the original sources offline. For the 1.0 gallery gate, each original Phaser example must demonstrate its intended behavior on C++ and Java. The published desktop baseline covers macOS arm64. [Compiler specification](specification.md) · [Native evidence and upstream revisions](compatibility/native-desktop/README.md)

## Where to start

1. **Implement synchronous generators and verify dependency initialization.** All 970 WebGL 1 pages reach Haxe emission. Three WebGL 2 pages still stop at `function*`. Start with the range generator in `conformance2/textures/misc/immutable-tex-render-feedback.html` and verify lazy execution, repeated iteration and early exit on both native targets. A separate dEQP program built for C++ and stopped on an unresolved `modules` global. Trace the order in which that executable loads and registers scripts. [Compiler issue #5](https://github.com/chadvictor/Silicanto/issues/5) · [Native dEQP record](compatibility/native-desktop/webgl-native-arrays.json)
2. **Fix rendering against independent expectations.** The Khronos context pages expose concrete mismatches in framebuffer preservation and object ownership. WPT supplies a reference document for each CSS comparison. Each change should include a small test that distinguishes the old result from the required one. [WebGL 1 issue #6](https://github.com/chadvictor/Silicanto/issues/6) · [WebGL 2 issue #7](https://github.com/chadvictor/Silicanto/issues/7) · [CSS issue #8](https://github.com/chadvictor/Silicanto/issues/8)
3. **Recheck the applications that use the affected APIs.** Repeat a failing original gallery entry first. Then run the pinned catalog on both targets and publish a matrix from the same compiler revision. The 151-entry follow-up was a targeted recheck. The totals below come from the last complete catalog run. [Gallery issue #9](https://github.com/chadvictor/Silicanto/issues/9) · [Complete matrix](compatibility/native-desktop/phaser4/matrix.tsv)

## Acceptance by area

| Area | Published baseline | Evidence needed to close the gap |
| --- | --- | --- |
| [JavaScript and dependencies · #5](https://github.com/chadvictor/Silicanto/issues/5) | Haxe emitted for 970/970 WebGL 1 pages and 2,862/2,865 WebGL 2 pages. The mixed-module Canvas fixture rebuilds from Haxe on C, C++, Java and Neko after its original source directory is removed. | Translate and run the three generator cases. Verify dependency initialization and offline rebuilding on original application graphs. |
| [WebGL 1 · #6](https://github.com/chadvictor/Silicanto/issues/6) | On each target, 6/21 context pages passed, 3 failed assertions and 12 stopped during execution. All 178 OGLES shader build cases and 775 rendering comparisons passed. | Pass the outstanding context pages and run the full 970-page list on each target. Publish per-page assertion, skip and completion counts. |
| [WebGL 2 · #7](https://github.com/chadvictor/Silicanto/issues/7) | On each target, 8/9 context pages passed. The cross-context object test failed assertions. | Fix object validation, keep texture isolation passing and run the full 2,865-page list on each target. |
| [CSS layout · #8](https://github.com/chadvictor/Silicanto/issues/8) | 1,056 of 1,714 static WPT pairs differed on C++. Grid contributed 782 differences and flexbox 149. | Match the eligible references and publish gains and regressions on the same inputs. Measure fonts, external resources and dynamic layout as separate coverage expands. |
| [Phaser and interaction · #9](https://github.com/chadvictor/Silicanto/issues/9) | 136 C++ and 132 Java entries failed the complete three-frame capture. Of 1,925 comparable entries, 944 matched at all three marks. | Demonstrate each original entry's behavior on both targets. For interactive examples, specify input, timing and an observable outcome. For visual examples, compare against an independent reference. |

## Host and platform coverage

These issues track services an application can require. Each claim of support applies to a specific target and operating system.

| Work item | What works today | Next proof |
| --- | --- | --- |
| [Web Audio · #10](https://github.com/chadvictor/Silicanto/issues/10) | AVFoundation decodes and plays a WAV and delivers the media element's ended event. | Schedule a known signal through a native audio graph, measure the gain and verify completion on C++ and Java. |
| [Network streaming · #11](https://github.com/chadvictor/Silicanto/issues/11) | Fetch, XHR, native HTTPS and WebSocket text/binary transfers have coverage. | Read the first chunk before the server finishes the response. Verify ordering, abort and cleanup on both targets. |
| [Other platforms and engines · #12](https://github.com/chadvictor/Silicanto/issues/12) | Desktop GPU measurements cover Apple Silicon. Linux and Windows CI exercise portable JVM logic. | Publish the OS, GPU API, target and native frame/input results for each added payload. Pin and exercise an independently licensed application from a second engine. |

## Reproduce a failure

From a configured Apple Silicon checkout, use a new output path. This command runs the original WebGL 2 ownership page, records its assertions and exits with a failing status when a check fails.

```sh
mkdir -p dist
npm run test:webgl-pages -- --version 2.0.1 --target cpp \
  --filter conformance2/context/incorrect-context-object-behaviour.html \
  --out dist/webgl2-ownership.json
```

When updating an issue, include the compiler and upstream revisions, target, platform, command, first failed stage and the relevant assertion or pixel difference. Preserve the original sources and assets. The linked issues contain focused reproduction commands and completion criteria. [Contributor guide](../CONTRIBUTING.md) · [Full test commands](compatibility/native-desktop/README.md#reproduce-on-apple-silicon)
