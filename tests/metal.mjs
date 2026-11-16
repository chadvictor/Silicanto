import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const aot = process.argv.includes("--aot");
const hlc = process.argv.includes("--haxe-c");
const root = fileURLToPath(new URL("../", import.meta.url));
process.chdir(root);
const run = (exe, args, options = {}) =>
  execFileSync(exe, args, { cwd: root, encoding: "utf8", ...options });
mkdirSync("dist", { recursive: true });
const output = mkdtempSync(path.resolve("dist/verification-"));
run("node", ["scripts/samples.mjs"]);
const browser = await chromium.launch({
  args: [
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
  ],
});
const report = {
  browser: browser.version(),
  three: "0.180.0",
  macOS: run("sw_vers", ["-productVersion"]).trim(),
  arch: process.arch,
  graphics: "Metal",
  gpu: JSON.parse(
    run("system_profiler", ["SPDisplaysDataType", "-json"]),
  ).SPDisplaysDataType.map((g) => g.sppci_model),
  pipeline: hlc ? "js-haxe-c-and-js" : aot ? "static-hermes-c-aot" : "haxe-cpp",
  captures: [],
};
try {
  for (const [sample, frames] of [
    ["fundamentals", [1]],
    ["fundamentals-with-animation", [1, 31, 61]],
  ]) {
    const input = "samples/r180/" + sample + ".html",
      project = path.join(output, sample);
    let app, graphics;
    if (hlc) {
      const cli = (...args) => run(process.execPath, ["src/cli.mjs", ...args]);
      const portable = project + "-haxe";
      cli("emit", input, "--out", portable);
      cli("target", portable, "--target", "c", "--out", project);
      cli("target", portable, "--target", "js", "--out", project + "-js");
      assert.equal(
        readFileSync(path.join(project, "haxe/Sample.hx"), "utf8"),
        readFileSync(path.join(project + "-js", "haxe/Sample.hx"), "utf8"),
      );
      app = path.join(project, "c/Sample");
      graphics = path.join(project, "c/lib/gpu_metal.hdll");
    } else if (aot) {
      run("node", ["scripts/experimental-hermes.mjs", input, project]);
      app = path.join(project, "Application.app/Contents/MacOS/Application");
      graphics = path.join(
        project,
        "Application.app/Contents/Frameworks/libGLESv2.dylib",
      );
    } else {
      run("node", [
        "src/cli.mjs",
        "emit",
        input,
        "--target",
        "cpp",
        "--out",
        project,
      ]);
      run("bash", [
        "-c",
        'source scripts/tool-env.sh && bash "$1/build.sh"',
        "threec",
        project,
      ]);
      app = graphics = path.join(project, "cpp/Sample");
    }
    assert.match(run("file", [app]), /Mach-O 64-bit executable arm64/);
    assert.match(run("otool", ["-L", graphics]), /Metal.framework/);
    run(app, ["--frames", "3"], { timeout: 20000 });
    for (const count of frames) {
      const ppm = path.join(project, "frame-" + count + ".ppm");
      run(app, ["--frames", String(count), "--capture", ppm], {
        timeout: 20000,
      });
      const native = readFileSync(ppm);
      const header = Buffer.from("P6\n300 150\n255\n");
      assert.ok(native.subarray(0, header.length).equals(header));
      const page = await browser.newPage({
        viewport: { width: 640, height: 480 },
        deviceScaleFactor: 1,
      });
      try {
        await page.addInitScript(() => {
          const original = HTMLCanvasElement.prototype.getContext;
          HTMLCanvasElement.prototype.getContext = function (type, attrs) {
            return original.call(
              this,
              type,
              type === "webgl2"
                ? { ...attrs, preserveDrawingBuffer: true }
                : attrs,
            );
          };
          let next = 0;
          window.queue = new Map();
          window.requestAnimationFrame = (f) => {
            window.queue.set(++next, f);
            return next;
          };
          window.cancelAnimationFrame = (id) => window.queue.delete(id);
        });
        await page.route("http://reference.test/**", (route) => {
          const url = new URL(route.request().url()),
            name = path.basename(url.pathname);
          if (url.pathname === "/manual/examples/" + sample + ".html")
            return route.fulfill({ path: input, contentType: "text/html" });
          if (
            ["/build/three.module.js", "/build/three.core.js"].includes(
              url.pathname,
            )
          )
            return route.fulfill({
              path: path.join("node_modules/three/build", name),
              contentType: "text/javascript",
            });
          return route.fulfill({ status: 404, body: "" });
        });
        await page.goto(
          "http://reference.test/manual/examples/" + sample + ".html",
        );
        const pixels = async () =>
          Buffer.from(
            await page.evaluate((count) => {
              for (let i = 0; i < count; i++) {
                const callbacks = [...window.queue.values()];
                window.queue.clear();
                callbacks.forEach((cb) => cb((i * 1000) / 60));
              }
              const gl = document.querySelector("canvas").getContext("webgl2");
              const w = gl.drawingBufferWidth,
                h = gl.drawingBufferHeight;
              const rgba = new Uint8Array(w * h * 4),
                rgb = new Uint8Array(w * h * 3);
              gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, rgba);
              for (let y = 0; y < h; y++)
                for (let x = 0; x < w; x++) {
                  const a = ((h - 1 - y) * w + x) * 4;
                  rgb.set(rgba.subarray(a, a + 3), (y * w + x) * 3);
                }
              return Array.from(rgb);
            }, count),
          );
        const reference = await pixels();
        if (hlc) {
          await page.route("http://compiled.test/**", (route) => {
            const file = path.basename(new URL(route.request().url()).pathname);
            if (
              ![
                "index.html",
                "three.module.js",
                "three.core.js",
                "program.js",
              ].includes(file)
            )
              return route.fulfill({ status: 404, body: "" });
            return route.fulfill({
              path: path.join(project + "-js/js", file),
              contentType: file.endsWith(".js")
                ? "text/javascript"
                : "text/html",
            });
          });
          await page.goto("http://compiled.test/index.html");
          const browserTarget = await pixels();
          writeFileSync(
            path.join(project, "haxe-web-" + count + ".ppm"),
            Buffer.concat([header, browserTarget]),
          );
          writeFileSync(
            path.join(project, "web-" + count + ".ppm"),
            Buffer.concat([header, reference]),
          );
          assert.ok(
            browserTarget.equals(reference),
            "Haxe → JavaScript framebuffer differs from original: " +
              sample +
              " frame " +
              count,
          );
        }
        writeFileSync(
          path.join(project, "web-" + count + ".ppm"),
          Buffer.concat([header, reference]),
        );
        const actual = native.subarray(header.length);
        assert.equal(actual.length, reference.length);
        let union = 0,
          intersection = 0,
          interior = 0,
          correct = 0;
        for (let i = 0; i < reference.length; i += 3) {
          const a = actual[i + 1] > 84,
            b = reference[i + 1] > 84;
          if (a || b) union++;
          if (a && b) intersection++;
          if (reference[i + 1] === 170) {
            const x = (i / 3) % 300,
              y = Math.floor(i / 900);
            if (
              x > 0 &&
              x < 299 &&
              y > 0 &&
              y < 149 &&
              [-903, -900, -897, -3, 3, 897, 900, 903].every(
                (d) => reference[i + d + 1] === 170,
              )
            ) {
              interior++;
              if (
                [0, 1, 2].every(
                  (d) => Math.abs(reference[i + d] - actual[i + d]) <= 3,
                )
              )
                correct++;
            }
          }
        }
        const iou = intersection / union,
          color = correct / interior;
        report.captures.push({ sample, frame: count, iou, color });
        console.log(sample, count, { iou, color });
        assert.ok(
          interior > 100 && iou >= 0.99 && color >= 0.99,
          "Pixel comparison failed; images in " + project,
        );
      } finally {
        await page.close();
      }
    }
  }
} finally {
  await browser.close();
  writeFileSync(
    path.join(output, "report.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
  console.log(output);
}
