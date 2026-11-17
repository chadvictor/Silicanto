import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import ts from "typescript";

function scriptRequests(code) {
  if (!/createElement\s*\(\s*["']script["']\s*\)/i.test(code)) return [];
  const file = ts.createSourceFile(
    "document.js",
    code,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.JS,
  );
  const holders = new Set(),
    requests = [];
  function isScript(node) {
    return (
      node &&
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === "createElement" &&
      ts.isStringLiteralLike(node.arguments[0] ?? file) &&
      node.arguments[0].text.toLowerCase() === "script"
    );
  }
  function discover(node) {
    if (
      ts.isVariableDeclaration(node) &&
      ts.isIdentifier(node.name) &&
      isScript(node.initializer)
    )
      holders.add(node.name.text);
    if (
      ts.isBinaryExpression(node) &&
      node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
      ts.isIdentifier(node.left) &&
      isScript(node.right)
    )
      holders.add(node.left.text);
    ts.forEachChild(node, discover);
  }
  function record(expr) {
    let suffix = false;
    if (
      ts.isBinaryExpression(expr) &&
      expr.operatorToken.kind === ts.SyntaxKind.PlusToken
    ) {
      suffix = true;
      expr = expr.right;
    }
    let url;
    if (ts.isStringLiteralLike(expr)) url = expr.text;
    else if (ts.isTemplateExpression(expr)) {
      suffix = true;
      url = expr.templateSpans.at(-1).literal.text;
    }
    if (
      url &&
      /\.[cm]?js(?:[?#].*)?$/i.test(url) &&
      !/^(?:[a-z]+:|\/\/)/i.test(url)
    )
      requests.push({ url: url.split(/[?#]/, 1)[0], suffix });
  }
  function visit(node) {
    if (
      ts.isBinaryExpression(node) &&
      node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
      ts.isPropertyAccessExpression(node.left) &&
      node.left.name.text === "src" &&
      ts.isIdentifier(node.left.expression) &&
      holders.has(node.left.expression.text)
    )
      record(node.right);
    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      ts.isIdentifier(node.expression.expression) &&
      holders.has(node.expression.expression.text) &&
      node.expression.name.text === "setAttribute" &&
      node.arguments.length >= 2 &&
      ts.isStringLiteralLike(node.arguments[0]) &&
      node.arguments[0].text === "src"
    )
      record(node.arguments[1]);
    ts.forEachChild(node, visit);
  }
  discover(file);
  if (holders.size) visit(file);
  return requests;
}

// Script URLs are resolved against the document. A computed prefix can also
// address a resource beside the script that constructs it. Only a registered
// URL that exists at build time can select a native module at run time.
export function scriptResources(entries, documentDir, webRoot) {
  const queue = [...entries],
    scanned = new Set(),
    resources = new Map();
  for (let i = 0; i < queue.length; i++) {
    const script = queue[i];
    if (scanned.has(script.path)) continue;
    scanned.add(script.path);
    if (script.source === undefined && !existsSync(script.path)) continue;
    const source = script.source ?? readFileSync(script.path, "utf8");
    for (const { url, suffix } of scriptRequests(source)) {
      let pathname;
      try {
        pathname = decodeURIComponent(url);
      } catch {
        continue;
      }
      const paths =
        pathname.startsWith("/") && !suffix
          ? [resolve(webRoot, "." + pathname)]
          : [
              ...new Set(
                [documentDir, ...(suffix ? [dirname(script.path)] : [])].map(
                  (base) =>
                    resolve(
                      base,
                      suffix ? pathname.replace(/^\/+/, "") : pathname,
                    ),
                ),
              ),
            ];
      for (const path of paths) {
        if (
          resources.has(path) ||
          !statSync(path, { throwIfNoEntry: false })?.isFile()
        )
          continue;
        const aliases = [relative(documentDir, path).split("\\").join("/")];
        const withinRoot = relative(webRoot, path).split("\\").join("/");
        if (withinRoot !== ".." && !withinRoot.startsWith("../"))
          aliases.push("/" + withinRoot);
        const resource = { path, kind: "classic", aliases };
        resources.set(path, resource);
        queue.push(resource);
      }
    }
  }
  return [...resources.values()];
}
