#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { translate } from "./module-graph.mjs";
import { packScene } from "./scene-asset.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const sha = (data) => createHash("sha256").update(data).digest("hex");
const usage = [
  "Silicanto — Run Three.js as native code.",
  "",
  "silicanto check INPUT",
  "silicanto emit INPUT --out DIR [--target haxe|c|cpp|js|python]",
  "silicanto build INPUT --target haxe|c|cpp|js|python --out DIR",
  "silicanto target HAXE_PROJECT --target NAME --out DIR",
  "",
  "build and target also accept --target NAME --backend FILE.hxml.",
  "emit defaults to editable Haxe. build defaults to native C.",
].join("\n");
try {
  const {
    values,
    positionals: [cmd, input, ...extra],
  } = parseArgs({
    allowPositionals: true,
    options: {
      out: { type: "string" },
      target: { type: "string" },
      graphics: { type: "string" },
      name: { type: "string" },
      backend: { type: "string" },
      help: { type: "boolean", short: "h" },
    },
  });
  if (values.help) {
    console.log(usage);
    process.exit(0);
  }
  if (
    !["check", "emit", "build", "target"].includes(cmd) ||
    !input ||
    extra.length
  )
    throw Error(usage);
  const target = values.target ?? (cmd === "emit" ? "haxe" : "c"),
    name = values.name ?? "Sample";
  const backend = values.backend && resolve(values.backend);
  if (
    backend &&
    (!["build", "target"].includes(cmd) ||
      !values.target ||
      !existsSync(backend) ||
      !backend.endsWith(".hxml"))
  )
    throw Error(
      "E-BACKEND: use build INPUT or target HAXE_PROJECT with --target NAME --backend FILE.hxml --out DIR",
    );
  if (!backend && !["haxe", "c", "cpp", "js", "python"].includes(target))
    throw Error("E-TARGET: " + target + " has no registered Haxe backend");
  if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(name))
    throw Error("E-NAME: use a simple executable name");
  const expectedGraphics =
    target === "js"
      ? "webgl"
      : ["cpp", "c"].includes(target)
        ? "metal"
        : undefined;
  if (values.graphics && values.graphics !== expectedGraphics)
    throw Error("E-TARGET: graphics backend unavailable for " + target);
  const source = resolve(input);
  const assets = new Map();
  let hx, metadata;
  if (cmd === "target") {
    metadata = JSON.parse(readFileSync(join(source, "manifest.json"), "utf8"));
    if (metadata.pipeline !== "js-haxe" || metadata.entry !== "haxe/Sample.hx")
      throw Error("E-INPUT: expected a generated Haxe project");
    hx = readFileSync(join(source, metadata.entry), "utf8");
  } else {
    const result = await translate(source, (path) => {
      if (!assets.has(path))
        assets.set(path, packScene(resolve(dirname(source), path)));
      return assets.get(path).sha256;
    });
    hx = result.haxe;
    metadata = {
      inputs: result.inputs.map((p) => ({
        file: relative(dirname(source), p),
        sha256: sha(readFileSync(p)),
      })),
      haxe: "4.3.7",
      pipeline: "js-haxe",
      entry: "haxe/Sample.hx",
      graphicsHost: hx.startsWith("import Three;"),
      sceneAssets: Object.fromEntries(
        [...assets].map(([p, a]) => [p, a.sha256]),
      ),
      sourceSHA256: sha(readFileSync(source)),
    };
  }
  if (metadata.graphicsHost && target === "python")
    throw Error("E-TARGET: Python graphics host pending");
  if (target === "js" && Object.keys(metadata.sceneAssets).length)
    throw Error("E-TARGET: static scene asset adapter pending for WebGL");
  if (cmd === "check") {
    console.log("OK JS → Haxe · " + input);
  } else {
    if (!values.out) throw Error("--out is required");
    const dest = resolve(values.out);
    if (existsSync(dest))
      throw Error("E-OUTPUT: choose a new directory: " + dest);
    mkdirSync(dirname(dest), { recursive: true });
    const stage = mkdtempSync(join(dirname(dest), ".silicanto-"));
    try {
      if (cmd === "target") {
        cpSync(join(source, "haxe"), join(stage, "haxe"), { recursive: true });
        if (existsSync(join(source, "assets")))
          cpSync(join(source, "assets"), join(stage, "assets"), {
            recursive: true,
          });
      } else {
        mkdirSync(join(stage, "haxe"));
        const runtime = [
          "WebConsole.hx",
          "WebFloat32.hx",
          "WebArray.hx",
          "WebBits.hx",
        ];
        if (metadata.graphicsHost)
          runtime.push(
            "Host.hx",
            "BrowserHost.hx",
            "three-browser.js",
            "Three.hx",
            "MetalSurface.hx",
            "SceneBuffers.hx",
            "ProcApi.hx",
            "ProcJs.hx",
            "GeometryData.hx",
            "SceneGraph.hx",
            "SceneUpload.hx",
            "box.metal",
            "scene.metal",
          );
        for (const f of runtime)
          cpSync(join(root, "runtime", f), join(stage, "haxe", f));
        writeFileSync(join(stage, "haxe/Sample.hx"), hx);
        if (assets.size) mkdirSync(join(stage, "assets"));
        for (const asset of assets.values()) {
          const base = join(stage, "assets", asset.sha256);
          writeFileSync(base + ".vertices.z", asset.data);
          if (asset.probe) writeFileSync(base + ".probe", asset.probe);
          writeFileSync(base + ".json", JSON.stringify(asset.metadata));
        }
      }
      mkdirSync(join(stage, "licenses"));
      cpSync(join(root, "LICENSE"), join(stage, "licenses/silicanto.txt"));
      if (metadata.graphicsHost)
        cpSync(join(root, "licenses/three.txt"), join(stage, "licenses/three.txt"));
      if (backend || target !== "haxe") {
        if (!existsSync(join(root, ".toolchain/haxe/haxe")))
          throw Error("Run npm run setup:mac to install Haxe");
        execFileSync(
          "bash",
          [
            join(root, "scripts/haxe-target.sh"),
            stage,
            backend ? "external" : target,
            metadata.graphicsHost ? "graphics" : "logic",
            cmd === "emit" ? "emit" : "build",
            name,
            backend || "",
          ],
          { stdio: "inherit" },
        );
      }
      writeFileSync(
        join(stage, "manifest.json"),
        JSON.stringify({ ...metadata, target, haxeSHA256: sha(hx) }, null, 2) +
          "\n",
      );
      renameSync(stage, dest);
      console.log(dest);
    } finally {
      rmSync(stage, { recursive: true, force: true });
    }
  }
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
}
