import { build } from "esbuild";
import ts from "typescript";
import { SourceMap } from "node:module";
import { readFileSync } from "node:fs";
import { basename, dirname, extname, resolve } from "node:path";
import { compileProject, moduleInput } from "./compiler.mjs";

export async function translate(input, loadScene) {
  const text = readFileSync(input, "utf8");
  const { source, offset, canvas } = moduleInput(input, text);
  const ast = ts.createSourceFile(
    input,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const imports = ast.statements.filter(ts.isImportDeclaration);
  if (
    !imports.some(
      (n) =>
        n.moduleSpecifier.text !== "three" &&
        !n.moduleSpecifier.text.endsWith(".json"),
    )
  )
    return { ...compileProject(input, text, loadScene), inputs: [input] };

  // Bundle only to resolve static ESM bindings and tree-shake unused library exports.
  // No module initializer runs during translation.
  const dir = dirname(input);
  const result = await build({
    absWorkingDir: dir,
    stdin: {
      contents: source,
      resolveDir: dir,
      sourcefile: basename(input),
      loader: extname(input) === ".ts" ? "ts" : "js",
    },
    bundle: true,
    platform: "browser",
    format: "esm",
    target: "esnext",
    plugins: [
      {
        name: "three-facade",
        setup(b) {
          b.onResolve({ filter: /^three$/ }, () => ({
            path: "three",
            external: true,
          }));
        },
      },
    ],
    write: false,
    outfile: "program.js",
    sourcemap: "external",
    metafile: true,
    logLevel: "silent",
  });
  const visited = new Set(),
    active = new Set();
  function visit(path) {
    if (active.has(path))
      throw Error(
        input +
          " E-MODULE: cyclic module initialization requires live binding support: " +
          path,
      );
    if (visited.has(path)) return;
    active.add(path);
    for (const dep of result.metafile.inputs[path]?.imports ?? []) {
      if (dep.kind !== "import-statement")
        throw Error(
          path + " E-MODULE: only static ES module imports are supported",
        );
      if (!dep.external) visit(dep.path);
    }
    active.delete(path);
    visited.add(path);
  }
  for (const path of Object.keys(result.metafile.inputs)) visit(path);
  const map = new SourceMap(
    JSON.parse(result.outputFiles.find((f) => f.path.endsWith(".map")).text),
  );
  const generated = result.outputFiles.find((f) => f.path.endsWith(".js")).text;
  const location = (line, col) => {
    const loc = map.findEntry(line, col);
    if (!loc.originalSource) return;
    const name = resolve(dir, loc.originalSource);
    const extra =
      name === input ? text.slice(0, offset).split("\n").length - 1 : 0;
    return (
      name +
      ":" +
      (loc.originalLine + 1 + extra) +
      ":" +
      (loc.originalColumn + 1)
    );
  };
  return {
    ...compileProject("program.js", generated, loadScene, {
      bundled: true,
      canvas,
      location,
    }),
    inputs: [...visited].map((p) => resolve(dir, p)),
  };
}
