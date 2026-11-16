import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { createHash } from "node:crypto";
import {
  readFileSync,
  readdirSync,
  writeFileSync,
  mkdirSync,
  mkdtempSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { chromium } from "playwright";

const root = path.resolve(fileURLToPath(new URL("../", import.meta.url)));
const cli = path.join(root, "src/cli.mjs");
mkdirSync(path.join(root, "dist"), { recursive: true });
const build = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(mkdtempSync(path.join(root, "dist/nacar-test-")), "native");
if (!process.argv[2])
  execFileSync(
    process.execPath,
    [
      cli,
      "build",
      path.join(root, "examples/nacar/main.js"),
      "--out",
      build,
      "--name",
      "Nacar",
    ],
    { stdio: "inherit" },
  );

const manifest = JSON.parse(
  readFileSync(path.join(build, "manifest.json"), "utf8"),
);
const haxe = manifest.pipeline === "js-haxe";
assert.ok(haxe || manifest.pipeline === "static-hermes-c-aot");
const runtime = path.join(build, "Nacar.app");
const native = path.join(runtime, "Contents/MacOS/Nacar");
for (const file of ["main.js", "world.mjs", "probe.mjs"]) {
  const sha = createHash("sha256")
    .update(readFileSync(path.join(root, "examples/nacar", file)))
    .digest("hex");
  assert.ok(
    manifest.inputs.some(
      (entry) => entry.file === file && entry.sha256 === sha,
    ),
    file,
  );
}
assert.ok(!manifest.inputs.some((entry) => entry.file.endsWith("world.json")));
const shipped = readdirSync(runtime, { recursive: true });
assert.ok(
  !shipped.some((file) => /\.(m?js|hbc|vertices\.z|probe)$/.test(file)),
);
if (haxe) {
  assert.deepEqual(manifest.sceneAssets, {});
  assert.equal(manifest.target, "c");
  const hx = readFileSync(path.join(build, manifest.entry), "utf8");
  for (const name of ["twilightProbe", "fbm", "cluster", "grid"])
    assert.ok(hx.includes("function v_" + name + "_"));
  assert.match(
    execFileSync("file", [native], { encoding: "utf8" }),
    /Mach-O.*arm64/,
  );
  assert.match(
    execFileSync("otool", ["-L", native], { encoding: "utf8" }),
    /gpu_metal/,
  );
} else {
  const symbols = execFileSync("nm", [native], { encoding: "utf8" });
  for (const name of [
    "_twilightProbe",
    "_fbm",
    "_WebGLRenderer",
    "_sh_export_app",
  ])
    assert.ok(symbols.includes(name));
}
const qa = path.join(build, "comparison");
mkdirSync(qa, { recursive: true });
const translated = path.join(mkdtempSync(path.join(qa, "targets-")), "web");
if (haxe)
  execFileSync(
    process.execPath,
    [cli, "target", build, "--target", "js", "--out", translated],
    { stdio: "inherit" },
  );

const browser = await chromium.launch({
  args: [
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
  ],
});
const report = {
  pipeline: manifest.pipeline,
  backend: "Metal",
  architecture: process.arch,
  three: "r180",
  browser: browser.version(),
  samples: [],
};
const server = createServer((request, response) => {
  const pathname = new URL(request.url, "http://localhost").pathname;
  const assetRoot = pathname.startsWith("/translated/")
    ? path.join(translated, "js")
    : root;
  const file = path.resolve(
    assetRoot,
    "." + (pathname.startsWith("/translated/") ? pathname.slice(11) : pathname),
  );
  if (
    !file.startsWith(assetRoot + path.sep) ||
    ![".mjs", ".js", ".json", ".html"].includes(path.extname(file))
  ) {
    response.writeHead(404).end();
    return;
  }
  response.setHeader(
    "Content-Type",
    {
      ".html": "text/html",
      ".js": "text/javascript",
      ".mjs": "text/javascript",
      ".json": "application/json",
    }[path.extname(file)],
  );
  const stream = createReadStream(file);
  stream.on("error", () => response.writeHead(404).end());
  stream.pipe(response);
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
try {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    deviceScaleFactor: 1,
  });
  const errors = [];
  await context.addInitScript(() => {
    const getContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (kind, options) {
      return getContext.call(
        this,
        kind,
        kind === "webgl2"
          ? { ...options, preserveDrawingBuffer: true }
          : options,
      );
    };
    let next = 0;
    window.threecFrames = new Map();
    window.requestAnimationFrame = (cb) => {
      window.threecFrames.set(++next, cb);
      return next;
    };
    window.cancelAnimationFrame = (id) => window.threecFrames.delete(id);
  });
  const base = "http://127.0.0.1:" + server.address().port;
  async function load(relative) {
    const page = await context.newPage();
    page.on("pageerror", (e) => errors.push(String(e)));
    const res = await page.goto(base + relative, { timeout: 60000 });
    assert.ok(res.ok(), relative + " HTTP " + res.status());
    assert.ok(
      await page.evaluate(() => window.threecFrames.size > 0),
      "Missing frame callback in " + relative + " " + errors.join(" "),
    );
    assert.deepEqual(errors, []);
    return page;
  }
  const page = await load("/examples/nacar/index.html");
  const compiled = haxe ? await load("/translated/index.html") : null;
  for (const time of [0, 14000, 35000]) {
    const ppm = path.join(qa, "metal-" + time + ".ppm");
    execFileSync(native, ["--time-ms", String(time), "--capture", ppm], {
      timeout: 45000,
    });
    execFileSync("sips", [
      "-s",
      "format",
      "png",
      ppm,
      "--out",
      path.join(qa, "metal-" + time + ".png"),
    ]);
    function draw(t) {
      const callbacks = [...window.threecFrames.values()];
      window.threecFrames.clear();
      callbacks.forEach((cb) => cb(t));
      return document
        .querySelector("canvas")
        .toDataURL("image/png")
        .split(",")[1];
    }
    const png = await page.evaluate(draw, time);
    writeFileSync(
      path.join(qa, "web-" + time + ".png"),
      Buffer.from(png, "base64"),
    );
    function pixels() {
      const gl = document.querySelector("canvas").getContext("webgl2"),
        w = gl.drawingBufferWidth,
        h = gl.drawingBufferHeight;
      const rgba = new Uint8Array(w * h * 4),
        rgb = new Uint8Array(w * h * 3);
      gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, rgba);
      for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++) {
          const i = ((h - 1 - y) * w + x) * 4,
            j = (y * w + x) * 3;
          rgb[j] = rgba[i];
          rgb[j + 1] = rgba[i + 1];
          rgb[j + 2] = rgba[i + 2];
        }
      let bytes = "";
      for (let i = 0; i < rgb.length; i += 16384)
        bytes += String.fromCharCode(...rgb.subarray(i, i + 16384));
      return btoa(bytes);
    }
    const reference = Buffer.from(await page.evaluate(pixels), "base64"),
      capture = readFileSync(ppm),
      header = Buffer.from("P6\n1280 720\n255\n");
    assert.ok(capture.subarray(0, header.length).equals(header));
    const actual = capture.subarray(header.length);
    assert.equal(actual.length, reference.length);
    let error = 0,
      within = 0;
    for (let i = 0; i < actual.length; i += 3) {
      const r = Math.abs(reference[i] - actual[i]),
        g = Math.abs(reference[i + 1] - actual[i + 1]),
        b = Math.abs(reference[i + 2] - actual[i + 2]);
      error += r + g + b;
      if (Math.max(r, g, b) <= 8) within++;
    }
    const sample = {
      timeMs: time,
      meanChannelError: error / actual.length,
      within8: within / (actual.length / 3),
      sha256: createHash("sha256").update(actual).digest("hex"),
    };
    if (compiled) {
      await compiled.evaluate(draw, time);
      const rgb = Buffer.from(await compiled.evaluate(pixels), "base64");
      assert.equal(rgb.length, reference.length);
      let webError = 0;
      for (let i = 0; i < rgb.length; i++)
        webError += Math.abs(rgb[i] - reference[i]);
      sample.haxeWebMeanError = webError / rgb.length;
      assert.ok(
        sample.haxeWebMeanError < 0.25,
        "Regenerated WebGL diverged: " + sample.haxeWebMeanError,
      );
    }
    report.samples.push(sample);
    console.log(sample);
    assert.ok(
      sample.meanChannelError < 4 && sample.within8 > 0.92,
      "WebGL and Metal diverged",
    );
  }
  assert.equal(new Set(report.samples.map((s) => s.sha256)).size, 3);
  assert.deepEqual(errors, []);
} finally {
  writeFileSync(
    path.join(qa, "report.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
  server.close();
  await browser.close();
}
