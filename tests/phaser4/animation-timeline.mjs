// Compare a changing upstream scene at several times, in standalone target builds.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { jdk } from "../jdk.mjs";
import {
  closeReferenceBrowser,
  compareFrame,
  referenceFrame,
} from "./reference.mjs";

const [sourceTree, cppDir, javaDir, mode = "exact"] = process.argv.slice(2);
if (!sourceTree || !cppDir || !javaDir || !["exact", "gallery"].includes(mode))
  throw Error(
    "Usage: node tests/phaser4/animation-timeline.mjs CHECKOUT CPP_RUN JAVA_RUN [exact|gallery]",
  );
const checkout = resolve(sourceTree);
const pub = join(checkout, "public");
const engine = fileURLToPath(
  new URL("./node_modules/phaser/dist/phaser.js", import.meta.url),
);
const reports = [cppDir, javaDir].map((dir, index) => {
  const r = JSON.parse(readFileSync(join(dir, "report.json")));
  assert.equal(r.target, index === 0 ? "cpp" : "java");
  assert.equal(r.selected, 1);
  assert.equal(r.cases[0].status, "frame-matched");
  return r;
});
const file = reports[0].cases[0].file;
assert.equal(reports[1].cases[0].file, file);
const revision = execFileSync("git", ["-C", checkout, "rev-parse", "HEAD"], {
  encoding: "utf8",
}).trim();
const hash = (b) => createHash("sha256").update(b).digest("hex");
for (const r of reports) {
  assert.equal(r.revision, revision);
  assert.equal(r.engineSHA256, hash(readFileSync(engine)));
}
const work = mkdtempSync(join(tmpdir(), "silicanto-timeline-"));
const unique = new Set();
const nativeFrames = [new Set(), new Set()];
const targets = [
  [join(resolve(cppDir), "case-0/project/cpp/Sample"), []],
  [
    jdk("java"),
    [
      "-Djava.awt.headless=true",
      "-jar",
      join(resolve(javaDir), "case-0/project/java/Sample.jar"),
    ],
  ],
];
try {
  for (const frames of [4, 12, 20, 30, 48]) {
    const ref = await referenceFrame({
      reuse: true,
      pub,
      checkout,
      engine,
      rev: revision,
      frames,
      html:
        '<!doctype html><div id="phaser-example"></div><script src="/engine.js"></script><script src="/' +
        encodeURI(file) +
        '"></script>',
    });
    unique.add(hash(Buffer.from(ref.pixels, "base64")));
    for (const [index, [exe, args]] of targets.entries()) {
      const ppm = join(work, "frame.ppm");
      rmSync(ppm, { force: true });
      execFileSync(
        exe,
        [
          ...args,
          "--frames",
          String(frames),
          "--asset-root",
          pub,
          "--capture",
          ppm,
        ],
        { timeout: 60000 },
      );
      const pixels = readFileSync(ppm);
      const measurement = compareFrame(pixels, ref);
      nativeFrames[index].add(hash(pixels));
      if (mode === "exact")
        assert.equal(
          measurement.mean,
          0,
          "Frame " + frames + " differs from Chromium",
        );
      console.log(
        "%s frame %d: mean RGB error %s, within tolerance %s",
        index === 0 ? "cpp" : "java",
        frames,
        measurement.mean.toFixed(6),
        measurement.within8.toFixed(6),
      );
    }
  }
  assert.ok(
    nativeFrames.every((frames) => frames.size > 1),
    "A target animation never visibly advanced",
  );
  assert.ok(unique.size > 1, "The reference animation never visibly advanced");
} finally {
  await closeReferenceBrowser();
  rmSync(work, { recursive: true, force: true });
}
