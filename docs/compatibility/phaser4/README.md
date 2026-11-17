# Can Silicanto run the Phaser 4 example gallery?

Of the 2,061 entries in the pinned [Phaser 4.1.0 gallery](https://phaser.io/oss/examples), **927 produced a matching fourth frame on both C++ and Java**. This measures the fourth rendered frame. Playability requires interaction and longer-running scenarios.

The compiler emitted editable Haxe from **2061** example source graphs. The original Phaser distribution was compiled from JavaScript as a shared prerequisite. Engine initialization **passed** on C++ and **passed** on Java. Both targets used the original example sources and the generic web runtime.

| Target | Catalog entries | Target process launched | Reached frame comparison | Matched Chromium | Pixel-exact |
| --- | ---: | ---: | ---: | ---: | ---: |
| C++ | 2061 | 2061 | 1792 | 955 | 272 |
| Java | 2061 | 2061 | 1795 | 955 | 292 |

Each example runs in a fresh process. The reference is the same example and engine in Chromium. A match requires the same dimensions, a nonuniform reference, mean absolute RGB error below 4, and more than 92% agreement within 8 levels per channel on both the full frame and the foreground. Pixel-exact means every channel was identical. A reference without a reproducible frame is not a pass.

## Changes since the previous gallery run

| Target | Previously matched | Newly matched | Previously matched, now failed | Still matched |
| --- | ---: | ---: | ---: | ---: |
| C++ | 145 | 810 | 0 | 145 |
| Java | 144 | 811 | 0 | 144 |
| Both targets | 144 | 783 | 0 | 144 |

The [baseline matrix](https://github.com/chadvictor/Silicanto/blob/072aabacee35be861da675d9725de8a37db0a046/docs/compatibility/phaser4/matrix.tsv) uses the same catalog, engine and fourth-frame comparison. Filter the current matrix by the `cpp_change`, `java_change` or `both_change` column to identify the individual cases.

## What prevents more examples from passing?

These are the most frequent first diagnostics in this run. A later problem can be hidden by an earlier one. A uniform reference can be valid for a nonvisual or interactive example; it needs a different behavioral assertion. Differences can also reflect timing, randomness or missing reference assets.

| First diagnostic | C++ | Java |
| --- | ---: | ---: |
| different pixels | 753 | 758 |
| property write: beforeUpdate | 82 | 82 |
| uniform reference; needs behavior test | 63 | 60 |
| GLSL compilation | 27 | 27 |
| missing global: dat | 26 | 26 |
| property read: data | 26 | 26 |
| no target canvas | 17 | 17 |
| property write: zIndex | 16 | 16 |

The [case matrix](matrix.tsv) lists every upstream source with its first failing stage or visual result, and pixel measurements for both matches and measurable differences. The [machine-readable summary](summary.json) contains counts for all stages and diagnostics. Each diagnostic describes the first observed failure on this revision.

## Reproduce

Use [Silicanto 8e4ef6b](https://github.com/chadvictor/Silicanto/commit/8e4ef6bc75476b059c9e5552f49ea00fee51db0d), the pinned [upstream examples](https://github.com/phaserjs/examples/tree/eb87db8355861ae222d0c5cd13aae54c2d7d72ae/public/src) and the [suite instructions](../../../tests/phaser4/README.md). The engine SHA-256 is `71d92687457da59f1233c75827df628ba173e2ad329d3c75f4e4b92d27c9dd1e`. The full matrix covers C++ and Java on Apple Silicon.

For a check beyond a still image, the [animation timeline test](../../../tests/phaser4/animation-timeline.mjs) compares five captures from the standalone PNG sequence or WebGL texture atlas apps with Chromium and requires visible movement on both targets. Games that depend on input, audio or external services need scenarios of their own.
