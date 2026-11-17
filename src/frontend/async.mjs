import { createRequire, SourceMap } from "node:module";
import ts from "typescript";

const require = createRequire(import.meta.url);
const cache = new Map();

export function lowerAsync(module, file) {
  if (!/\basync\b/.test(file.text)) return { file };
  const hasAsync = (node) =>
    (ts.isFunctionLike(node) &&
      !node.asteriskToken &&
      node.modifiers?.some((m) => m.kind === ts.SyntaxKind.AsyncKeyword)) ||
    ts.forEachChild(node, hasAsync);
  if (!hasAsync(file)) return { file };
  const key = module.sourcePath + "\0" + module.format;
  const hit = cache.get(key);
  if (hit?.source === file.text) return hit.lowered;
  const identifiers = new Set();
  function visit(node) {
    if (ts.isIdentifier(node)) identifiers.add(node.text);
    ts.forEachChild(node, visit);
  }
  visit(file);
  const babel = require("@babel/core");
  const plugin = require("babel-plugin-transform-async-to-promises");
  const output = babel.transformSync(file.text, {
    configFile: false,
    babelrc: false,
    ast: false,
    sourceMaps: true,
    filename: module.sourcePath,
    sourceType: module.format === "esm" ? "module" : "script",
    parserOpts: {
      allowReturnOutsideFunction: module.format === "cjs",
      plugins: /\.[cm]?tsx?$/.test(module.path) ? ["typescript"] : [],
    },
    plugins: [[plugin, { inlineHelpers: true }]],
  });
  const lowered = {
    file: ts.createSourceFile(
      file.fileName,
      output.code,
      ts.ScriptTarget.Latest,
      true,
      file.scriptKind,
    ),
    map: new SourceMap(output.map),
    identifiers,
  };
  if (cache.size >= 12) cache.delete(cache.keys().next().value);
  cache.set(key, { source: file.text, lowered });
  return lowered;
}
