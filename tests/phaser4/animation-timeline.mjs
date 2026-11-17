// Cross-check a deterministic animation in two independently built standalone applications.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { jdk } from "../jdk.mjs";

const [checkout, cppDir, javaDir] = process.argv.slice(2);
if (!javaDir)
  throw Error(
    "Expected examples checkout, standalone C++ run, standalone Java run",
  );
const marks = [4, 12, 20, 30, 48];
const dir = mkdtempSync(join(tmpdir(), "silicanto-animation-"));
const revision = execFileSync("git", ["-C", checkout, "rev-parse", "HEAD"], {
  encoding: "utf8",
}).trim();
try {
  const results = [],
    reports = [];
  for (const [target, path] of [
    ["cpp", cppDir],
    ["java", javaDir],
  ]) {
    const r = JSON.parse(readFileSync(join(path, "report.json")));
    assert.equal(r.target, target);
    assert.equal(r.revision, revision);
    assert.equal(r.selected, 1);
    assert.equal(r.cases[0].status, "native-observed");
    reports.push(r);
    const file = join(dir, target + ".json"),
      args = [
        "--asset-root",
        join(resolve(checkout), "public"),
        "--frames",
        "48",
        "--timeline",
        file,
        marks.join(","),
      ];
    if (target === "cpp")
      execFileSync(join(resolve(path), "case-0/project/cpp/Sample"), args);
    else
      execFileSync(jdk("java"), [
        "-Djava.awt.headless=true",
        "-jar",
        join(resolve(path), "case-0/project/java/Sample.jar"),
        ...args,
      ]);
    const frames = JSON.parse(readFileSync(file));
    assert.deepEqual(
      frames.map((f) => f.frame),
      marks,
    );
    assert.ok(
      new Set(frames.map((f) => f.sha256)).size > 1,
      "Animation did not advance on " + target,
    );
    results.push(frames);
  }
  assert.equal(reports[0].engineSHA256, reports[1].engineSHA256);
  assert.equal(reports[0].cases[0].file, reports[1].cases[0].file);
  assert.deepEqual(results[0], results[1], "C++ and Java RGBA frames differ");
  console.log(
    reports[0].cases[0].file +
      " advanced and matched across targets at frames " +
      marks.join(", "),
  );
} finally {
  rmSync(dir, { recursive: true, force: true });
}
