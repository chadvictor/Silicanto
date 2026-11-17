import { build } from "esbuild";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  realpathSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { moduleInput } from "./compiler.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const toolchain = join(root, ".toolchain/aot");

export async function buildNative(filename, output, name = "Application") {
  if (!output) throw Error("build requires --out");
  if (!/^[A-Za-z][A-Za-z0-9-]*$/.test(name))
    throw Error("Use an ASCII application name starting with a letter");
  const compiler = join(toolchain, "build/bin/shermes");
  if (
    !existsSync(compiler) ||
    !existsSync(join(toolchain, "libraries/libexgl.a"))
  )
    throw Error("Run npm run setup:aot first");
  const dest = resolve(output),
    input = realpathSync(filename);
  if (existsSync(dest))
    throw Error("E-OUTPUT: choose a new directory: " + dest);
  mkdirSync(dirname(dest), { recursive: true });
  const stage = mkdtempSync(join(dirname(dest), ".threec-native-"));
  try {
    const html =
      input.endsWith(".html") &&
      moduleInput(input, readFileSync(input, "utf8"));
    const prelude = [
      join(toolchain, "constructors.js"),
      join(root, "runtime/legacy/three/aot/platform.js"),
    ];
    const init = html?.canvas
      ? "globalThis.__nativeCanvas.id = " +
        JSON.stringify(html.canvas.slice(1)) +
        ";"
      : "";
    const result = await build({
      stdin: {
        contents:
          prelude.map((p) => "import " + JSON.stringify(p) + ";").join("\n") +
          '\nimport "native-canvas-id";\nimport "native-entry";',
        resolveDir: dirname(input),
        sourcefile: "<native-entry>",
      },
      absWorkingDir: root,
      bundle: true,
      format: "iife",
      platform: "browser",
      target: "es2015",
      metafile: true,
      write: false,
      logLevel: "silent",
      plugins: [
        {
          name: "native-input",
          setup(b) {
            b.onResolve({ filter: /^native-canvas-id$/ }, () => ({
              path: "canvas",
              namespace: "host",
            }));
            b.onLoad({ filter: /.*/, namespace: "host" }, () => ({
              contents: init,
            }));
            b.onResolve({ filter: /^native-entry$/ }, () =>
              html
                ? { path: input, namespace: "inline-module" }
                : { path: input },
            );
            b.onLoad({ filter: /.*/, namespace: "inline-module" }, () => ({
              contents: html.source,
              resolveDir: dirname(input),
            }));
          },
        },
      ],
    });
    const bundle = join(stage, "input.js");
    writeFileSync(bundle, result.outputFiles[0].contents);
    execFileSync(
      compiler,
      [
        "-O",
        "-strict",
        "-Xes6-block-scoping",
        "-Xenable-tdz",
        "-g1",
        "-Wno-undefined-variable",
        "-emit-c",
        "-exported-unit=app",
        "-o",
        join(stage, "app.c"),
        bundle,
      ],
      { stdio: "inherit" },
    );
    rmSync(bundle);
    execFileSync("bash", [join(root, "scripts/link-aot.sh"), stage, name], {
      stdio: "inherit",
    });
    const sources = Object.keys(result.metafile.inputs)
      .filter((p) => !p.endsWith("<native-entry>") && p !== "host:canvas")
      .map((p) => resolve(root, p.replace(/^inline-module:/, "")));
    const inputs = [...new Set(sources)].map((p) => ({
      file: relative(dirname(input), p),
      sha256: createHash("sha256").update(readFileSync(p)).digest("hex"),
    }));
    writeFileSync(
      join(stage, "manifest.json"),
      JSON.stringify(
        {
          pipeline: "static-hermes-c-aot",
          target: "macos-arm64",
          graphics: "ANGLE Metal",
          inputs,
          executable: name + ".app/Contents/MacOS/" + name,
        },
        null,
        2,
      ) + "\n",
    );
    renameSync(stage, dest);
    console.log(join(dest, name + ".app"));
  } finally {
    rmSync(stage, { recursive: true, force: true });
  }
}
