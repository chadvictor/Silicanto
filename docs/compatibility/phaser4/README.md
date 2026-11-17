# Can Silicanto run the Phaser 4 example gallery?

Of the 2,061 entries in the pinned [Phaser 4.1.0 gallery](https://phaser.io/oss/examples), **144 produced a matching fourth frame on both C++ and Java**. This measures a rendered frame, not whether a complete game is playable.

The compiler emitted editable Haxe from **2061** example source graphs. The original Phaser distribution was compiled from JavaScript as a shared prerequisite. Engine initialization: C++ **passed**, Java **passed**. No examples were rewritten and no framework adapter was used.

| Target | Catalog entries | Target process launched | Reached frame comparison | Matched Chromium | Pixel-exact |
| --- | ---: | ---: | ---: | ---: | ---: |
| C++ | 2061 | 2060 | 409 | 145 | 91 |
| Java | 2061 | 2057 | 407 | 144 | 92 |

Each example runs in a fresh process. The reference is the same example and engine in Chromium. A match requires the same dimensions, a nonuniform reference, mean absolute RGB error below 4, and more than 92% agreement within 8 levels per channel on both the full frame and the foreground. Pixel-exact means every channel was identical. A reference without a reproducible frame is not a pass.

## What prevents more examples from passing?

These are the most frequent first diagnostics in this run. A later problem can be hidden by an earlier one. A uniform reference can be valid for a nonvisual or interactive example; it needs a different behavioral assertion. Differences can also reflect timing, randomness or missing reference assets.

| First diagnostic | C++ | Java |
| --- | ---: | ---: |
| WebGL context | 436 | 436 |
| missing call: context.measureText | 268 | 271 |
| different pixels | 225 | 224 |
| run diagnostic | 319 | 1 |
| missing call: source.hasOwnProperty | 141 | 142 |
| missing call: Array.from | 117 | 117 |
| missing global: JSON | 8 | 223 |
| missing call: ctx.arc | 64 | 64 |

The [case matrix](matrix.tsv) lists every upstream source with its first failing stage or visual result, and pixel measurements for both matches and measurable differences. The [machine-readable summary](summary.json) contains counts for all stages and diagnostics. These are observations for the tested revision, not permanent exclusions.

## Reproduce

Use [Silicanto 92e6075](https://github.com/chadvictor/Silicanto/commit/92e60752e1883aedf97335707b6b4be1de260442), the pinned [upstream examples](https://github.com/phaserjs/examples/tree/eb87db8355861ae222d0c5cd13aae54c2d7d72ae/public/src) and the [suite instructions](../../../tests/phaser4/README.md). The engine SHA-256 is `71d92687457da59f1233c75827df628ba173e2ad329d3c75f4e4b92d27c9dd1e`. The full matrix covers C++ and Java; it does not establish gallery compatibility on C or Neko.

For a check beyond a still image, the [animation timeline test](../../../tests/phaser4/animation-timeline.mjs) builds on the PNG sequence example's standalone apps, compares five captures with Chromium, and requires the sprite to change. Games that depend on input, audio or external services need scenarios of their own.
