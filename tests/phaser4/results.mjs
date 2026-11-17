// Convert complete target reports into a portable, reviewable compatibility matrix.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const [input, out, compiler, baselineCommit] = process.argv.slice(2);
if (!input || !out || !/^[a-f0-9]{40}$/.test(compiler ?? ""))
  throw Error(
    "Usage: node tests/phaser4/results.mjs REPORT_ROOT OUTPUT_DIR COMPILER_COMMIT [BASELINE_REPORT_COMMIT]",
  );
const suite = fileURLToPath(new URL("./", import.meta.url));
const catalog = readFileSync(join(suite, "catalog.tsv"), "utf8")
  .trimEnd()
  .split("\n")
  .map((line) => line.split("\t")[1]);
const reports = Object.fromEntries(
  ["frontend", "java", "cpp"].map((name) => [
    name,
    JSON.parse(readFileSync(join(input, name, "report.json"))),
  ]),
);
assert.equal(reports.frontend.stage, "frontend");
const byFile = {};
for (const [name, r] of Object.entries(reports)) {
  // Older raw reports predate the compiler stamp; the explicit snapshot argument
  // identifies them. For new runs, never relabel dirty or mixed compiler revisions.
  if ("compiler" in r) {
    assert.equal(r.compiler, compiler, "compiler commit differs from run");
    assert.equal(
      r.modifiedCompilerOrSuite,
      false,
      "uncommitted compiler or suite",
    );
  }
  assert.equal(r.engine, "4.1.0");
  assert.equal(r.selected, catalog.length);
  assert.equal(r.cases.length, catalog.length, name + " is unfinished");
  assert.equal(r.revision, reports.frontend.revision);
  if (name !== "frontend") {
    assert.equal(r.target, name);
    assert.equal(r.stage, "native");
    assert.ok(["passed", "failed"].includes(r.bootstrap.status));
    if (r.bootstrap.status === "failed")
      assert.ok(
        r.cases.every((c) => c.status === "blocked-by-engine" && !c.executed),
      );
    assert.equal(r.oracle, "fourth-frame-foreground-v2");
  }
  byFile[name] = new Map(r.cases.map((c) => [c.file, c]));
  assert.deepEqual(new Set(byFile[name].keys()), new Set(catalog));
}
assert.equal(reports.java.engineSHA256, reports.cpp.engineSHA256);
assert.match(reports.java.engineSHA256 ?? "", /^[a-f0-9]{64}$/);
function reason(c) {
  const s = c.diagnostic ?? "";
  if (c.status === "frame-matched") return "matched";
  if (c.status === "blocked-by-engine") return "shared engine failed";
  if (
    /Cannot create WebGL context|WebGL unsupported|WebGL is not supported/i.test(
      s,
    )
  )
    return "WebGL context";
  if (/Fragment Shader failed|Vertex Shader failed/i.test(s))
    return "GLSL compilation";
  if (/Failed to link (?:the )?program/i.test(s)) return "GLSL program link";
  if (/Uniform reference/.test(s))
    return "uniform reference; needs behavior test";
  if (/Frame mismatch/.test(s)) return "different pixels";
  if (/Frame dimensions differ/.test(s)) return "different dimensions";
  if (/No reference canvas/.test(s)) return "reference has no canvas";
  if (/Missing asset|External resource/.test(s))
    return "missing or unpinned reference resource";
  if (/timeout|ETIMEDOUT|timed out/i.test(s)) return "time limit";
  if (/E-CANVAS: nothing to capture/.test(s)) return "no target canvas";
  const cap = s.match(
    /(E-(?:DOM|CANVAS|IMAGE|XHR|ASSET|WEBGL)):\s*([^\n]{1,90})/,
  );
  if (cap)
    return (
      cap[1] +
      ": " +
      cap[2].replace(/(?:file:|\/Users\/|https?:\/\/).*$/, "resource")
    );
  const call = s.match(
    /([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*) TypeError: value is not (callable|a constructor)/,
  );
  if (call) return "missing call: " + call[1];
  const ref = s.match(/ReferenceError: ([\w$]+) is not defined/);
  if (ref) return "missing global: " + ref[1];
  const read = s.match(/TypeError: cannot (read|write) ([\w$]+)/);
  if (read) return "property " + read[1] + ": " + read[2];
  if (/ClassCastException/.test(s)) return "JVM runtime type mismatch";
  if (/stack nearly exhausted|stack overflow/i.test(s) && c.stage === "build")
    return "native compiler stack limit";
  if (
    /expression too complex|code too large|too large for try statement/i.test(
      s,
    ) &&
    c.stage === "build"
  )
    return "target method size or complexity";
  return c.stage + " diagnostic";
}
const stats = {
  compiler,
  engine: reports.java.engine,
  engineSHA256: reports.java.engineSHA256,
  examplesCommit: reports.java.revision,
  oracle: reports.java.oracle,
  catalog: catalog.length,
  frontend: {},
  matchedOnBoth: 0,
  engineBootstrap: Object.fromEntries(
    ["cpp", "java"].map((t) => [t, reports[t].bootstrap.status]),
  ),
  targets: {},
};
const header = [
  "source",
  "frontend",
  ...["cpp", "java"].flatMap((t) =>
    [
      "stage",
      "result",
      "mean_rgb_error",
      "within8_fraction",
      "foreground_matched",
      "foreground_pixels",
    ].map((k) => t + "_" + k),
  ),
];
const comparisonText = [];
let previous;
if (baselineCommit) {
  assert.match(baselineCommit, /^[a-f0-9]{40}$/);
  const readBaseline = (name) =>
    execFileSync(
      "git",
      ["show", baselineCommit + ":docs/compatibility/phaser4/" + name],
      { cwd: suite, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );
  const baseline = JSON.parse(readBaseline("summary.json"));
  for (const key of ["oracle", "engineSHA256", "examplesCommit", "catalog"])
    assert.equal(baseline[key], stats[key], "incompatible baseline " + key);
  const [columns, ...data] = readBaseline("matrix.tsv")
    .trimEnd()
    .split("\n")
    .map((row) => row.split("\t"));
  const indexes = ["cpp_stage", "java_stage"].map((name) =>
    columns.indexOf(name),
  );
  assert.ok(indexes.every((i) => i >= 0));
  previous = new Map(
    data.map((row) => [row[0], indexes.map((i) => row[i] === "matched")]),
  );
  assert.deepEqual(new Set(previous.keys()), new Set(catalog));
  stats.comparison = {
    reportCommit: baselineCommit,
    compiler: baseline.compiler,
    targets: {},
  };
  for (const [target, matched] of [
    ["cpp", baseline.targets.cpp.matched],
    ["java", baseline.targets.java.matched],
    ["both", baseline.matchedOnBoth],
  ]) {
    stats.comparison.targets[target] = {
      previous: matched,
      gained: 0,
      lost: 0,
      retained: 0,
    };
    header.push(target + "_change");
  }
}
const rows = [header.join("\t")];
for (const target of ["cpp", "java"])
  stats.targets[target] = {
    attempted: 0,
    returnedFrame: 0,
    matched: 0,
    exact: 0,
    stages: {},
    reasons: {},
  };
for (const file of catalog) {
  const fe = byFile.frontend.get(file).status,
    row = [file, fe];
  stats.frontend[fe] = (stats.frontend[fe] ?? 0) + 1;
  for (const target of ["cpp", "java"]) {
    const c = byFile[target].get(file),
      t = stats.targets[target],
      ok = c.status === "frame-matched",
      stage = ok ? "matched" : (c.stage ?? c.status),
      why = reason(c);
    if (c.executed) t.attempted++;
    if (ok || stage === "compare" || stage === "reference") t.returnedFrame++;
    if (ok) {
      assert.ok(
        c.measurement.foreground > 0 &&
          c.measurement.foregroundMatched / c.measurement.foreground > 0.92 &&
          c.measurement.mean < 4 &&
          c.measurement.within8 > 0.92,
      );
      t.matched++;
      if (c.measurement.mean === 0) t.exact++;
    }
    t.stages[stage] = (t.stages[stage] ?? 0) + 1;
    if (!ok) t.reasons[why] = (t.reasons[why] ?? 0) + 1;
    const mismatch = c.diagnostic?.match(
      /Frame mismatch: mean ([\d.e+-]+), within8 ([\d.e+-]+), foreground (\d+)\/(\d+)/,
    );
    const pixels = ok
      ? [
          c.measurement.mean,
          c.measurement.within8,
          c.measurement.foregroundMatched,
          c.measurement.foreground,
        ]
      : (mismatch?.slice(1) ?? ["-", "-", "-", "-"]);
    row.push(stage, why.replace(/[\t\r\n]/g, " "), ...pixels);
  }
  if (
    byFile.cpp.get(file).status === "frame-matched" &&
    byFile.java.get(file).status === "frame-matched"
  )
    stats.matchedOnBoth++;
  if (previous) {
    const before = previous.get(file),
      after = ["cpp", "java"].map(
        (t) => byFile[t].get(file).status === "frame-matched",
      );
    before.push(before.every(Boolean));
    after.push(after.every(Boolean));
    for (const [i, t] of ["cpp", "java", "both"].entries()) {
      const change = after[i]
        ? before[i]
          ? "retained"
          : "gained"
        : before[i]
          ? "lost"
          : "unmatched";
      row.push(change);
      if (change !== "unmatched") stats.comparison.targets[t][change]++;
    }
  }
  rows.push(row.join("\t"));
}
if (previous) {
  comparisonText.push(
    "## Changes since the previous gallery run",
    "",
    "| Target | Previously matched | Newly matched | Previously matched, now failed | Still matched |",
    "| --- | ---: | ---: | ---: | ---: |",
  );
  for (const [target, c] of Object.entries(stats.comparison.targets)) {
    const current =
      target === "both" ? stats.matchedOnBoth : stats.targets[target].matched;
    assert.equal(c.lost + c.retained, c.previous);
    assert.equal(c.gained + c.retained, current);
    const label = { cpp: "C++", java: "Java", both: "Both targets" }[target];
    comparisonText.push(
      `| ${label} | ${c.previous} | ${c.gained} | ${c.lost} | ${c.retained} |`,
    );
  }
  comparisonText.push(
    "",
    `The [baseline matrix](https://github.com/chadvictor/Silicanto/blob/${baselineCommit}/docs/compatibility/phaser4/matrix.tsv) uses the same catalog, engine and fourth-frame comparison. Filter the current matrix by the \`cpp_change\`, \`java_change\` or \`both_change\` column to identify the individual cases.`,
    "",
  );
}
for (const t of Object.values(stats.targets))
  t.reasons = Object.fromEntries(
    Object.entries(t.reasons).sort(
      ([a, n], [b, m]) => m - n || a.localeCompare(b),
    ),
  );
mkdirSync(out, { recursive: true });
writeFileSync(join(out, "matrix.tsv"), rows.join("\n") + "\n");
writeFileSync(join(out, "summary.json"), JSON.stringify(stats, null, 2) + "\n");
console.log(
  Object.fromEntries(
    Object.entries(stats.targets).map(
      ([k, { attempted, returnedFrame, matched, exact }]) => [
        k,
        { attempted, returnedFrame, matched, exact },
      ],
    ),
  ),
);

const rowsByTarget = ["cpp", "java"].map((target) => {
  const t = stats.targets[target];
  return [
    target === "cpp" ? "C++" : "Java",
    stats.catalog,
    t.attempted,
    t.returnedFrame,
    t.matched,
    t.exact,
  ].join(" | ");
});
const reasons = [
  ...new Set(
    Object.values(stats.targets).flatMap((t) => Object.keys(t.reasons)),
  ),
];
const count = (target, why) => stats.targets[target].reasons[why] ?? 0;
const total = (why) => count("cpp", why) + count("java", why);
const leading = reasons
  .sort((a, b) => total(b) - total(a) || a.localeCompare(b))
  .slice(0, 8);
const sourceURL =
  "https://github.com/phaserjs/examples/tree/" +
  stats.examplesCommit +
  "/public/src";
const compilerURL =
  "https://github.com/chadvictor/Silicanto/commit/" + stats.compiler;
const page = [
  "# Can Silicanto run the Phaser 4 example gallery?",
  "",
  `Of the ${stats.catalog.toLocaleString("en-US")} entries in the pinned [Phaser ${stats.engine} gallery](https://phaser.io/oss/examples), **${stats.matchedOnBoth} produced a matching fourth frame on both C++ and Java**. This measures the fourth rendered frame. Playability requires interaction and longer-running scenarios.`,
  "",
  `The compiler emitted editable Haxe from **${stats.frontend["haxe-emitted"] ?? 0}** example source graphs. The original Phaser distribution was compiled from JavaScript as a shared prerequisite. Engine initialization **${stats.engineBootstrap.cpp}** on C++ and **${stats.engineBootstrap.java}** on Java. Both targets used the original example sources and the generic web runtime.`,
  "",
  "| Target | Catalog entries | Target process launched | Reached frame comparison | Matched Chromium | Pixel-exact |",
  "| --- | ---: | ---: | ---: | ---: | ---: |",
  ...rowsByTarget.map((r) => "| " + r + " |"),
  "",
  "Each example runs in a fresh process. The reference is the same example and engine in Chromium. A match requires the same dimensions, a nonuniform reference, mean absolute RGB error below 4, and more than 92% agreement within 8 levels per channel on both the full frame and the foreground. Pixel-exact means every channel was identical. A reference without a reproducible frame is not a pass.",
  "",
  ...comparisonText,
  "## What prevents more examples from passing?",
  "",
  "These are the most frequent first diagnostics in this run. A later problem can be hidden by an earlier one. A uniform reference can be valid for a nonvisual or interactive example; it needs a different behavioral assertion. Differences can also reflect timing, randomness or missing reference assets.",
  "",
  "| First diagnostic | C++ | Java |",
  "| --- | ---: | ---: |",
  ...leading.map(
    (why) =>
      `| ${why.replaceAll("|", "/")} | ${count("cpp", why)} | ${count("java", why)} |`,
  ),
  "",
  "The [case matrix](matrix.tsv) lists every upstream source with its first failing stage or visual result, and pixel measurements for both matches and measurable differences. The [machine-readable summary](summary.json) contains counts for all stages and diagnostics. Each diagnostic describes the first observed failure on this revision.",
  "",
  "## Reproduce",
  "",
  `Use [Silicanto ${stats.compiler.slice(0, 7)}](${compilerURL}), the pinned [upstream examples](${sourceURL}) and the [suite instructions](../../../tests/phaser4/README.md). The engine SHA-256 is \`${stats.engineSHA256}\`. The full matrix covers C++ and Java on Apple Silicon.`,
  "",
  "For a check beyond a still image, the [animation timeline test](../../../tests/phaser4/animation-timeline.mjs) compares five captures from the standalone PNG sequence or WebGL texture atlas apps with Chromium and requires visible movement on both targets. Games that depend on input, audio or external services need scenarios of their own.",
  "",
];
writeFileSync(join(out, "README.md"), page.join("\n"));
