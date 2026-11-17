# Phaser 4 native compatibility suite

The runner compiles Phaser 4.1.0 and each original example through the general JavaScript frontend. Each example starts in a fresh target process. The pinned gallery contains 2,061 sources in 33 categories. Script order, assets and module roots follow the upstream viewer. [Catalog](catalog.tsv) · [Upstream sources](https://github.com/phaserjs/examples/tree/eb87db8355861ae222d0c5cd13aae54c2d7d72ae/public/src)

```sh
npm ci
npm ci --prefix tests/phaser4
npm run setup:c
npm run setup:java
npm run test:phaser4 -- --stage frontend --out dist/catalog/frontend
npm run test:phaser4 -- --target cpp --out dist/catalog/cpp
npm run test:phaser4 -- --target java --out dist/catalog/java
node tests/phaser4/native-results.mjs dist/catalog dist/catalog-results "$(git rev-parse HEAD)"
```

The first run fetches the pinned upstream checkout (about 700 MiB unpacked). Use `--checkout PATH` to reuse it. The suite checks both the examples revision and npm engine digest. Choose fresh output directories. Each report carries the compiler revision and a flag identifying local source edits. Publication requires complete reports from one clean checkout.

**What the test measures.** Each native process advances 12 frame callbacks. Frames 1, 4 and 12 record the dimensions, a SHA-256 of raw RGBA pixels and whether all pixels have the same color. The report distinguishes changing, static and uniform output, build or runtime errors, and exact agreement across targets. Randomized scenes can legitimately differ between independent processes. A successful observation alone does not establish correct visuals, responsiveness or a complete playthrough. The desktop integration test separately exercises input, audio and network with explicit assertions.

**Build stages.** `--stage frontend` translates each source graph. `--stage bootstrap` builds and runs the shared engine. The default builds complete native apps and gathers frames. Batched runs share the engine compilation and isolate failed builds. A filtered single-example run uses the ordinary CLI to build a standalone executable. For a selected group pass `--cases paths.txt` with one catalog path per line. A failing build, process or incomplete trace sets a nonzero exit code and remains in the JSON report.

```sh
npm run test:phaser4 -- --target cpp --filter 'animation/animation from png sequence.js' --out dist/png-cpp
npm run test:phaser4 -- --target java --filter 'animation/animation from png sequence.js' --out dist/png-java
node tests/phaser4/animation-timeline.mjs .toolchain/phaser-examples dist/png-cpp dist/png-java
dist/png-cpp/case-0/project/cpp/Sample --asset-root .toolchain/phaser-examples/public --window
```

The standalone animation check requires the scene to advance and both targets to produce identical RGBA frames at 4, 12, 20, 30 and 48. The earlier fourth-frame visual benchmark is preserved with its original methodology. [Historical results](../../docs/compatibility/phaser4/README.md)
