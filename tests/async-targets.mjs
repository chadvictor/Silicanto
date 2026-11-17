import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { jdk } from "./jdk.mjs";
const root = fileURLToPath(new URL("../", import.meta.url));
const work = mkdtempSync(join(tmpdir(), "silicanto-async-"));
const run = (exe, args) =>
  execFileSync(exe, args, {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 16 << 20,
  });
try {
  const source = join(work, "source");
  run(process.execPath, [
    "src/cli.mjs",
    "emit",
    "tests/fixtures/async/main.mjs",
    "--frontend",
    "generic",
    "--out",
    source,
  ]);
  const manifest = JSON.parse(readFileSync(join(source, "manifest.json")));
  assert.equal(manifest.asyncLowering, true);
  assert.equal(manifest.webHost, false);
  assert.ok(existsSync(join(source, "licenses/async-to-promises.txt")));
  for (const target of ["cpp", "java", "neko", "c"]) {
    const project = join(work, target);
    run(process.execPath, [
      "src/cli.mjs",
      "target",
      source,
      "--target",
      target,
      "--out",
      project,
    ]);
    const output =
      target === "java"
        ? run(jdk("java"), ["-jar", join(project, "java/Sample.jar")])
        : target === "neko"
          ? run("bash", [
              "-c",
              'source scripts/tool-env.sh && exec neko "$@"',
              "_",
              join(project, "neko/Sample.n"),
            ])
          : run(join(project, target, "Sample"), []);
    assert.match(
      output,
      /^native async contracts passed$/m,
      target + ": " + output,
    );
    console.log(
      target + ": native await, rejection, finally, all and race passed",
    );
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
