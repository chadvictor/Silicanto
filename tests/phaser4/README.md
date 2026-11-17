# Phaser 4 compatibility suite

This suite is an external consumer of the normal Silicanto compiler. It loads the published engine, then the unmodified example and any required modules. There is no Phaser implementation or Phaser import substitution in the general compiler or its runtime.

The frozen [official gallery](https://phaser.io/oss/examples) lists **2,061 examples, 33 categories, Phaser 4.1.0**. [catalog.tsv](catalog.tsv) contains one published page and one upstream source path per row. It intentionally does not enumerate every JavaScript file: the repository also contains helper modules and historical examples. The [source revision](https://github.com/phaserjs/examples/tree/eb87db8355861ae222d0c5cd13aae54c2d7d72ae/public/src) and npm engine integrity digest are pinned. Assets are not redistributed. The test checkout includes the pinned example sources and assets (about 700 MiB of unpacked assets). Both the native process and browser use this source tree. The examples' own multi-script boot manifests and the gallery's document-relative module resolution are respected.

```sh
npm ci
npm ci --prefix tests/phaser4
npx playwright install chromium
npm run setup:c
npm run setup:java
npm run test:phaser4 -- --stage frontend --out dist/catalog-frontend
npm run test:phaser4 -- --stage bootstrap --target java --out dist/engine-java
npm run test:phaser4 -- --target java --out dist/catalog-java
npm run test:phaser4 -- --target cpp --out dist/catalog-cpp
```

See the [published native results](../../docs/compatibility/phaser4/README.md) for the tested compiler revision and the outcome of each example. To regenerate that table, run the three stages above with output paths ending in `frontend`, `java` and `cpp` under one directory (for example, `dist/phaser4-validation`), then run:

```sh
node tests/phaser4/results.mjs dist/phaser4-validation dist/phaser4-results "$(git rev-parse HEAD)"
```

Run the stages from a clean checkout. The publisher rejects incomplete reports and mismatched catalogs; newly stamped reports must also agree on the clean compiler and suite revision. The native commands exit nonzero while any cases fail; keep both reports.

To reproduce a single example as an ordinary standalone application:

```sh
npm run test:phaser4 -- --target java --filter 'graphics/stroke rect.js' --out dist/stroke
java -jar dist/stroke/case-0/project/java/Sample.jar --window
```

The PNG animation has an additional test: the sprite must change over time, and every pixel on both targets must equal Chromium at frames 4, 12, 20, 30 and 48. Build two standalone copies of the original example, then run the timeline:

```sh
npm run test:phaser4 -- --target cpp --filter 'animation/animation from png sequence.js' --out dist/animation-cpp
npm run test:phaser4 -- --target java --filter 'animation/animation from png sequence.js' --out dist/animation-java
node tests/phaser4/animation-timeline.mjs .toolchain/phaser-examples dist/animation-cpp dist/animation-java
dist/animation-cpp/case-0/project/cpp/Sample --asset-root .toolchain/phaser-examples/public --window
```

The runner clones the upstream repository on first use. Supply `--checkout PATH` to use an existing clean checkout of the pinned revision. Output directories must be new. Neko is also selectable; generating bytecode for the complete bundled engine takes much longer than building a small Neko app.

- **Frontend** translates each example's own source graph and records diagnostics independently of the shared engine. It does not compile Haxe or run a frame.
- **Bootstrap** builds the original UMD engine and runs its module initializers in a target process. If it fails, all dependent samples are blocked, and none are counted as executed.
- **Native** compiles samples and runs each in a fresh process. By default related compilations share the engine and target build in batches; the dispatcher is test code in Haxe, and it selects a single module graph before the first frame. Build errors are isolated to individual samples. Use `--batch-size 1` to build independent standalone projects. Filtered single-example runs always build the real app directly through the CLI. For an exact selection, pass `--cases paths.txt` (one catalog source path per line).
- **Reference** runs the unchanged scripts in Chromium, advances four frame callbacks and compares the fourth frame with the target's PPM. A uniform browser frame cannot pass. Dimensions must match; mean absolute RGB error must be below 4, and over 92% of both the frame and its non-background pixels must match within 8 levels per channel. Blocked assets or an upstream exception produce diagnostics. External network requests outside the pinned source are not accepted as reproducible references.
- **Exit status** is nonzero on failure. Each run writes a machine-readable report with each page, source file, stage and outcome. The result label `frame-matched` is deliberately narrow. Four frames cannot verify keyboard interaction, audio playback, loading transitions, or a complete playthrough. Those need explicit scenarios and observable assertions before a general 1.0 compatibility claim.

The native renderer must honor an explicitly requested WebGL context. Editing an example to force Canvas, embedding its JavaScript, or substituting hand-written code for the framework invalidates the result.
