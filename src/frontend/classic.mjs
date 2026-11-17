// Module resolution should not run a bundler's optimizer on a classic script
// with no module edges. In particular, a write to const is a runtime exception
// in JavaScript. The compiler still parses and lowers the original script.
import ts from "typescript";
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
