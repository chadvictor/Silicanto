// Module resolution should not run a bundler's optimizer on a classic script
// with no module edges. In particular, a write to const is a runtime exception
// in JavaScript. The compiler still parses and lowers the original script.
import ts from "typescript";
import { parseSync } from "@babel/core";

// Annex B changes the lexical grammar of scripts. Ask the JS parser which
// tokens really are HTML comments so strings, regexes and templates survive.
export function parseScript(source, commonJS = false) {
  return parseSync(source, {
    configFile: false,
    babelrc: false,
    sourceType: "script",
    parserOpts: { allowReturnOutsideFunction: commonJS },
  });
}

export function normalizeScriptComments(source, comments) {
  let result = "", start = 0;
  for (const comment of comments) {
    if (comment.type !== "CommentLine") continue;
    const from = comment.start;
    const size = source.startsWith("<!--", from) ? 4 : source.startsWith("-->", from) ? 3 : 0;
    if (!size) continue;
    result += source.slice(start, from) + "//".padEnd(size);
    start = from + size;
  }
  return start ? result + source.slice(start) : source;
}
export function hasModuleSyntax(source) {
  // A backslash may introduce an escaped identifier such as require.
  if (!/import|export|require|\\/.test(source)) return false;
  const tree = ts.createSourceFile(
    "classic.js",
    source,
    ts.ScriptTarget.Latest,
    false,
    ts.ScriptKind.JS,
  );
  function search(n) {
    if (
      n.kind === ts.SyntaxKind.ImportKeyword ||
      n.kind === ts.SyntaxKind.ExportKeyword ||
      ts.isImportDeclaration(n) ||
      ts.isExportDeclaration(n) ||
      (ts.isIdentifier(n) && n.text === "require")
    )
      return true;
    return ts.forEachChild(n, search);
  }
  return !!search(tree);
}
