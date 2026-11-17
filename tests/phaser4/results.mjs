// Summarize evidence without confusing an attempted process with a working game.
// A stricter independent replay may replace the frame measurements of a prior run.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
const [input, replay, output] = process.argv.slice(2);
const reports = [input, replay]
  .filter(Boolean)
  .map((p) => JSON.parse(readFileSync(p)));
const [all, confirmed] = reports;
assert.equal(all.catalogSize, 2061);
assert.equal(all.cases.length, all.catalogSize);
assert.equal(new Set(all.cases.map((c) => c.file)).size, all.catalogSize);
if (confirmed) {
  for (const k of ["engine", "engineSHA256", "revision", "target"])
    assert.equal(confirmed[k], all[k], k);
  const candidates = all.cases.filter((c) => c.status === "frame-matched"),
    checks = new Map(confirmed.cases.map((c) => [c.file, c]));
  assert.deepEqual(
    new Set(checks.keys()),
    new Set(candidates.map((c) => c.file)),
    "replay must cover all previous frame matches",
  );
  all.cases = all.cases.map((c) => checks.get(c.file) ?? c);
  all.oracle = confirmed.oracle;
}
const counts = {};
for (const c of all.cases) {
  const key = c.stage && c.status === "failed" ? c.stage + "-failed" : c.status;
  counts[key] = (counts[key] ?? 0) + 1;
  if (c.status === "frame-matched")
    assert.ok(
      c.measurement.foregroundMatched / c.measurement.foreground > 0.92,
      "missing foreground evidence for " + c.file,
    );
}
const matches = all.cases.filter((c) => c.status === "frame-matched");
all.counts = counts;
if (output) writeFileSync(output, JSON.stringify(all, null, 2) + "\n");
console.log(
  JSON.stringify(
    {
      engine: all.engine,
      revision: all.revision,
      target: all.target,
      selected: all.selected,
      executed: all.cases.filter((c) => c.executed).length,
      counts,
      exact: matches.filter((c) => c.measurement.mean === 0).length,
      matched: matches.map((c) => c.file),
    },
    null,
    2,
  ),
);
