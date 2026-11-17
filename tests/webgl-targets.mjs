import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { jdk } from "./jdk.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const source = join(root, "tests/fixtures/webgl");
mkdirSync(join(root, "dist"), { recursive: true });
const out = mkdtempSync(join(root, "dist/webgl-test-"));
const browser = await chromium.launch({
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
});
try {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("about:blank");
  await page.setContent('<canvas id="view" width="48" height="32"></canvas>');
  await page.addScriptTag({ path: join(source, "draw.js") });
  await page.addScriptTag({ path: join(source, "resources.js") });
  assert.deepEqual(errors, []);
  const expected = await page.evaluate(() => {
    const c = document.querySelector("canvas"),
      gl = c.getContext("webgl"),
      rgba = new Uint8Array(c.width * c.height * 4);
    gl.readPixels(0, 0, c.width, c.height, gl.RGBA, gl.UNSIGNED_BYTE, rgba);
    const rgb = [];
    for (let y = c.height - 1; y >= 0; y--)
      for (let x = 0; x < c.width; x++) {
        const i = (y * c.width + x) * 4;
        rgb.push(rgba[i], rgba[i + 1], rgba[i + 2]);
      }
    return rgb;
  });
  assert.equal(new Set(expected).size, 2);
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
        ": linked GLSL program, readPixels, framebuffer and browser RGB match; text and ECMAScript assertions passed",
    );
  }
} finally {
  await browser.close();
  rmSync(out, { recursive: true, force: true });
}
