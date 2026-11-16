import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
process.chdir(root);
mkdirSync("dist", { recursive: true });
const work = mkdtempSync(path.resolve("dist/haxe-e2e-"));
const run = (exe, args) =>
  execFileSync(exe, args, { encoding: "utf8", timeout: 180000 }).trim();
const cli = (...args) => run(process.execPath, ["src/cli.mjs", ...args]);
try {
  const source = path.join(work, "source"),
    project = path.join(work, "project");
  cpSync("tests/fixtures/modules", source, { recursive: true });
  const original = run(process.execPath, [path.join(source, "main.js")]);
  cli("emit", path.join(source, "main.js"), "--out", project);
  const entry = path.join(project, "haxe/Sample.hx"),
    hx = readFileSync(entry, "utf8");
  assert.match(hx, /function v_sampleHeight/);
  assert.match(hx, /function v_lerp/);
  const inputs = JSON.parse(
    readFileSync(path.join(project, "manifest.json")),
  ).inputs;
  assert.ok(inputs.some((i) => i.file.endsWith("three/src/math/MathUtils.js")));
  assert.ok(inputs.some((i) => i.file === "height.js"));
  rmSync(source, { recursive: true });
  // Simulate receiving just the Haxe project. Every backend reads it after the move.
  const detached = path.join(work, "detached");
  renameSync(project, detached);
  const nativeResults = {};
  for (const [target, executable, arg] of [
    ["c", "c/Sample"],
    ["cpp", "cpp/Sample"],
    ["js", process.execPath, "js/program.js"],
    ["python", "python3", "python/program.py"],
  ]) {
    const out = path.join(work, target);
    cli("target", detached, "--target", target, "--out", out);
    assert.equal(readFileSync(path.join(out, "haxe/Sample.hx"), "utf8"), hx);
    const actual = arg
      ? run(executable, [path.join(out, arg)])
      : run(path.join(out, executable), []);
    assert.equal(actual, original, target);
    nativeResults[target] = actual;
    if (target === "c") {
      assert.match(
        run("file", [path.join(out, executable)]),
        /Mach-O 64-bit executable arm64/,
      );
      assert.ok(existsSync(path.join(out, "c/_std/Sample.c")));
      assert.doesNotMatch(
        run("otool", ["-L", path.join(out, executable)]),
        /Hermes|JavaScriptCore|node/i,
      );
    }
  }
  const updated = hx.replace(
    "WebConsole.log(v_sum);",
    "WebConsole.log(v_sum + 10.0);",
  );
  assert.notEqual(updated, hx);
  writeFileSync(path.join(detached, "haxe/Sample.hx"), updated);
  const modified = path.join(work, "modified");
  cli("target", detached, "--target", "c", "--out", modified);
  assert.equal(
    Number(run(path.join(modified, "c/Sample"), [])),
    Number(original) + 10,
  );
  const backend = path.join(work, "custom.hxml");
  writeFileSync(backend, "--python custom.py\n");
  const extension = path.join(work, "extension");
  cli(
    "target",
    detached,
    "--target",
    "custom",
    "--backend",
    backend,
    "--out",
    extension,
  );
  assert.equal(
    Number(run("python3", [path.join(extension, "custom.py")])),
    Number(original) + 10,
  );
  const direct = path.join(work, "direct");
  cli("build", "tests/fixtures/modules/main.js", "--target", "custom", "--backend", backend, "--out", direct);
  assert.equal(run("python3", [path.join(direct, "custom.py")]), original);
  const rejected = path.join(work, "rejected");
  const unsupported = path.join(work, "particles.mjs");
  writeFileSync(
    unsupported,
    'import * as T from "three"; const g=new T.BufferGeometry(); new T.ShaderMaterial();',
  );
  assert.throws(() => cli("build", unsupported, "--out", rejected), /E-SUBSET/);
  assert.equal(existsSync(rejected), false);
  console.log({
    original,
    targets: nativeResults,
    changedHaxe: Number(original) + 10,
  });
} finally {
  rmSync(work, { recursive: true, force: true });
}
