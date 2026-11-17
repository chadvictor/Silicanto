import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { jdk } from "./jdk.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const source = join(root, "tests/fixtures/webgl");
mkdirSync(join(root, "dist"), { recursive: true });
const out = mkdtempSync(join(root, "dist/webgl-test-"));
const expected = [];
// The triangle occupies x/48 + (31-y)/32 < 1, evaluated at pixel centers.
for (let y = 0; y < 32; y++)
  for (let x = 0; x < 48; x++) {
    const red = (x + 0.5) / 48 + (31.5 - y) / 32 < 1;
    expected.push(red ? 255 : 0, 0, red ? 0 : 255);
  }
try {
  for (const target of ["cpp", "java"]) {
    const dir = join(out, target),
      ppm = join(out, target + ".ppm");
    execFileSync(
      process.execPath,
      [
        "src/cli.mjs",
        "build",
        join(source, "index.html"),
        "--frontend",
        "generic",
        "--target",
        target,
        "--out",
        dir,
      ],
      { cwd: root, timeout: 300000 },
    );
    const args = ["--capture", ppm];
    if (target === "java")
      execFileSync(jdk("java"), [
        "-Djava.awt.headless=true",
        "-jar",
        join(dir, "java/Sample.jar"),
        ...args,
      ]);
    else execFileSync(join(dir, "cpp/Sample"), args);
    assert.deepEqual(
      readFileSync(ppm),
      Buffer.concat([Buffer.from("P6\n48 32\n255\n"), Buffer.from(expected)]),
    );
    console.log(
      target +
        ": linked GLSL program, readPixels, framebuffer and analytic RGB match; text and ECMAScript assertions passed",
    );
  }
} finally {
  rmSync(out, { recursive: true, force: true });
}
