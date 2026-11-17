import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { jdk } from "../jdk.mjs";
const root = fileURLToPath(new URL("../../", import.meta.url)),
  source = fileURLToPath(new URL("library-logic.cjs", import.meta.url));
const run = (exe, args) =>
  execFileSync(exe, args, {
    cwd: root,
    encoding: "utf8",
    timeout: 300000,
  }).trim();
mkdirSync(join(root, "dist"), { recursive: true });
const work = mkdtempSync(join(root, "dist/source-libraries-"));
try {
  const expected = run(process.execPath, [source]),
    hx = join(work, "source");
  run(process.execPath, [
    "src/cli.mjs",
    "emit",
    source,
    "--frontend",
    "generic",
    "--out",
    hx,
  ]);
  const manifest = JSON.parse(readFileSync(join(hx, "manifest.json")));
  assert.ok(manifest.inputs.some((i) => i.file.includes("eventemitter3")));
  assert.ok(manifest.inputs.some((i) => i.file.endsWith("DistanceBetween.js")));
  for (const t of ["java", "cpp", "neko"]) {
    const output = join(work, t);
    run(process.execPath, [
      "src/cli.mjs",
      "target",
      hx,
      "--target",
      t,
      "--out",
      output,
    ]);
    const result =
      t === "java"
        ? run(jdk("java"), ["-jar", join(output, "java/Sample.jar")])
        : t === "neko"
          ? run("bash", [
              "-c",
              'source scripts/tool-env.sh && exec neko "$@"',
              "_",
              join(output, "neko/Sample.n"),
            ])
          : run(join(output, "cpp/Sample"), []);
    assert.equal(result, expected, t);
    console.log(t + ": " + result.replaceAll("\n", "; "));
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
