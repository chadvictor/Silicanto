import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { extname, resolve, sep } from "node:path";
import { chromium } from "playwright";

let shared;
export async function closeReferenceBrowser() {
  if (shared) {
    const b = await shared;
    shared = null;
    await b.close();
  }
}
export async function referenceFrame({
  reuse = false,
  html,
  rootFile,
  pub,
  checkout,
  rev,
  engine,
  frames,
}) {
  const launch = () =>
    chromium.launch({
      args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
    });
  const browser = await (reuse ? (shared ??= launch()) : launch());
  let page;
  try {
    page = await browser.newPage({
      viewport: { width: 800, height: 600 },
      deviceScaleFactor: 1,
    });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.route("**/*", async (route) => {
      const url = new URL(route.request().url());
      if (url.origin !== "http://example.test") {
        errors.push("External resource: " + url.href);
        return route.abort();
      }
      const path = decodeURIComponent(url.pathname).slice(1);
      if (!path) return route.fulfill({ body: html, contentType: "text/html" });
      const file =
        path === "engine.js"
          ? engine
          : path === "gallery-entry.mjs" && rootFile
            ? rootFile
            : resolve(pub, path);
      if (file !== engine && !file.startsWith(pub + sep)) return route.abort();
      const mime = {
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".svg": "image/svg+xml",
        ".mp3": "audio/mpeg",
        ".ogg": "audio/ogg",
        ".xml": "text/xml",
      };
      try {
        const body = existsSync(file)
          ? readFileSync(file)
          : execFileSync(
              "git",
              ["-C", checkout, "show", rev + ":public/" + path],
              { maxBuffer: 32 << 20, stdio: ["ignore", "pipe", "pipe"] },
            );
        return await route.fulfill({
          body,
          contentType: mime[extname(file)] ?? "application/octet-stream",
        });
      } catch {
        errors.push("Missing asset: " + path);
        return route.abort();
      }
    });
    await page.addInitScript(() => {
      let next = 0;
      const frames = new Map();
      window.requestAnimationFrame = (f) => {
        frames.set(++next, f);
        return next;
      };
      window.cancelAnimationFrame = (id) => frames.delete(id);
      window.advanceFrame = (t) => {
        const batch = [...frames];
        for (const [id, f] of batch) if (frames.delete(id)) f(t);
      };
      const original = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (type, opts) {
        return original.call(
          this,
          type,
          /webgl/.test(type) ? { ...opts, preserveDrawingBuffer: true } : opts,
        );
      };
    });
    await page.goto("http://example.test/", {
      waitUntil: "networkidle",
      timeout: 30000,
    });
    for (let i = 0; i < frames; i++) {
      await page.evaluate((t) => window.advanceFrame(t), (i * 1000) / 60);
      await page.waitForLoadState("networkidle");
    }
    if (errors.length) throw Error(errors.join("\n"));
    return await page.evaluate(() => {
      const src = document.querySelector("canvas");
      if (!src) throw Error("No reference canvas");
      const canvas = document.createElement("canvas");
      canvas.width = src.width;
      canvas.height = src.height;
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "black";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(src, 0, 0);
      const bytes = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let data = "";
      for (let i = 0; i < bytes.length; i += 4)
        data += String.fromCharCode(bytes[i], bytes[i + 1], bytes[i + 2]);
      return { width: src.width, height: src.height, pixels: btoa(data) };
    });
  } finally {
    if (reuse) await page?.close();
    else await browser.close();
  }
}
export function compareFrame(ppm, ref) {
  const header = Buffer.from(`P6\n${ref.width} ${ref.height}\n255\n`),
    expected = Buffer.from(ref.pixels, "base64");
  if (
    !ppm.subarray(0, header.length).equals(header) ||
    ppm.length !== header.length + expected.length ||
    !expected.length
  )
    throw Error("Frame dimensions differ");
  const actual = ppm.subarray(header.length);
  let error = 0,
    matched = 0,
    changed = false;
  const colors = new Map(),
    rgb = (buf, i) => (buf[i] << 16) | (buf[i + 1] << 8) | buf[i + 2];
  for (let i = 0; i < expected.length; i += 3) {
    const c = rgb(expected, i);
    colors.set(c, (colors.get(c) ?? 0) + 1);
  }
  let background = -1,
    most = 0;
  for (const [color, n] of colors)
    if (n > most) {
      background = color;
      most = n;
    }
  let foreground = 0,
    foregroundMatched = 0;
  for (let i = 0; i < actual.length; i += 3) {
    const d = [0, 1, 2].map((k) => Math.abs(actual[i + k] - expected[i + k]));
    if (i && [0, 1, 2].some((k) => expected[i + k] !== expected[k]))
      changed = true;
    const ok = Math.max(...d) <= 8;
    if (rgb(expected, i) !== background) {
      foreground++;
      if (ok && rgb(actual, i) !== background) foregroundMatched++;
    }
    error += d[0] + d[1] + d[2];
    if (ok) matched++;
  }
  const mean = error / actual.length,
    within8 = matched / (actual.length / 3);
  if (!changed)
    throw Error(
      "Uniform reference frame needs a sample-specific behavioral assertion",
    );
  if (mean >= 4 || within8 <= 0.92 || foregroundMatched / foreground <= 0.92)
    throw Error(
      `Frame mismatch: mean ${mean}, within8 ${within8}, foreground ${foregroundMatched}/${foreground}`,
    );
  return { mean, within8, foreground, foregroundMatched };
}
