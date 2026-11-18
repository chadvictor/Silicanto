import { build } from "esbuild";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { basename, dirname, relative, resolve } from "node:path";
import ts from "typescript";
import { hasModuleSyntax, normalizeScriptComments, parseScript } from "./classic.mjs";
import { readDocument } from "./document.mjs";

export async function resolveGraph(entry, { externals = [], webRoot } = {}) {
  const dir = realpathSync(dirname(resolve(entry)));
  entry = resolve(dir, basename(entry));
  const document = /\.html?$/i.test(entry)
    ? readDocument(entry, webRoot ?? dir)
    : null;
  const scripts = document?.scripts ?? [{ path: entry, kind: "entry" }];
  const resources = document?.resources ?? [];
  const entries = [...resources, ...scripts];
  const canonical = (script) =>
    script.source === undefined && existsSync(script.path)
      ? realpathSync(script.path)
      : script.path;
  const byPath = new Map(
    entries.flatMap((s) => [
      [s.path, s],
      [canonical(s), s],
    ]),
  );
  const inline = new Map(
    scripts.filter((s) => s.source !== undefined).map((s) => [s.path, s]),
  );
  let result;
  try {
    result = await build({
      absWorkingDir: dir,
      entryPoints: [...new Set(entries.map((s) => s.path))],
      outdir: ".silicanto-analysis",
      entryNames: "[dir]/[name]-[hash]",
      bundle: true,
      platform: "browser",
      format: "esm",
      target: "esnext",
      write: false,
      metafile: true,
      logLevel: "silent",
      plugins: [
        {
          name: "document-scripts",
          setup(b) {
            b.onResolve({ filter: /.*/ }, (args) => {
              if (externals.includes(args.path))
                return { path: args.path, external: true };
              if (webRoot && args.importer && args.path.startsWith("../")) {
                const root = resolve(webRoot),
                  inside = relative(root, args.resolveDir),
                  dest = relative(root, resolve(args.resolveDir, args.path));
                if (!inside.startsWith("..") && dest.startsWith("..")) {
                  const url = new URL(
                    args.path,
                    "https://local.invalid/" + (inside ? inside + "/" : ""),
                  );
                  return {
                    path: resolve(root, "." + decodeURIComponent(url.pathname)),
                  };
                }
              }
              if (inline.has(args.path))
                return { path: args.path, namespace: "inline" };
              if (Object.hasOwn(document?.imports ?? {}, args.path))
                return { path: document.imports[args.path] };
            });
            b.onLoad({ filter: /./, namespace: "file" }, (args) => {
              if (byPath.get(args.path)?.kind !== "classic") return;
              const source = readFileSync(args.path, "utf8");
              if (!hasModuleSyntax(source))
                return { contents: "", loader: "js" };
            });
            b.onLoad({ filter: /.*/, namespace: "inline" }, (args) => ({
              contents:
                inline.get(args.path).kind === "classic" &&
                !hasModuleSyntax(inline.get(args.path).source)
                  ? ""
                  : inline.get(args.path).source,
              loader: "js",
              resolveDir: dir,
            }));
          },
        },
      ],
    });
  } catch (error) {
    const d = error.errors?.[0];
    if (!d) throw error;
    throw Error(
      `${d.location?.file || entry}:${d.location?.line || 1}:${(d.location?.column ?? 0) + 1} E-MODULE: ${d.text}`,
    );
  }
  const normalize = (id) =>
    id.startsWith("inline:") ? relative(dir, id.slice(7)) : id;
  const records = result.metafile.inputs;
  const modules = Object.keys(records)
    .sort()
    .map((key, index) => {
      const id = normalize(key),
        disabled = id.startsWith("(disabled):"),
        path = resolve(dir, id),
        script = byPath.get(path);
      const edges = records[key].imports.map((i) => ({
        request: i.original ?? i.path,
        kind: i.kind,
        to: normalize(i.path),
        external: !!i.external,
      }));
      return {
        id,
        index,
        path,
        disabled,
        sourcePath: inline.has(path) ? entry : path,
        line: script?.line ?? 0,
        format: disabled
          ? "empty"
          : script?.kind === "classic"
            ? "classic"
            : path.endsWith(".json")
              ? "json"
              : (records[key].format ??
                (script?.kind === "module" ? "esm" : "script")),
        edges,
        source: disabled
          ? ""
          : inline.has(path)
            ? inline.get(path).source
            : readFileSync(path, "utf8"),
      };
    });
  const byId = new Map(modules.map((m) => [m.id, m])),
    roots = scripts.map(
      (s) =>
        byId.get(relative(dir, s.path)) ??
        byId.get(relative(dir, canonical(s))),
    );
  if (roots.some((r) => !r))
    throw Error("E-MODULE: missing graph entry " + entry);
  const scriptModules = resources.map((resource) => ({
    aliases: resource.aliases,
    module:
      byId.get(relative(dir, resource.path)) ??
      byId.get(relative(dir, canonical(resource))),
  }));
  return {
    scriptModules,
    entry: roots[0],
    roots,
    modules,
    byId,
    dir,
    document,
    inputs: [
      ...new Set([
        entry,
        ...(document?.styleInputs ?? []),
        ...modules.filter((m) => !m.disabled).map((m) => m.sourcePath),
      ]),
    ],
    manifest: {
      entry: relative(dir, entry),
      scripts: roots.map((r) => r.id),
      ...(scriptModules.length
        ? {
            scriptResources: scriptModules.map((r) => ({
              urls: r.aliases,
              module: r.module.id,
            })),
          }
        : {}),
      modules: modules.map(({ id, format, edges }) => ({
        id,
        format,
        imports: edges,
      })),
    },
  };
}

export function syntax(module) {
  const script = ["classic", "cjs", "script"].includes(module.format)
    && !/\.[cm]?tsx?$/.test(module.path);
  let source = module.source, parsed;
  const parseLegacy = () => {
    if (parsed === undefined) {
      try {
        parsed = parseScript(source, module.format === "cjs");
      } catch {
        parsed = null;
      }
    }
    return parsed;
  };
  if (script && /<!--|-->/.test(source) && parseLegacy())
    source = normalizeScriptComments(source, parsed.comments);
  const file = ts.createSourceFile(
    module.sourcePath,
    source,
    ts.ScriptTarget.Latest,
    true,
    /\.[cm]?tsx?$/.test(module.path) ? ts.ScriptKind.TS : ts.ScriptKind.JS,
  );
  const diagnostic = file.parseDiagnostics.find((d) => {
    // TypeScript decodes legacy octals but diagnoses them in every scope.
    // The script parser enforces the actual directive, function and class scope.
    return !script || ![1121, 1487, 1488].includes(d.code) || !parseLegacy();
  });
  if (diagnostic) {
    const error = diagnostic,
      { line, character } = file.getLineAndCharacterOfPosition(error.start);
    throw Error(
      `${module.id}:${line + 1 + module.line}:${character + 1} E-SYNTAX: ${ts.flattenDiagnosticMessageText(error.messageText, " ")}`,
    );
  }
  return file;
}
