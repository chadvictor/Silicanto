// Structural rules for script forms that also occur in the Haxe 4.3.7 JS backend.
// Operate on original nodes so errors retain the input file's line and column.
import ts from "typescript";

function unparen(node) {
  while (ts.isParenthesizedExpression(node)) node = node.expression;
  return node;
}

function hostGlobal(node, names = ["window", "global", "self"]) {
  node = unparen(node);
  if (!names.length) return node.kind === ts.SyntaxKind.ThisKeyword;
  if (!ts.isConditionalExpression(node)) return false;
  const test = unparen(node.condition),
    name = names[0];
  return (
    ts.isBinaryExpression(test) &&
    [
      ts.SyntaxKind.ExclamationEqualsToken,
      ts.SyntaxKind.ExclamationEqualsEqualsToken,
    ].includes(test.operatorToken.kind) &&
    ts.isTypeOfExpression(test.left) &&
    ts.isIdentifier(test.left.expression) &&
    test.left.expression.text === name &&
    ts.isStringLiteral(test.right) &&
    test.right.text === "undefined" &&
    ts.isIdentifier(node.whenTrue) &&
    node.whenTrue.text === name &&
    hostGlobal(node.whenFalse, names.slice(1))
  );
}

export function scriptBody(file) {
  const fallback = { statements: file.statements };
  if (
    file.statements.length !== 1 ||
    !ts.isExpressionStatement(file.statements[0])
  )
    return fallback;
  const call = unparen(file.statements[0].expression);
  if (!ts.isCallExpression(call) || call.questionDotToken) return fallback;
  const fn = unparen(call.expression);
  if (
    !ts.isFunctionExpression(fn) ||
    fn.name ||
    fn.asteriskToken ||
    fn.modifiers?.length
  )
    return fallback;
  const [directive, ...statements] = fn.body.statements;
  if (
    !directive ||
    !ts.isExpressionStatement(directive) ||
    !ts.isStringLiteral(directive.expression) ||
    directive.expression.text !== "use strict"
  )
    return fallback;
  if (!call.arguments.length && !fn.parameters.length) return { statements };
  const [p] = fn.parameters;
  if (
    call.arguments.length !== 1 ||
    fn.parameters.length !== 1 ||
    !ts.isIdentifier(p.name) ||
    p.initializer ||
    p.dotDotDotToken
  )
    return fallback;
  const arg = unparen(call.arguments[0]);
  if ((ts.isIdentifier(arg) && arg.text === "globalThis") || hostGlobal(arg))
    return { statements, global: p.name.text };
  return fallback;
}

const method = (name, fn, isStatic = false) => ({ name, fn, isStatic });

export function modernClass(node, fail) {
  if (node.heritageClauses?.length || node.modifiers?.length)
    fail(node, "unsupported class inheritance or modifier");
  return node.members.map((m) => {
    const ctor = ts.isConstructorDeclaration(m);
    if (
      (!ctor && (!ts.isMethodDeclaration(m) || !ts.isIdentifier(m.name))) ||
      !m.body ||
      m.asteriskToken ||
      m.modifiers?.some((mod) => mod.kind !== ts.SyntaxKind.StaticKeyword)
    )
      fail(m, "unsupported class member");
    return method(ctor ? null : m.name.text, m, !!m.modifiers?.length);
  });
}

function plainFunction(n) {
  return (
    ts.isFunctionExpression(n) &&
    !n.name &&
    !n.asteriskToken &&
    !n.modifiers?.length
  );
}

// The accepted assignments only install functions. Leave computed properties,
// getters, redefinitions and other initialization to the normal diagnostics.
export function legacyClass(statements, index) {
  const decl = statements[index];
  if (
    !ts.isVariableStatement(decl) ||
    decl.declarationList.declarations.length !== 1
  )
    return;
  const d = decl.declarationList.declarations[0];
  if (
    !ts.isIdentifier(d.name) ||
    !d.initializer ||
    !plainFunction(d.initializer)
  )
    return;
  const name = d.name.text,
    members = [method(null, d.initializer)];
  let next = index + 1,
    prototypeAssigned = false;
  for (; next < statements.length; next++) {
    const st = statements[next];
    if (!ts.isExpressionStatement(st) || !ts.isBinaryExpression(st.expression))
      break;
    const { left, right, operatorToken } = st.expression;
    if (
      operatorToken.kind !== ts.SyntaxKind.EqualsToken ||
      !ts.isPropertyAccessExpression(left) ||
      !ts.isIdentifier(left.expression) ||
      left.expression.text !== name
    )
      break;
    if (
      left.name.text === "prototype" &&
      ts.isObjectLiteralExpression(right) &&
      right.properties.every(
        (p) =>
          ts.isPropertyAssignment(p) &&
          ts.isIdentifier(p.name) &&
          p.name.text !== "__proto__" &&
          plainFunction(p.initializer),
      )
    ) {
      if (prototypeAssigned) break;
      prototypeAssigned = true;
      for (const p of right.properties)
        members.push(method(p.name.text, p.initializer));
    } else if (
      plainFunction(right) &&
      ![
        "name",
        "length",
        "prototype",
        "__proto__",
        "caller",
        "arguments",
        "call",
        "apply",
        "bind",
      ].includes(left.name.text)
    ) {
      members.push(method(left.name.text, right, true));
    } else break;
  }
  if (next !== index + 1) return { name, members, next };
}

// A function-scoped var can use a typed Haxe local when every use stays in
// its declared block, follows initialization, and no nested closure captures it.
export function checkVar(declaration, fail) {
  if (!ts.isIdentifier(declaration.name))
    fail(declaration, "unsupported var pattern");
  const name = declaration.name.text,
    block = declaration.parent.parent.parent;
  let owner = block;
  while (owner.parent && !ts.isFunctionLike(owner)) owner = owner.parent;
  function visit(n, inside = false, nested = false) {
    inside ||= n === block;
    nested ||= n !== owner && ts.isFunctionLike(n);
    if (ts.isIdentifier(n) && n.text === name && n !== declaration.name) {
      if (ts.isPropertyAccessExpression(n.parent) && n.parent.name === n)
        return;
      if (
        !inside ||
        nested ||
        n.pos < declaration.name.pos ||
        (ts.isVariableDeclaration(n.parent) && n.parent.name === n) ||
        (ts.isParameter(n.parent) && n.parent.name === n)
      )
        fail(
          n,
          "var hoisting, redeclaration or capture requires function-scope analysis",
        );
    }
    ts.forEachChild(n, (child) => visit(child, inside, nested));
  }
  visit(owner);
}
