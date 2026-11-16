import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { resolve, join } from "node:path";
import { jdk } from "./jdk.mjs";

mkdirSync("dist", { recursive: true });
const work = mkdtempSync(resolve("dist/java-test-"));
const run = (cmd, args, cwd = process.cwd()) =>
  execFileSync(cmd, args, { cwd, encoding: "utf8", timeout: 120000 }).trim();
const cli = (...args) => run(process.execPath, ["src/cli.mjs", ...args]);
try {
  const source = join(work, "src"),
    project = join(work, "project"),
    out = join(work, "java");
  cpSync("tests/fixtures/modules", source, { recursive: true });
  const reference = Number(run(process.execPath, [join(source, "main.js")]));
  cli("emit", join(source, "main.js"), "--out", project);
  rmSync(source, { recursive: true });
  const file = join(project, "haxe/Sample.hx"),
    hx = readFileSync(file, "utf8");
  const edited = hx.replace(
    "WebConsole.log(v_sum);",
    "WebConsole.log(v_sum + 10.0);",
  );
  assert.notEqual(hx, edited);
  writeFileSync(file, edited);
  cli(
    "target",
    project,
    "--target",
    "java",
    "--platform",
    "jvm",
    "--name",
    "Logic",
    "--out",
    out,
  );
  const jar = join(work, "standalone.jar");
  cpSync(join(out, "java/Logic.jar"), jar);
  assert.deepEqual(
    JSON.parse(readFileSync(join(out, "manifest.json"))).payload,
    { apiVersion: 1, platform: "jvm", graphics: "none", profile: "logic" },
  );
  const classes = run(jdk("jar"), ["tf", jar]);
  assert.match(classes, /haxe\/root\/Sample.class/);
  assert.doesNotMatch(classes, /MetalDisplay|\.(?:js|dylib|dll|so)$/m);
  assert.ok(existsSync(join(out, "java/src/haxe/root/Sample.java")));
  rmSync(project, { recursive: true });
  rmSync(out, { recursive: true });
  assert.equal(Number(run(jdk("java"), ["-jar", jar], work)), reference + 10);
  console.log(
    "Edited Haxe compiled and ran from an isolated JVM JAR:",
    reference + 10,
  );
} finally {
  rmSync(work, { force: true, recursive: true });
}
