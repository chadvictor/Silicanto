// This directory is an external compiler consumer. No framework symbols or shims
// are installed in the compiler. UMD and example scripts load in upstream order.
import { execFileSync, execFile, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
  symlinkSync,
  copyFileSync,
  renameSync,
} from "node:fs";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify, parseArgs } from "node:util";
import { jdk } from "../jdk.mjs";
import { batchSuite } from "./batch.mjs";
import { resolveGraph } from "../../src/frontend/graph.mjs";
import { emitModules } from "../../src/frontend/modules.mjs";
import {
  referenceFrame,
  compareFrame,
  closeReferenceBrowser,
} from "./reference.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const suite = fileURLToPath(new URL("./", import.meta.url));
const rev = "eb87db8355861ae222d0c5cd13aae54c2d7d72ae";
const options = parseArgs({
  options: {
    checkout: { type: "string" },
    target: { type: "string", default: "java" },
    out: { type: "string" },
    filter: { type: "string" },
    cases: { type: "string" },
    stage: { type: "string", default: "native" },
    "batch-size": { type: "string", default: "128" },
  },
}).values;
const checkout = resolve(
  options.checkout ?? join(root, ".toolchain/phaser-examples"),
);
const optionsTarget = options.target;
if (!["frontend", "bootstrap", "native"].includes(options.stage))
  throw Error("Use --stage frontend or native");
if (!["java", "cpp", "neko"].includes(optionsTarget))
  throw Error("Use --target java, cpp or neko");
function git(...args) {
  return execFileSync("git", ["-C", checkout, ...args], {
    encoding: "utf8",
  }).trim();
}
if (!existsSync(join(checkout, ".git"))) {
  mkdirSync(checkout, { recursive: true });
  git("init", "-q");
  git("remote", "add", "origin", "https://github.com/phaserjs/examples.git");
  git("sparse-checkout", "init", "--cone");
  git(
    "sparse-checkout",
    "set",
    "public/src",
    "public/assets",
    "public/libs/ui",
  );
  git("fetch", "--depth=1", "--filter=blob:none", "origin", rev);
  git("checkout", "--detach", "-q", rev);
}
if (
  git("rev-parse", "HEAD") !== rev ||
  git(
    "status",
    "--porcelain",
    "--untracked-files=no",
    "public/src",
    "public/assets",
    "public/libs",
  )
)
  throw Error("Use an unmodified examples checkout at " + rev);
const engine = join(suite, "node_modules/phaser/dist/phaser.js");
if (!existsSync(engine))
  throw Error("Install the pinned engine with npm ci --prefix tests/phaser4");
const engineSHA256 = createHash("sha256")
  .update(readFileSync(engine))
  .digest("hex");
if (
  engineSHA256 !==
  "71d92687457da59f1233c75827df628ba173e2ad329d3c75f4e4b92d27c9dd1e"
)
  throw Error("The installed engine differs from the pinned npm distribution");
const version = JSON.parse(
  readFileSync(join(dirname(engine), "../package.json")),
).version;
if (version !== "4.1.0") throw Error("Expected the catalog's Phaser 4.1.0");
const pub = join(checkout, "public");
const catalog = readFileSync(join(suite, "catalog.tsv"), "utf8")
  .trimEnd()
  .split("\n")
  .map((line) => {
    const [page, file] = line.split("\t");
    if (!file.startsWith("src/") || !existsSync(join(pub, file)))
      throw Error("Missing catalog source " + file);
    return { page, file };
  });
if (
  catalog.length !== 2061 ||
  new Set(catalog.map((c) => c.file)).size !== 2061
)
  throw Error("Incomplete pinned Phaser catalog");
const requested = options.cases
  ? new Set(readFileSync(options.cases, "utf8").trimEnd().split("\n"))
  : null;
const cases = catalog.filter(
  (c) =>
    (!options.filter || c.file.includes(options.filter)) &&
    (!requested || requested.has(c.file)),
);
if (requested && !options.filter && cases.length !== requested.size)
  throw Error("Case selection contains an unknown source path");
const size = Number(options["batch-size"]);
if (!Number.isInteger(size) || size < 1 || size > 512)
  throw Error("Use a batch size between 1 and 512");
if (!cases.length) throw Error("No matching entries");
mkdirSync(join(root, "dist"), { recursive: true });
const out = options.out
  ? resolve(options.out)
  : mkdtempSync(join(root, "dist/phaser-suite-"));
mkdirSync(out, { recursive: true });
if (existsSync(join(out, "report.json")) || existsSync(join(out, "bootstrap")))
  throw Error("Choose a fresh output directory");
const report = {
  stage: options.stage,
  oracle: "fourth-frame-foreground-v2",
  engine: version,
  revision: rev,
  target: optionsTarget,
  catalogSize: catalog.length,
  selected: cases.length,
  bootstrap: {},
  cases: [],
};
const env = { ...process.env };
if (existsSync(join(root, ".toolchain/neko/neko"))) {
  env.NEKOPATH = join(root, ".toolchain/neko");
  env.DYLD_LIBRARY_PATH = env.NEKOPATH;
}
function run(exe, args, timeout, extra = {}) {
  const r = spawnSync(exe, args, {
    env: { ...env, ...extra },
    encoding: "utf8",
    timeout,
    maxBuffer: 32 << 20,
  });
  if (r.status !== 0 || r.error) {
    const detail =
      r.error?.message ||
      r.stderr?.trim() ||
      r.stdout?.trim() ||
      "process exited with " + (r.signal ?? r.status);
    throw Error(
      detail.length > 5000
        ? detail.slice(0, 2200) + "\n…\n" + detail.slice(-2800)
        : detail,
    );
  }
}
function scriptsFor(file) {
  const folder = dirname(join(pub, file)),
    boot = join(folder, "boot.json");
  if (basename(file) === "main.js" && existsSync(boot)) {
    const config = JSON.parse(readFileSync(boot));
    if (config.files && !config.module)
      return config.files.map((name) => ({ file: join(folder, name) }));
    if (config.module) return [{ file: join(pub, file), module: true }];
  }
  const source = readFileSync(join(pub, file), "utf8");
  return [
    {
      file: join(pub, file),
      rootModule: /^\s*\/\/\s*#module\b/.test(source),
      module: /^\s*\/\/\s*#module\b|^\s*(?:import|export)\s/m.test(source),
    },
  ];
}
const htmlEsc = (s) => s.replaceAll("&", "&amp;").replaceAll('"', "&quot;");
// The upstream viewer injects single #module scripts into its root page; their
// relative imports resolve against public/, unlike modules launched via boot.json.
function nativePaths(folder, scripts) {
  return scripts.map((s, i) => {
    if (!s.rootModule) return s;
    for (const name of ["assets", "libs", "src"])
      if (!existsSync(join(folder, name)))
        symlinkSync(join(pub, name), join(folder, name), "dir");
    const dest = join(folder, "gallery-entry-" + i + ".mjs");
    copyFileSync(s.file, dest);
    return { ...s, file: dest };
  });
}
function html(scripts, url) {
  return (
    '<!doctype html><html><body><div id="phaser-example"></div>' +
    [{ file: engine }, ...scripts]
      .map(
        (s) =>
          "<script " +
          (s.module ? 'type="module" ' : "") +
          'src="' +
          htmlEsc(url(s.file)) +
          '"></script>',
      )
      .join("\n") +
    "</body></html>"
  );
}
function emit(folder, scripts) {
  mkdirSync(folder, { recursive: true });
  const entry = join(folder, "index.html"),
    project = join(folder, "project");
  writeFileSync(
    entry,
    html(nativePaths(folder, scripts), (p) =>
      relative(folder, p).split(sep).map(encodeURIComponent).join("/"),
    ),
  );
  run(
    process.execPath,
    [
      join(root, "src/cli.mjs"),
      "build",
      entry,
      "--frontend",
      "generic",
      "--web-root",
      folder,
      "--target",
      optionsTarget,
      "--out",
      project,
    ],
    1200000,
  );
  return project;
}
const launch = promisify(execFile);
async function execute(project, args, index) {
  args = [...args, "--asset-root", pub];
  const selector =
    index === undefined ? {} : { SILICANTO_EXAMPLE: String(index) };
  const [program, argv] =
    optionsTarget === "java"
      ? [
          jdk("java"),
          [
            "-Djava.awt.headless=true",
            "-jar",
            join(project, "java/Sample.jar"),
            ...args,
          ],
        ]
      : optionsTarget === "cpp"
        ? [join(project, "cpp/Sample"), args]
        : [
            existsSync(join(root, ".toolchain/neko/neko"))
              ? join(root, ".toolchain/neko/neko")
              : "neko",
            [join(project, "neko/Sample.n"), ...args],
          ];
  try {
    await launch(program, argv, {
      env: { ...env, ...selector },
      timeout: 60000,
      maxBuffer: 4 << 20,
    });
  } catch (error) {
    const output =
      error.stderr?.trim() ||
      error.stdout
        ?.split("\n")
        .filter((line) => /^Error :|Exception|E-[A-Z]+:/.test(line))
        .join("\n") ||
      error.stdout?.trim() ||
      error.message;
    throw Error(output.slice(0, 4000));
  }
}
async function compareCase(c, ppm) {
  const scripts = scriptsFor(c.file);
  const rootFile = scripts.find((s) => s.rootModule)?.file;
  const reference = await referenceFrame({
    html: html(scripts, (p) =>
      p === engine
        ? "/engine.js"
        : p === rootFile
          ? "/gallery-entry.mjs"
          : "/" + relative(pub, p).split(sep).map(encodeURIComponent).join("/"),
    ),
    reuse: true,
    rootFile,
    pub,
    checkout,
    rev,
    engine,
    frames: 4,
  });
  return compareFrame(readFileSync(ppm), reference);
}
function save() {
  writeFileSync(
    join(out, "report.partial"),
    JSON.stringify(report, null, 2) + "\n",
  );
  renameSync(join(out, "report.partial"), join(out, "report.json"));
}
if (options.stage === "frontend") {
  // Translate each example source graph separately, so errors in the shared engine cannot mask coverage.
  const scratch = join(out, "sample.html");
  for (const c of cases) {
    try {
      const tags = nativePaths(out, scriptsFor(c.file)).map(
        (s) =>
          "<script " +
          (s.module ? 'type="module" ' : "") +
          'src="' +
          htmlEsc(
            relative(out, s.file).split(sep).map(encodeURIComponent).join("/"),
          ) +
          '"></script>',
      );
      writeFileSync(scratch, tags.join("\n"));
      const graph = await resolveGraph(scratch, { webRoot: out });
      emitModules(graph);
      report.cases.push({ ...c, status: "haxe-emitted", executed: false });
    } catch (e) {
      report.cases.push({
        ...c,
        status: "translation-failed",
        diagnostic: e.message,
        executed: false,
      });
    }
  }
  report.stage = "frontend";
  report.bootstrap = { status: "not-tested" };
  report.counts = Object.fromEntries(
    [...new Set(report.cases.map((c) => c.status))].map((k) => [
      k,
      report.cases.filter((c) => c.status === k).length,
    ]),
  );
  save();
  console.log(
    JSON.stringify({ report: join(out, "report.json"), counts: report.counts }),
  );
  process.exit(report.cases.some((c) => c.status !== "haxe-emitted") ? 1 : 0);
}
const prefix = join(out, "bootstrap");
let stage = "build";
try {
  const project = emit(prefix, []);
  stage = "run";
  await execute(project, ["--frames", "1"]);
  report.bootstrap = { status: "passed" };
} catch (error) {
  report.bootstrap = { status: "failed", stage, diagnostic: error.message };
}
save();
if (options.stage === "bootstrap") {
  console.log(JSON.stringify(report.bootstrap));
  process.exit(report.bootstrap.status === "passed" ? 0 : 1);
}
if (report.bootstrap.status === "failed") {
  // Every catalog entry loads this exact browser script before its own code.
  // Do not count a shared dependency failure as an executed or passing game.
  report.cases = cases.map((c) => ({
    ...c,
    status: "blocked-by-engine",
    executed: false,
  }));
} else if (Number(options["batch-size"]) > 1 && cases.length > 1) {
  const size = Number(options["batch-size"]);
  if (!Number.isInteger(size) || size > 512)
    throw Error("Use a batch size between 1 and 512");
  const scratch = join(out, "input.html");
  await batchSuite({
    project: join(prefix, "project"),
    out,
    cases,
    target: optionsTarget,
    report,
    save,
    batchSize: size,
    documentFor: (c) => {
      const scripts = nativePaths(out, scriptsFor(c.file));
      writeFileSync(
        scratch,
        '<!doctype html><div id="phaser-example"></div>' +
          scripts
            .map(
              (s) =>
                "<script " +
                (s.module ? 'type="module" ' : "") +
                'src="' +
                htmlEsc(
                  relative(out, s.file)
                    .split(sep)
                    .map(encodeURIComponent)
                    .join("/"),
                ) +
                '"></script>',
            )
            .join("\n"),
      );
      return scratch;
    },
    build: (source, dest) =>
      run(
        process.execPath,
        [
          join(root, "src/cli.mjs"),
          "target",
          source,
          "--target",
          optionsTarget,
          "--out",
          dest,
        ],
        1200000,
      ),
    execute,
    compare: compareCase,
  });
} else {
  for (const [index, c] of cases.entries()) {
    const folder = join(out, "case-" + index);
    let phase = "build";
    try {
      const scripts = scriptsFor(c.file),
        project = emit(folder, scripts);
      phase = "run";
      const ppm = join(folder, "native.ppm");
      await execute(project, ["--frames", "4", "--capture", ppm]);
      phase = "reference";
      const measurement = await compareCase(c, ppm);
      report.cases.push({
        ...c,
        status: "frame-matched",
        executed: true,
        measurement,
      });
    } catch (error) {
      report.cases.push({
        ...c,
        status: "failed",
        stage: phase,
        executed: phase !== "build",
        diagnostic: error.message,
      });
    }
    save();
  }
}
await closeReferenceBrowser();
report.counts = Object.fromEntries(
  [...new Set(report.cases.map((c) => c.status))].map((status) => [
    status,
    report.cases.filter((c) => c.status === status).length,
  ]),
);
report.engineSHA256 = createHash("sha256")
  .update(readFileSync(engine))
  .digest("hex");
save();
console.log(
  JSON.stringify({
    report: join(out, "report.json"),
    bootstrap: report.bootstrap,
    counts: report.counts,
  }),
);
if (report.cases.some((c) => c.status !== "frame-matched"))
  process.exitCode = 1;
