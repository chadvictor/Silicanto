// Check a mixed ESM/CommonJS/JSON application against its specified fourth frame.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { jdk } from "./jdk.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const source = join(root, "tests/fixtures/general");
mkdirSync(join(root, "dist"), { recursive: true });
const out = mkdtempSync(join(root, "dist/generic-e2e-"));
function run(exe, args, opts = {}) {
  return execFileSync(exe, args, {
    cwd: root,
    encoding: "utf8",
    timeout: 300000,
    ...opts,
  });
}
const expected = [];
const tile = [
  [255, 0, 210],
  [0, 80, 250],
  [90, 40, 16],
  [255, 220, 30],
];
for (let y = 0; y < 16; y++)
  for (let x = 0; x < 24; x++) {
    const sprite = x >= 1 && x <= 2 && y >= 1 && y <= 2;
    expected.push(
      ...(sprite
        ? tile[(y - 1) * 2 + x - 1]
        : x >= 4 && x < 9 && y >= 3 && y < 9
          ? [71, 168, 110]
          : [35, 43, 57]),
    );
  }
assert.deepEqual(expected.slice(3 * (24 + 1), 3 * (24 + 1) + 3), [255, 0, 210]);
const native = Buffer.concat([
  Buffer.from("P6\n24 16\n255\n"),
  Buffer.from(expected),
]);
try {
  const hx = join(out, "source");
  run(process.execPath, [
    "src/cli.mjs",
    "emit",
    join(source, "index.html"),
    "--frontend",
    "generic",
    "--out",
    hx,
  ]);
  const manifest = JSON.parse(readFileSync(join(hx, "manifest.json")));
  assert.equal(manifest.frontend, "generic");
  assert.equal(manifest.graphicsHost, false);
  assert.deepEqual(manifest.moduleGraph.scripts, ["palette.js", "main.mjs"]);
  assert.ok(manifest.moduleGraph.modules.some((m) => m.id === "settings.json"));
  for (const target of ["java", "neko", "cpp", "c"]) {
    const dest = join(out, target),
      ppm = join(out, target + ".ppm");
    run(process.execPath, [
      "src/cli.mjs",
      "target",
      hx,
      "--target",
      target,
      "--out",
      dest,
    ]);
    const args = ["--frames", "4", "--capture", ppm, "--asset-root", source];
    if (target === "java")
      run(jdk("java"), ["-jar", join(dest, "java/Sample.jar"), ...args]);
    else if (target === "neko")
      run("bash", [
        "-c",
        'source scripts/tool-env.sh && exec neko "$@"',
        "_",
        join(dest, "neko/Sample.n"),
        ...args,
      ]);
    else run(join(dest, target, "Sample"), args);
    assert.deepEqual(readFileSync(ppm), native, target);
    console.log(
      target +
        ": four frames, 384 pixels match the expected RGBA drawing exactly",
    );
  }
} finally {
  rmSync(out, { recursive: true, force: true });
}
