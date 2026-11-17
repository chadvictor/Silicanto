// Compare the emitted programs with the browser using a mixed ESM/CommonJS/JSON application.
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
import { build } from "esbuild";
import { chromium } from "playwright";
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
const bundled = await build({
  entryPoints: [join(source, "main.mjs")],
  bundle: true,
  write: false,
  format: "iife",
});
const browser = await chromium.launch();
let expected;
try {
  const page = await browser.newPage();
  await page.route("http://fixture.test/**", (route) =>
    route.request().url().endsWith("/tile.png")
      ? route.fulfill({
          contentType: "image/png",
          body: readFileSync(join(source, "tile.png")),
        })
      : route.fulfill({
          contentType: "text/html",
          body: '<canvas id="screen" width="24" height="16"></canvas>',
        }),
  );
  await page.goto("http://fixture.test/");
  await page.evaluate(() => {
    let callbacks = [];
    window.requestAnimationFrame = (f) => callbacks.push(f);
    window.hasFrame = () => callbacks.length > 0;
    window.advance = (t) => {
      const frame = callbacks;
      callbacks = [];
      for (const f of frame) f(t);
    };
  });
  await page.addScriptTag({ path: join(source, "palette.js") });
  await page.addScriptTag({ content: bundled.outputFiles[0].text });
  await page.waitForFunction(() => window.hasFrame(), null, {
    polling: 25,
    timeout: 5000,
  });
  expected = await page.evaluate(() => {
    const canvas = document.querySelector("canvas");
    for (let n = 0; n < 4; n++) window.advance((n * 1000) / 60);
    const rgba = canvas
      .getContext("2d")
      .getImageData(0, 0, canvas.width, canvas.height).data;
    return Array.from(rgba).filter((_, i) => i % 4 !== 3);
  });
} finally {
  await browser.close();
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
    console.log(target + ": four frames, 384 pixels match Chromium exactly");
  }
} finally {
  rmSync(out, { recursive: true, force: true });
}
