import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  readdirSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildNative } from "../src/native.mjs";

const tmp = mkdtempSync(join(tmpdir(), "threec-test-"));
const source = readFileSync(
  new URL("fixtures/triangle.js", import.meta.url),
  "utf8",
);
try {
  for (const [channel, expected] of [
    ["green", [0, 255, 0]],
    ["red", [255, 0, 0]],
  ]) {
    const dir = join(tmp, channel),
      out = join(dir, "build");
    mkdirSync(dir);
    // A second input with a different fragment program must change the native pixels.
    writeFileSync(
      join(dir, "fragment.js"),
      'export default "' +
        (channel === "green" ? "0.,1.,0." : "1.,0.,0.") +
        '";',
    );
    writeFileSync(
      join(dir, "draw.js"),
      'import color from "./fragment.js";\n' +
        source.replace("vec4(0.,1.,0.,1.);", 'vec4(" + color + ",1.);'),
    );
    await buildNative(join(dir, "draw.js"), out);
    const manifest = JSON.parse(readFileSync(join(out, "manifest.json")));
    assert.ok(manifest.inputs.some((x) => x.file === "fragment.js"));
    const bundle = join(out, "Application.app"),
      exe = join(out, manifest.executable);
    assert.match(
      execFileSync("file", [exe], { encoding: "utf8" }),
      /Mach-O 64-bit executable arm64/,
    );
    assert.match(
      execFileSync("nm", [exe], { encoding: "utf8" }),
      /_sh_export_app/,
    );
    assert.ok(
      readFileSync(join(out, "app.c"), "utf8").includes("/*shaderSource*/"),
    );
    assert.ok(
      !readdirSync(bundle, { recursive: true }).some((s) =>
        /\.(?:m?js|hbc)$/.test(s),
      ),
    );
    rmSync(join(dir, "draw.js"));
    rmSync(join(dir, "fragment.js"));
    const ppm = join(dir, "out.ppm");
    execFileSync(exe, ["--capture", ppm], { timeout: 15000 });
    const data = readFileSync(ppm),
      header = Buffer.from("P6\n80 40\n255\n");
    assert.ok(data.subarray(0, header.length).equals(header));
    const rgb = data.subarray(header.length);
    assert.equal(rgb.length, 80 * 40 * 3);
    assert.deepEqual([...rgb.subarray(0, 3)], [0, 0, 0]);
    const center = (20 * 80 + 40) * 3;
    assert.deepEqual([...rgb.subarray(center, center + 3)], expected);
  }
  console.log(
    "Two native builds reproduced the colors of two different input shaders.",
  );
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
