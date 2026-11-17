import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { gzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";

const [input, out, compiler] = process.argv.slice(2);
if (!input || !out || !/^[0-9a-f]{40}$/.test(compiler ?? ""))
  throw Error("Expected report root, output directory and compiler commit");
const catalog = readFileSync(
  fileURLToPath(new URL("./catalog.tsv", import.meta.url)),
  "utf8",
)
  .trimEnd()
  .split("\n")
  .map((line) => line.split("\t")[1]);
const rows = new Map(catalog.map((file) => [file, { file }]));
const targets = {};
let revision, engine, engineSHA256;
for (const target of ["cpp", "java"]) {
  const r = JSON.parse(readFileSync(join(input, target, "report.json")));
  assert.equal(r.stage, "native");
  assert.equal(r.oracle, "native-rgba-timeline-v1");
  assert.equal(r.compiler, compiler);
  assert.equal(r.modifiedCompilerOrSuite, false);
  assert.equal(r.target, target);
  assert.equal(r.selected, catalog.length);
  assert.deepEqual(r.cases.map((c) => c.file).sort(), catalog.slice().sort());
  if (revision) {
    assert.equal(r.revision, revision);
    assert.equal(r.engineSHA256, engineSHA256);
    assert.equal(r.engine, engine);
  }
  revision = r.revision;
  engine = r.engine;
  engineSHA256 = r.engineSHA256;
  const s = { observed: 0, changing: 0, uniformAtEveryMark: 0, failed: 0 };
  for (const c of r.cases) {
    if (c.status === "native-observed") {
      const f = c.measurement.frames;
      assert.deepEqual(
        f.map((x) => x.frame),
        [1, 4, 12],
      );
      assert.ok(
        f.every(
          (x) => x.width > 0 && x.height > 0 && /^[a-f0-9]{64}$/.test(x.sha256),
        ),
      );
      s.observed++;
      if (c.measurement.distinct > 1) s.changing++;
      if (f.every((x) => x.uniform)) s.uniformAtEveryMark++;
      rows.get(c.file)[target] = f;
    } else {
      s.failed++;
      rows.get(c.file)[target] = {
        stage: c.stage ?? "bootstrap",
        diagnostic: c.diagnostic ?? r.bootstrap.diagnostic,
      };
    }
  }
  targets[target] = s;
}
let identical = 0,
  comparable = 0;
const table = ["source\tcpp\tjava\tidentical_rgba_at_all_marks"];
function describe(f) {
  return Array.isArray(f)
    ? f.every((x) => x.uniform)
      ? "uniform"
      : new Set(f.map((x) => x.sha256)).size > 1
        ? "changing"
        : "still"
    : "failed at " + f.stage;
}
for (const row of rows.values()) {
  const compared = Array.isArray(row.cpp) && Array.isArray(row.java);
  if (compared) comparable++;
  const same =
    compared &&
    row.cpp.every(
      (x, i) =>
        x.width === row.java[i].width &&
        x.height === row.java[i].height &&
        x.sha256 === row.java[i].sha256,
    );
  if (same) identical++;
  table.push(
    [
      row.file,
      describe(row.cpp),
      describe(row.java),
      compared ? (same ? "yes" : "no") : "",
    ].join("\t"),
  );
}
mkdirSync(out, { recursive: true });
const stats = {
  compiler,
  engine,
  engineSHA256,
  examplesCommit: revision,
  catalog: catalog.length,
  frames: [1, 4, 12],
  targets,
  comparable,
  identical,
};
writeFileSync(join(out, "summary.json"), JSON.stringify(stats, null, 2) + "\n");
writeFileSync(join(out, "matrix.tsv"), table.join("\n") + "\n");
writeFileSync(
  join(out, "frames.json.gz"),
  gzipSync(JSON.stringify([...rows.values()]), { level: 9 }),
);
console.log(stats);
