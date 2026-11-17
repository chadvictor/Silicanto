import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { jdk } from "./jdk.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const { values } = parseArgs({
  options: { checkout: { type: "string" }, out: { type: "string" } },
});
const revision = "39443210f7f81db4773eb104facadfb85d05dfa4";
const checkout = resolve(
  values.checkout ?? join(root, ".toolchain/khronos-webgl"),
);
const group = "sdk/tests/conformance/ogles/GL/build";
mkdirSync(checkout, { recursive: true });
const git = (...args) =>
  execFileSync("git", ["-C", checkout, ...args], { encoding: "utf8" }).trim();
if (!existsSync(join(checkout, ".git"))) {
  git("init", "-q");
  git("remote", "add", "origin", "https://github.com/KhronosGroup/WebGL.git");
  git("sparse-checkout", "init", "--cone");
  git("sparse-checkout", "set", dirname(group));
  git("fetch", "--filter=blob:none", "--depth=1", "origin", revision);
  git("checkout", "--detach", "FETCH_HEAD");
}
assert.equal(git("rev-parse", "HEAD"), revision);
assert.equal(git("status", "--porcelain", "--", dirname(group)), "");
const folder = join(checkout, group);
const cases = readdirSync(folder)
  .filter((name) => name.endsWith(".html"))
  .sort()
  .flatMap((page) => {
    const html = readFileSync(join(folder, page), "utf8");
    const metadata = html.match(/OpenGLESTestRunner\.run\(([\s\S]*?)\);/)[1];
    return JSON.parse(metadata).tests.map((test) => {
      assert.equal(test.pattern, "build");
      const shader = (field) =>
        readFileSync(resolve(folder, test.testProgram[field]), "utf8");
      return {
        name: test.name,
        page,
        vertex: shader("vertexShader"),
        fragment: shader("fragmentShader"),
        compile: test.compstat,
        link: test.linkstat,
      };
    });
  });
assert.equal(cases.length, 178);
assert.equal(new Set(cases.map((c) => c.name)).size, 178);
mkdirSync(join(root, "dist"), { recursive: true });
const work = mkdtempSync(join(root, "dist/khronos-"));
try {
  writeFileSync(join(work, "cases.json"), JSON.stringify(cases));
  const results = {};
  for (const target of ["cpp", "java"]) {
    const dest = join(work, target);
    execFileSync(
      process.execPath,
      [
        "src/cli.mjs",
        "build",
        "tests/fixtures/khronos/index.html",
        "--frontend",
        "generic",
        "--target",
        target,
        "--out",
        dest,
      ],
      { cwd: root },
    );
    const args = ["--asset-root", work];
    const output =
      target === "cpp"
        ? execFileSync(join(dest, "cpp/Sample"), args, { encoding: "utf8" })
        : execFileSync(
            jdk("java"),
            [
              "-Djava.awt.headless=true",
              "-jar",
              join(dest, "java/Sample.jar"),
              ...args,
            ],
            { encoding: "utf8" },
          );
    const result = JSON.parse(output.trim().split("\n").at(-1));
    assert.deepEqual(
      result.map((c) => c.name),
      cases.map((c) => c.name),
    );
    const failures = result.filter((c) => !c.passed);
    results[target] = result;
    console.log(
      target +
        ": " +
        (cases.length - failures.length) +
        "/" +
        cases.length +
        " Khronos OGLES WebGL 1 shader build cases passed",
    );
    for (const c of failures) console.error(c);
    if (failures.length) process.exitCode = 1;
  }
  if (values.out)
    writeFileSync(
      values.out,
      JSON.stringify({ revision, group, results }, null, 2) + "\n",
    );
} finally {
  rmSync(work, { recursive: true, force: true });
}
