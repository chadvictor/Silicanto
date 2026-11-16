import assert from "node:assert/strict";
import { test } from "node:test";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { registry, selectPayload } from "../src/targets.mjs";

test("resolve graphics, portable logic and unsupported platform combinations before building", async () => {
  const routes = await registry();
  const select = (options) =>
    selectPayload(routes, { target: "java", mode: "emit", ...options });
  assert.equal(select({ profile: "scene" }).platform, "macos-arm64");
  assert.equal(select({ profile: "logic" }).platform, "jvm");
  assert.equal(
    select({ profile: "logic", platform: "windows-x64" }).platform,
    "jvm",
  );
  for (const options of [
    { profile: "packed-scene" },
    { profile: "scene", platform: "jvm" },
    { profile: "scene", graphics: "opengl" },
  ])
    assert.throws(() => select(options), /E-TARGET/);
});

test("load a project-local payload, retarget edited Haxe without JS, discard failed output", () => {
  const work = mkdtempSync(join(tmpdir(), "silicanto-payload-"));
  const cli = (...args) =>
    execFileSync(process.execPath, ["src/cli.mjs", ...args], { stdio: "pipe" });
  try {
    const js = join(work, "main.js"),
      project = join(work, "project"),
      plugin = join(work, "payload.mjs");
    const out = join(work, "out"),
      failure = join(work, "failure");
    writeFileSync(js, "console.log(17);");
    cli("emit", js, "--out", project);
    rmSync(js);
    const hx = readFileSync(join(project, "haxe/Sample.hx"), "utf8").replace(
      "17.0",
      "23.0",
    );
    writeFileSync(join(project, "haxe/Sample.hx"), hx);
    writeFileSync(
      plugin,
      `
      import {readFileSync,writeFileSync} from "node:fs";
      import {join} from "node:path";
      export default { apiVersion:1, target:"sample", platform:"desktop", graphics:"none", capabilities:["logic"],
        async build({projectDir, manifest, mode, name}) {
          const source=readFileSync(join(projectDir,manifest.entry),"utf8");
          writeFileSync(join(projectDir,"result.json"),JSON.stringify({source,mode,name}));
          if(name === "Fail") throw Error("intentional failure");
        }
      };`,
    );
    const target = (...args) =>
      cli(
        "target",
        project,
        "--payload",
        plugin,
        "--target",
        "sample",
        "--platform",
        "desktop",
        ...args,
      );
    target("--out", out, "--name", "Hello");
    assert.deepEqual(JSON.parse(readFileSync(join(out, "result.json"))), {
      source: hx,
      mode: "build",
      name: "Hello",
    });
    assert.throws(
      () => target("--out", failure, "--name", "Fail"),
      /intentional failure/,
    );
    assert.equal(existsSync(failure), false);
    assert.throws(
      () => target("--out", failure, "--graphics", "vulkan"),
      /E-TARGET/,
    );
    assert.equal(existsSync(failure), false);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
