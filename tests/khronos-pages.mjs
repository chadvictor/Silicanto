import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { parseArgs, stripVTControlCharacters } from "node:util";
import { resolveGraph } from "../src/frontend/graph.mjs";
import { emitModules } from "../src/frontend/modules.mjs";
import { revision, root, sourceTree } from "./khronos-source.mjs";
import { jdk } from "./jdk.mjs";

const { values } = parseArgs({
  options: {
    checkout: { type: "string" },
    out: { type: "string" },
    filter: { type: "string" },
    version: { type: "string", default: "1.0.4" },
    target: { type: "string", default: "cpp" },
    "frontend-only": { type: "boolean" },
    "build-timeout-ms": { type: "string", default: "600000" },
  },
});
assert.ok(["1.0.4", "2.0.1"].includes(values.version));
assert.ok(["cpp", "java"].includes(values.target));
const tests = dirname(sourceTree(values.checkout)),
  checkout = resolve(tests, "../..");
const git = (...args) =>
  execFileSync("git", ["-C", checkout, ...args], { encoding: "utf8" }).trim();
// The list runner needs the complete upstream test tree, including shared
// libraries outside the conformance directories of a shader-only checkout.
const sparse = git("config", "--type=bool", "--default", "false", "--get", "core.sparseCheckout");
if (sparse === "true") {
  const paths = git("sparse-checkout", "list").split("\n");
  if (!paths.includes("sdk/tests") && !paths.includes("sdk"))
    git("sparse-checkout", "add", "sdk/tests");
}
assert.equal(git("rev-parse", "HEAD"), revision);
assert.equal(git("status", "--porcelain", "--", "sdk/tests"), "");
const version = (v) => v.split(".").reduce((a, n) => a * 100 + Number(n), 0);
const selected = [];
function list(file, minimum = "1.0.0", maximum = "9.9.9") {
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const row = line.trim();
    if (!row || /^(?:#|;|\/\/)/.test(row)) continue;
    const args = row.split(/\s+/);
    let lo = minimum,
      hi = maximum;
    while (args[0]?.startsWith("--")) {
      const opt = args.shift();
      if (opt === "--min-version") lo = args.shift();
      else if (opt === "--max-version") hi = args.shift();
      else if (opt !== "--slow") throw Error("Unknown list option " + opt);
    }
    const path = resolve(dirname(file), args.join(" "));
    if (path.endsWith(".txt")) list(path, lo, hi);
    else if (
      version(lo) <= version(values.version) &&
      version(values.version) <= version(hi)
    ) {
      const id = relative(tests, path);
      if (!values.filter || id.includes(values.filter)) selected.push(id);
    }
  }
}
list(join(tests, "00_test_list.txt"));
assert.ok(selected.length);
const compiler = execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
  encoding: "utf8",
}).trim();
const buildTimeout = Number(values["build-timeout-ms"]);
assert.ok(Number.isSafeInteger(buildTimeout) && buildTimeout > 0);
const modifiedCompilerOrSuite =
  execFileSync(
    "git",
    [
      "-C",
      root,
      "status",
      "--porcelain",
      "--",
      "src",
      "runtime",
      "scripts",
      "payloads",
      "package.json",
      "package-lock.json",
      "tests/khronos-pages.mjs",
      "tests/khronos-source.mjs",
    ],
    { encoding: "utf8" },
  ).trim().length !== 0;
const report = {
  compiler,
  modifiedCompilerOrSuite,
  revision,
  version: values.version,
  target: values.target,
  selected: selected.length,
  cases: [],
};
function save() {
  if (!values.out) return;
  writeFileSync(values.out + ".partial", JSON.stringify(report) + "\n");
  renameSync(values.out + ".partial", values.out);
}
function run(cmd, args, timeout = 120000) {
  return execFileSync(cmd, args, {
    cwd: root,
    encoding: "utf8",
    timeout,
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 8 << 20,
  });
}
function nativePage(id, work) {
  // Give the original document its relative URLs in a private directory tree.
  const [name, query] = id.split("?");
  const segments = name.split("/");
  let directory = tests,
    mirror = join(work, "tests");
  mkdirSync(mirror);
  for (const [i, segment] of segments.entries()) {
    for (const sibling of readdirSync(directory)) {
      if (sibling !== segment)
        symlinkSync(join(directory, sibling), join(mirror, sibling));
    }
    if (i === segments.length - 1) break;
    directory = join(directory, segment);
    mirror = join(mirror, segment);
    mkdirSync(mirror);
  }
  const search =
    "?" + (query ? query + "&" : "") + "webglVersion=" + values.version[0];
  const location = {
    pathname: "/" + name,
    search,
    href: "http://localhost/" + name + search,
  };
  const reporter = `<script>
    window.location = ${JSON.stringify(location)};
    window.parent = window;
    var nativeKhronos = {pass:0,fail:0,skipped:0,errors:[]};
    window.webglTestHarness = {
      reportResults:function(path, ok, text, skipped) {
        if (skipped) nativeKhronos.skipped++;
        else if (ok) nativeKhronos.pass++;
        else { nativeKhronos.fail++; if(nativeKhronos.errors.length < 8) nativeKhronos.errors.push(text); }
        if (nativeKhronos.pass + nativeKhronos.fail + nativeKhronos.skipped === 1 || (nativeKhronos.pass + nativeKhronos.fail + nativeKhronos.skipped) % 50 === 0 || !ok)
          console.log("SILICANTO_KHRONOS_PROGRESS=" + JSON.stringify(nativeKhronos));
      },
      notifyFinished:function(){ console.log("SILICANTO_KHRONOS_RESULT=" + JSON.stringify(nativeKhronos)); }
    };
  </script>`;
  const original = readFileSync(join(tests, name), "utf8");
  const first = original.search(/<script\b/i);
  assert.ok(first >= 0, "Test page has no script");
  const entry = join(mirror, basename(name));
  writeFileSync(
    entry,
    original.slice(0, first) + reporter + original.slice(first),
  );
  return entry;
}
for (const id of selected) {
  let stage = "translate",
    work;
  const row = { id };
  try {
    emitModules(
      await resolveGraph(join(tests, id.split("?")[0]), { webRoot: tests }),
    );
    if (values["frontend-only"]) row.status = "haxe-emitted";
    else {
      work = mkdtempSync(join(tmpdir(), "silicanto-khronos-page-"));
      const entry = nativePage(id, work),
        project = join(work, "project");
      stage = "build";
      run(
        process.execPath,
        [
          "src/cli.mjs",
          "build",
          entry,
          "--frontend",
          "generic",
          "--web-root",
          join(work, "tests"),
          "--target",
          values.target,
          "--out",
          project,
        ],
        buildTimeout,
      );
      stage = "run";
      const args = ["--asset-root", dirname(entry), "--frames", "240"];
      const output =
        values.target === "cpp"
          ? run(join(project, "cpp/Sample"), args)
          : run(jdk("java"), [
              "-Djava.awt.headless=true",
              "-jar",
              join(project, "java/Sample.jar"),
              ...args,
            ]);
      const results = [...output.matchAll(/^SILICANTO_KHRONOS_RESULT=(.+)$/gm)];
      if (results.length !== 1) {
        const failure = Error(
          "Expected exactly one completion notification, received " +
            results.length,
        );
        failure.stdout = output;
        throw failure;
      }
      row.assertions = JSON.parse(results[0][1]);
      row.status = row.assertions.fail
        ? "assertion-failed"
        : row.assertions.pass
          ? "passed"
          : "no-assertions";
    }
  } catch (e) {
    row.status = stage + "-failed";
    const stdout = String(e.stdout ?? "");
    const progress = [
      ...stdout.matchAll(/^SILICANTO_KHRONOS_PROGRESS=(.+)$/gm),
    ].at(-1);
    if (stage === "run" && progress) row.lastProgress = JSON.parse(progress[1]);
    const details = stripVTControlCharacters(
      [
        e.stderr?.trim(),
        stdout.replace(/^SILICANTO_KHRONOS_PROGRESS=.+$/gm, "").trim(),
      ]
        .filter(Boolean)
        .join("\n"),
    );
    const lines = details.split("\n");
    const errors =
      stage === "build"
        ? lines.filter((line) =>
            /error|failed|characters? \d+|no space/i.test(line),
          )
        : [];
    const reason =
      e.stdout !== undefined && e.message.startsWith("Expected exactly")
        ? e.message
        : "";
    row.diagnostic = [
      reason,
      errors.join("\n") || details || e.signal || e.message,
    ]
      .filter(Boolean)
      .join("\n")
      .replaceAll(checkout + "/", "")
      .replaceAll(root, "")
      .replaceAll(work ? work + "/" : "\0", "<work>/")
      .slice(0, 1400);
  } finally {
    if (work) rmSync(work, { recursive: true, force: true });
  }
  report.cases.push(row);
  if (report.cases.length % 25 === 0) save();
}
save();
const counts = {};
for (const c of report.cases) counts[c.status] = (counts[c.status] ?? 0) + 1;
console.log(
  JSON.stringify({
    version: values.version,
    selected: selected.length,
    counts,
  }),
);
if (report.cases.some((c) => !["passed", "haxe-emitted"].includes(c.status)))
  process.exitCode = 1;
