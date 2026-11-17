#!/usr/bin/env node
import { registry, selectPayload, projectProfile } from "./targets.mjs";
import { createHash } from "node:crypto";
import {
  cpSync,
  readdirSync,
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
import { translate, resolveGraph } from "./module-graph.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const sha = (data) => createHash("sha256").update(data).digest("hex");
const usage = [
  "Silicanto — Run Three.js as native code.",
  "",
  "silicanto graph INPUT",
  "silicanto check INPUT [--frontend generic]",
  "silicanto emit INPUT --out DIR [--target NAME]",
  "silicanto build INPUT --target NAME --out DIR",
  "silicanto target HAXE_PROJECT --target NAME --out DIR",
  "",
  "silicanto targets [--payload FILE.mjs]",
  "Select a platform payload with --platform ID, --graphics ID, or --payload FILE.mjs.",
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
      "web-root": { type: "string" },
      frontend: { type: "string", default: "auto" },
      target: { type: "string" },
      graphics: { type: "string" },
      name: { type: "string" },
      platform: { type: "string" },
      payload: { type: "string" },
      backend: { type: "string" },
      help: { type: "boolean", short: "h" },
    },
  });
  if (values.help) {
    console.log(usage);
    process.exit(0);
  }
  if (!["auto", "generic"].includes(values.frontend))
    throw Error("E-INPUT: --frontend expects auto or generic");
  if (cmd === "graph" && input && !extra.length) {
    console.log(
      JSON.stringify(
        (await resolveGraph(input, { webRoot: values["web-root"] })).manifest,
        null,
        2,
      ),
    );
    process.exit(0);
  }
  const routes = await registry(values.payload);
  if (cmd === "targets" && !input) {
    console.table(
      routes.map(({ target, platform, graphics, capabilities }) => ({
        target,
        platform,
        graphics,
        profiles: capabilities.join(", "),
      })),
    );
    process.exit(0);
  }
  if (values.backend && values.payload)
    throw Error("E-PAYLOAD: choose --backend or --payload");
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
  if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(name))
    throw Error("E-NAME: use a simple executable name");
  const source = resolve(input);
  const assets = new Map();
  let hx,
    metadata,
    extraSources = {};
  if (cmd === "target") {
    metadata = JSON.parse(readFileSync(join(source, "manifest.json"), "utf8"));
    if (metadata.pipeline !== "js-haxe" || metadata.entry !== "haxe/Sample.hx")
      throw Error("E-INPUT: expected a generated Haxe project");
    hx = readFileSync(join(source, metadata.entry), "utf8");
  } else {
    const result = await translate(
      source,
      (path, packScene) => {
        if (!assets.has(path))
          assets.set(path, packScene(resolve(dirname(source), path)));
        return assets.get(path).sha256;
      },
      values.frontend,
      values["web-root"],
    );
    hx = result.haxe;
    extraSources = result.sources ?? {};
    metadata = {
      frontend: result.frontend,
      moduleGraph: result.graph,
      webHost: !!result.web,
      globals: result.globals,
      inputs: result.inputs.map((p) => ({
        file: relative(dirname(source), p),
        sha256: sha(readFileSync(p)),
      })),
      haxe: "4.3.7",
      pipeline: "js-haxe",
      entry: "haxe/Sample.hx",
      graphicsHost: result.graphicsHost,
      sceneAssets: Object.fromEntries(
        [...assets].map(([p, a]) => [p, a.sha256]),
      ),
      sourceSHA256: sha(readFileSync(source)),
    };
  }
  const mode = cmd === "emit" ? "emit" : "build";
  const profile = projectProfile(metadata);
  const route =
    cmd !== "check" || values.target || values.platform || values.graphics
      ? selectPayload(routes, {
          target,
          platform: values.platform,
          graphics: values.graphics,
          backend,
          profile,
          mode: cmd === "check" ? "check" : mode,
        })
      : null;
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
        for (const group of [
          "ecmascript",
          ...(metadata.webHost ? ["web"] : []),
          ...(metadata.graphicsHost ? ["legacy/three"] : []),
        ]) {
          for (const name of readdirSync(join(root, "runtime", group))) {
            if (/\.(?:hx|metal|js)$/.test(name))
              cpSync(
                join(root, "runtime", group, name),
                join(stage, "haxe", name),
              );
          }
        }
        if (metadata.webHost)
          cpSync(join(root, "runtime/web/format"), join(stage, "haxe/format"), {
            recursive: true,
          });
        for (const [name, code] of Object.entries(extraSources))
          writeFileSync(join(stage, "haxe", name), code);
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
      if (metadata.webHost)
        cpSync(
          join(root, "licenses/haxe-format.txt"),
          join(stage, "licenses/haxe-format.txt"),
        );
      if (metadata.graphicsHost)
        cpSync(
          join(root, "licenses/three.txt"),
          join(stage, "licenses/three.txt"),
        );
      const manifest = {
        ...metadata,
        target,
        haxeSHA256: sha(hx),
        payload: {
          apiVersion: route.apiVersion,
          platform: route.platform,
          graphics: route.graphics,
          profile,
        },
      };
      writeFileSync(
        join(stage, "manifest.json"),
        JSON.stringify(manifest, null, 2) + "\n",
      );
      await route.build({
        projectDir: stage,
        manifest,
        target,
        mode,
        name,
        backend,
      });
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
