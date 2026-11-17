import assert from "node:assert/strict";
import { execFile, execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, promisify } from "node:util";
import { createHash } from "node:crypto";
import { parse, serialize } from "parse5";

const root = fileURLToPath(new URL("../", import.meta.url));
const { values } = parseArgs({
  options: {
    checkout: { type: "string" },
    filter: { type: "string" },
    out: { type: "string" },
    jobs: { type: "string", default: "3" },
  },
});
const revision = "92d37954de77c1594899db93bc2e81dcff661460";
const modules = [
  "css/CSS2/normal-flow",
  "css/CSS2/floats",
  "css/CSS2/tables",
  "css/css-display",
  "css/css-flexbox",
  "css/css-grid",
  "css/css-tables",
];
const checkout = resolve(values.checkout ?? join(root, ".toolchain/css-wpt"));
const jobs = Number(values.jobs);
assert.ok(Number.isInteger(jobs) && jobs > 0 && jobs <= 8);
mkdirSync(checkout, { recursive: true });
const git = (...args) =>
  execFileSync("git", ["-C", checkout, ...args], { encoding: "utf8" }).trim();
if (!existsSync(join(checkout, ".git"))) {
  git("init", "-q");
  git(
    "remote",
    "add",
    "origin",
    "https://github.com/web-platform-tests/wpt.git",
  );
  git("sparse-checkout", "init", "--cone");
  git("sparse-checkout", "set", ...modules, "css/reference");
  git("fetch", "--filter=blob:none", "--depth=1", "origin", revision);
  git("checkout", "--detach", "FETCH_HEAD");
}
assert.equal(git("rev-parse", "HEAD"), revision);
assert.equal(git("status", "--porcelain", "--", "css"), "");
const pages = new Map();
function page(path) {
  if (pages.has(path)) return pages.get(path);
  const text = readFileSync(path, "utf8"),
    data = {},
    matches = [];
  let supported = !/\bAhem\b|@import\b|\burl\s*\(/i.test(text);
  function visit(n) {
    const attrs = Object.fromEntries(
        (n.attrs ?? []).map((a) => [a.name, a.value]),
      ),
      tag = n.tagName;
    if (
      [
        "script",
        "canvas",
        "svg",
        "iframe",
        "img",
        "object",
        "video",
        "input",
        "math",
      ].includes(tag) ||
      attrs.onload
    )
      supported = false;
    if (tag === "link") {
      const rel = attrs.rel?.toLowerCase().split(/\s+/) ?? [];
      if (rel.includes("stylesheet")) supported = false;
      if (rel.includes("match") && attrs.href) matches.push(attrs.href);
    }
    if (tag === "html" || tag === "head" || tag === "body")
      data[tag] = { attrs: n.attrs, html: tag === "html" ? "" : serialize(n) };
    for (const child of n.childNodes ?? []) visit(child);
  }
  visit(parse(text));
  const result = { matches, data, supported };
  pages.set(path, result);
  return result;
}
function* walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(path);
    else if (entry.name.endsWith(".html")) yield path;
  }
}
const cases = [];
for (const m of modules) {
  for (const path of walk(join(checkout, m))) {
    const id = relative(checkout, path);
    if (values.filter && !id.includes(values.filter)) continue;
    const actual = page(path);
    if (!actual.supported || !actual.matches.length) continue;
    const refs = actual.matches.map((href) =>
      href.startsWith("/")
        ? resolve(checkout, "." + href)
        : resolve(dirname(path), href),
    );
    if (
      refs.some(
        (p) =>
          !p.startsWith(checkout + "/") ||
          !p.endsWith(".html") ||
          !existsSync(p) ||
          !page(p).supported,
      )
    )
      continue;
    cases.push({ id, refs: refs.map((p) => relative(checkout, p)) });
  }
}
assert.ok(cases.length, "No static, self-contained reftest pairs in selection");
mkdirSync(join(root, "dist"), { recursive: true });
const work = mkdtempSync(join(root, "dist/wpt-css-")),
  log = new Array(cases.length);
const report = () => {
  if (values.out)
    writeFileSync(
      values.out,
      JSON.stringify(
        {
          revision,
          modules,
          selected: cases.length,
          results: log.filter(Boolean),
        },
        null,
        2,
      ) + "\n",
    );
};
try {
  const dest = join(work, "cpp");
  execFileSync(
    process.execPath,
    [
      "src/cli.mjs",
      "build",
      "tests/fixtures/css/index.html",
      "--frontend",
      "generic",
      "--target",
      "cpp",
      "--out",
      dest,
    ],
    { cwd: root },
  );
  const launch = promisify(execFile),
    cache = new Map();
  let done = 0,
    next = 0;
  async function capture(id, slot) {
    if (cache.has(id)) return cache.get(id);
    const task = (async () => {
      const dir = join(work, "worker-" + slot);
      mkdirSync(dir, { recursive: true });
      writeFileSync(
        join(dir, "document.json"),
        JSON.stringify(page(join(checkout, id)).data),
      );
      const file = join(dir, "page.ppm");
      await launch(
        join(dest, "cpp/Sample"),
        ["--asset-root", dir, "--capture-page", file],
        { timeout: 15000 },
      );
      const ppm = readFileSync(file),
        header = Buffer.from("P6\n800 600\n255\n");
      assert.ok(ppm.subarray(0, header.length).equals(header));
      const pixels = ppm.subarray(header.length);
      assert.equal(pixels.length, 800 * 600 * 3);
      let uniform = true;
      for (let i = 3; i < pixels.length; i++) {
        if (pixels[i] !== pixels[i % 3]) {
          uniform = false;
          break;
        }
      }
      return {
        sha256: createHash("sha256").update(pixels).digest("hex"),
        uniform,
      };
    })();
    cache.set(id, task);
    return task;
  }
  async function worker(slot) {
    while (next < cases.length) {
      const i = next++,
        c = cases[i];
      try {
        const actual = await capture(c.id, slot),
          refs = [];
        for (const id of c.refs) refs.push(await capture(id, slot));
        const match = refs.some((r) => r.sha256 === actual.sha256);
        log[i] = {
          ...c,
          actual,
          expected: refs,
          status: match
            ? actual.uniform
              ? "uniform-match"
              : "matched"
            : "different",
        };
      } catch (e) {
        log[i] = {
          ...c,
          status: "failed",
          error: String(e.message).slice(0, 300),
        };
      }
      if (++done % 50 === 0) report();
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(jobs, cases.length) }, (_, s) => worker(s)),
  );
  report();
  const counts = {};
  for (const c of log) counts[c.status] = (counts[c.status] ?? 0) + 1;
  console.log(JSON.stringify({ revision, cases: cases.length, counts }));
  if (counts.different || counts.failed) process.exitCode = 1;
} finally {
  rmSync(work, { recursive: true, force: true });
}
