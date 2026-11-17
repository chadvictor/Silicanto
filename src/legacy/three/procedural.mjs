// Source-to-source lowering for the procedural geometry API. Haxe Dynamic carries
// JS values across higher-order functions and heterogeneous arrays. Numeric
// expressions still execute as native double operations on the C backend.
import ts from "typescript";

const constructors = new Map(
  Object.entries({
    Vector3: [0, 3],
    Color: [0, 1],
    BufferGeometry: [0, 0],
    SphereGeometry: [1, 3],
    TorusGeometry: [1, 5],
    OctahedronGeometry: [1, 1],
    Float32BufferAttribute: [2, 2],
    Scene: [0, 0],
    Group: [0, 0],
    FogExp2: [2, 2],
    Mesh: [2, 2],
    MeshBasicMaterial: [0, 1],
    MeshStandardMaterial: [0, 1],
    HemisphereLight: [3, 3],
    DirectionalLight: [2, 2],
    DataTexture: [5, 5],
    WebGLRenderer: [0, 1],
    PerspectiveCamera: [4, 4],
  }),
);
const constants = {
  DoubleSide: "2",
  RGBAFormat: "1023",
  FloatType: "1015",
  CubeUVReflectionMapping: "306",
  LinearFilter: "1006",
  LinearSRGBColorSpace: '"srgb-linear"',
};
const math = {
  sin: "sin",
  cos: "cos",
  exp: "exp",
  abs: "abs",
  pow: "pow",
  max: "max",
  min: "min",
  floor: "ffloor",
  sqrt: "sqrt",
  tan: "tan",
  ceil: "fceil",
  log: "log",
  atan2: "atan2",
  PI: "PI",
  hypot: "hypot",
  imul: "imul",
};
const apiMembers = new Set(
  "x y z r g b name background fog environment environmentIntensity mapping minFilter magFilter colorSpace needsUpdate position rotation order scale attributes normal color count length code repeat set normalize crossVectors dot fromBufferAttribute clone lerp multiplyScalar sub addScaledVector add copy setAttribute getAttribute setIndex computeVertexNormals getX getY getZ setXYZ updateMatrixWorld lookAt setSize setAnimationLoop render".split(
    " ",
  ),
);
function imports(file) {
  const ns = new Set(),
    named = new Map();
  for (const n of file.statements.filter(ts.isImportDeclaration)) {
    if (n.moduleSpecifier.text !== "three") continue;
    const b = n.importClause?.namedBindings;
    if (b && ts.isNamespaceImport(b)) ns.add(b.name.text);
    else
      for (const p of b?.elements ?? [])
        named.set(p.name.text, (p.propertyName ?? p.name).text);
  }
  return { ns, named };
}
function imported(n, bindings) {
  if (ts.isIdentifier(n)) return bindings.named.get(n.text);
  if (
    ts.isPropertyAccessExpression(n) &&
    ts.isIdentifier(n.expression) &&
    bindings.ns.has(n.expression.text)
  )
    return n.name.text;
}
export function usesProceduralGeometry(file) {
  const bindings = imports(file);
  function visit(n) {
    if (
      ts.isNewExpression(n) &&
      [
        "BufferGeometry",
        "SphereGeometry",
        "TorusGeometry",
        "OctahedronGeometry",
        "MeshStandardMaterial",
        "DataTexture",
        "Float32BufferAttribute",
      ].includes(imported(n.expression, bindings))
    )
      return true;
    return ts.forEachChild(n, visit);
  }
  return !!visit(file);
}

export function emitProcedural(file, fail) {
  const bindings = imports(file);
  const scoped = (parent) => new Map(parent);
  const root = new Map(),
    lines = [];
  let depth = 2,
    serial = 0,
    loop = null,
    returned;
  const results = new WeakMap();
  function vector(n, scope) {
    if (ts.isIdentifier(n)) return !!scope.get(n.text)?.vector;
    if (ts.isNewExpression(n))
      return imported(n.expression, bindings) === "Vector3";
    if (ts.isCallExpression(n) && ts.isPropertyAccessExpression(n.expression)) {
      const call = n.expression;
      return (
        [
          "normalize",
          "set",
          "clone",
          "sub",
          "add",
          "copy",
          "lerp",
          "multiplyScalar",
          "crossVectors",
          "addScaledVector",
          "fromBufferAttribute",
        ].includes(call.name.text) && vector(call.expression, scope)
      );
    }
    return false;
  }
  function kind(n, scope) {
    if (ts.isNumericLiteral(n)) return "Float";
    if (ts.isStringLiteral(n)) return "String";
    if (
      [ts.SyntaxKind.TrueKeyword, ts.SyntaxKind.FalseKeyword].includes(n.kind)
    )
      return "Bool";
    if (ts.isIdentifier(n)) return scope.get(n.text)?.type;
    if (ts.isParenthesizedExpression(n)) return kind(n.expression, scope);
    if (
      ts.isPropertyAccessExpression(n) &&
      ts.isIdentifier(n.expression) &&
      scope.get(n.expression.text)?.numericFields?.has(n.name.text)
    )
      return "Float";
    if (ts.isConditionalExpression(n)) {
      const k = kind(n.whenTrue, scope);
      return k === kind(n.whenFalse, scope) ? k : undefined;
    }
    if (ts.isBinaryExpression(n)) {
      const op = n.operatorToken.getText();
      if (["<", ">", "<=", ">=", "===", "!=="].includes(op)) return "Bool";
      if (["&&", "||"].includes(op))
        return kind(n.left, scope) === "Bool" && kind(n.right, scope) === "Bool"
          ? "Bool"
          : undefined;
      if (op === "+")
        return kind(n.left, scope) === "String" ||
          kind(n.right, scope) === "String"
          ? "String"
          : kind(n.left, scope) === "Float" && kind(n.right, scope) === "Float"
            ? "Float"
            : undefined;
      if (["-", "*", "/", "%", "**", ">>>"].includes(op)) return "Float";
    }
    if (ts.isPrefixUnaryExpression(n))
      return n.operator === ts.SyntaxKind.ExclamationToken ? "Bool" : "Float";
    if (
      ts.isPropertyAccessExpression(n) &&
      ["x", "y", "z"].includes(n.name.text) &&
      vector(n.expression, scope)
    )
      return "Float";
    if (ts.isCallExpression(n)) {
      if (ts.isIdentifier(n.expression))
        return scope.get(n.expression.text)?.result;
      if (
        ts.isPropertyAccessExpression(n.expression) &&
        n.expression.expression.getText() === "Math" &&
        !scope.has("Math")
      )
        return "Float";
    }
  }
  function condition(n, scope) {
    const code = expr(n, scope);
    return kind(n, scope) === "Bool" ? code : "ProcJs.truth(" + code + ")";
  }
  function numericParameters(fn) {
    const names = new Set(
        fn.parameters
          .filter((p) => ts.isIdentifier(p.name))
          .map((p) => p.name.text),
      ),
      used = new Set();
    function visit(n) {
      if (ts.isFunctionLike(n)) return;
      if (ts.isIdentifier(n) && names.has(n.text)) {
        const p = n.parent;
        if (
          (ts.isBinaryExpression(p) &&
            ["*", "/", "%", "-", "**", ">>>"].includes(
              p.operatorToken.getText(),
            )) ||
          (ts.isPrefixUnaryExpression(p) &&
            p.operator === ts.SyntaxKind.MinusToken)
        )
          used.add(n.text);
      }
      ts.forEachChild(n, visit);
    }
    visit(fn.body);
    return used;
  }
  const temp = () => "tmp_" + ++serial;
  const write = (s) => lines.push("  ".repeat(depth) + s);
  const num = (s) => "(" + s + " : Float)";
  const arr = (s) => "(" + s + " : Array<Dynamic>)";
  const methodMath = (name) =>
    name === "imul"
      ? "WebBits.imul"
      : name === "hypot"
        ? "ProcJs.hypot"
        : "Math." + math[name];
  function binding(n, scope) {
    const b = scope.get(n.text);
    if (!b) fail(n, "unknown identifier " + n.text);
    return b;
  }
  function def(scope, key, extra = {}) {
    const name = "v_" + key.replaceAll("$", "_dollar_") + "_" + ++serial;
    scope.set(key, { code: name, ...extra });
    return name;
  }
  function field(n) {
    if (!ts.isIdentifier(n)) fail(n, "expected a property name");
    return n.text;
  }
  function pattern(n, source, scope, info = {}) {
    if (ts.isIdentifier(n)) {
      const name = def(scope, n.text, info);
      write(
        "var " + name + (info.dynamic ? ":Dynamic" : "") + " = " + source + ";",
      );
      return;
    }
    if (ts.isArrayBindingPattern(n)) {
      const v = temp();
      write("var " + v + " = " + arr(source) + ";");
      n.elements.forEach((e, i) => {
        if (ts.isOmittedExpression(e)) return;
        if (e.initializer || e.dotDotDotToken)
          fail(e, "unsupported destructuring default or rest");
        pattern(e.name, v + "[" + i + "]", scope, { dynamic: true });
      });
      return;
    }
    fail(n, "unsupported binding pattern");
  }
  function callback(n, scope) {
    if (n.modifiers?.length || n.asteriskToken)
      fail(n, "expected synchronous function");
    const inner = scoped(scope),
      params = [],
      defaults = [],
      numericArgs = numericParameters(n);
    for (const p of n.parameters) {
      if (p.dotDotDotToken) fail(p, "rest parameters");
      const type = numericArgs.has(p.name.text) ? "Float" : "Dynamic";
      const id = ts.isIdentifier(p.name)
        ? def(inner, p.name.text, { type })
        : temp();
      params.push((p.initializer ? "?" : "") + id + ":" + type);
      if (p.initializer)
        defaults.push(() =>
          write(
            "if (" +
              id +
              " == null) " +
              id +
              " = " +
              expr(p.initializer, inner) +
              ";",
          ),
        );
      if (!ts.isIdentifier(p.name))
        defaults.push(() => pattern(p.name, id, inner));
    }
    function returns(s) {
      return (
        (ts.isReturnStatement(s) && !!s.expression) ||
        (!ts.isFunctionLike(s) && ts.forEachChild(s, returns))
      );
    }
    const hasReturn = !ts.isBlock(n.body) || returns(n.body);
    const start = lines.length,
      outerLoop = loop,
      outerReturn = returned;
    returned = new Set();
    loop = null;
    depth++;
    defaults.forEach((f) => f());
    if (ts.isBlock(n.body)) for (const s of n.body.statements) stat(s, inner);
    else {
      write("return " + expr(n.body, inner) + ";");
      returned.add(kind(n.body, inner));
    }
    depth--;
    loop = outerLoop;
    const result = hasReturn
      ? (returned.size === 1 && [...returned][0]) || "Dynamic"
      : "Void";
    results.set(n, result);
    returned = outerReturn;
    const body = lines.splice(start);
    return (
      "function(" +
      params.join(", ") +
      "):" +
      result +
      " {\n" +
      body.join("\n") +
      "\n" +
      "  ".repeat(depth) +
      "}"
    );
  }
  function mapArray(n, scope, receiver, cb, from = false) {
    const arity = ts.isIdentifier(cb)
      ? binding(cb, scope).arity
      : cb.parameters?.length;
    if (arity === undefined) fail(cb, "array callback needs a known signature");
    const src = temp(),
      fn = temp(),
      out = temp(),
      args = (from ? ["null", "j"] : [src + "[j]", "j", src]).slice(0, arity);
    if (arity > (from ? 2 : 3)) fail(cb, "unsupported callback arity");
    const count = from ? "Std.int(" + src + ".length)" : src + ".length";
    return (
      "({ var " +
      src +
      " = " +
      (from ? receiver : arr(receiver)) +
      "; var " +
      fn +
      " = " +
      expr(cb, scope) +
      "; var " +
      out +
      ":Array<Dynamic> = []; for (j in 0..." +
      count +
      ") " +
      out +
      ".push(" +
      fn +
      "(" +
      args.join(", ") +
      ")); " +
      out +
      "; })"
    );
  }
  function object(n, scope) {
    const v = temp(),
      code = ["var " + v + ":Dynamic = {};"];
    for (const p of n.properties) {
      if (ts.isSpreadAssignment(p)) {
        code.push(
          "ProcJs.assign(" + v + ", " + expr(p.expression, scope) + ");",
        );
        continue;
      }
      if (!ts.isPropertyAssignment(p) && !ts.isShorthandPropertyAssignment(p))
        fail(p, "unsupported object member");
      const key = field(p.name);
      code.push(
        "Reflect.setField(" +
          v +
          ", " +
          JSON.stringify(key) +
          ", " +
          expr(p.initializer ?? p.name, scope) +
          ");",
      );
    }
    return "({ " + code.join(" ") + " " + v + "; })";
  }
  function expr(n, scope) {
    if (ts.isNumericLiteral(n)) {
      const s = String(Number(n.text));
      return /^\d+$/.test(s) ? s + ".0" : s;
    }
    if (ts.isStringLiteral(n)) return JSON.stringify(n.text);
    if (
      n.kind === ts.SyntaxKind.TrueKeyword ||
      n.kind === ts.SyntaxKind.FalseKeyword
    )
      return n.getText();
    if (ts.isIdentifier(n)) return binding(n, scope).code;
    if (ts.isParenthesizedExpression(n))
      return "(" + expr(n.expression, scope) + ")";
    if (ts.isArrayLiteralExpression(n))
      return arr("[" + n.elements.map((e) => expr(e, scope)).join(", ") + "]");
    if (ts.isObjectLiteralExpression(n)) return object(n, scope);
    if (ts.isArrowFunction(n) || ts.isFunctionExpression(n))
      return callback(n, scope);
    if (ts.isNewExpression(n)) {
      const args = (n.arguments ?? []).map((a) => expr(a, scope));
      if (
        ts.isIdentifier(n.expression) &&
        n.expression.text === "Float32Array" &&
        !scope.has("Float32Array") &&
        args.length === 1
      )
        return "new ProcFloats(" + args[0] + ")";
      const name = imported(n.expression, bindings),
        arity = constructors.get(name);
      if (!arity || args.length < arity[0] || args.length > arity[1])
        fail(
          n,
          "unsupported constructor or arguments " + n.expression.getText(),
        );
      return "ProcApi.make(" + [JSON.stringify(name), ...args].join(", ") + ")";
    }
    if (ts.isPropertyAccessExpression(n)) {
      const key = field(n.name),
        symbol = imported(n, bindings);
      if (symbol) {
        if (!Object.hasOwn(constants, symbol))
          fail(n, "unsupported Three constant " + symbol);
        return constants[symbol];
      }
      if (
        n.expression.getText() === "Math" &&
        !scope.has("Math") &&
        Object.hasOwn(math, key)
      )
        return methodMath(key);
      // User-defined record fields are tracked from their object literals.
      if (!apiMembers.has(key) && !recordFields.has(key))
        fail(n, "unsupported property " + key);
      if (
        vector(n.expression, scope) ||
        (ts.isIdentifier(n.expression) &&
          scope.get(n.expression.text)?.numericFields?.has(key))
      )
        return expr(n.expression, scope) + "." + key;
      return "(" + expr(n.expression, scope) + " : Dynamic)." + key;
    }
    if (ts.isElementAccessExpression(n))
      return (
        arr(expr(n.expression, scope)) +
        "[Std.int(" +
        expr(n.argumentExpression, scope) +
        ")]"
      );
    if (ts.isConditionalExpression(n))
      return (
        "(" +
        condition(n.condition, scope) +
        " ? " +
        expr(n.whenTrue, scope) +
        " : " +
        expr(n.whenFalse, scope) +
        ")"
      );
    if (ts.isPrefixUnaryExpression(n) || ts.isPostfixUnaryExpression(n)) {
      const a = expr(n.operand, scope),
        op = ts.tokenToString(n.operator);
      if (op === "!") return "!(" + condition(n.operand, scope) + ")";
      if (op === "-")
        return "(-" + (kind(n.operand, scope) === "Float" ? a : num(a)) + ")";
      if (["++", "--"].includes(op))
        return ts.isPostfixUnaryExpression(n) ? a + op : op + a;
      fail(n, "unsupported unary operator " + op);
    }
    if (ts.isBinaryExpression(n)) {
      const l = expr(n.left, scope),
        r = expr(n.right, scope),
        op = n.operatorToken.getText();
      if (op === "**") return "Math.pow(" + l + ", " + r + ")";
      if (op === ">>>") return "WebBits.shiftUnsigned(" + l + ", " + r + ")";
      if (op === "&&" || op === "||") {
        if (kind(n, scope) === "Bool")
          return "(" + l + " " + op + " " + r + ")";
        const v = temp();
        return (
          "({ var " +
          v +
          ":Dynamic = " +
          l +
          "; ProcJs.truth(" +
          v +
          ") ? " +
          (op === "&&" ? r : v) +
          " : " +
          (op === "&&" ? v : r) +
          "; })"
        );
      }
      if (["===", "!=="].includes(op))
        return "(" + l + (op === "===" ? " == " : " != ") + r + ")";
      if (op === "+" && kind(n, scope) === "String")
        return "(" + l + " + " + r + ")";
      if (["+", "-", "*", "/", "%", "<", "<=", ">", ">="].includes(op))
        return (
          "(" +
          (kind(n.left, scope) === "Float" ? l : num(l)) +
          " " +
          op +
          " " +
          (kind(n.right, scope) === "Float" ? r : num(r)) +
          ")"
        );
      if (["=", "+=", "-=", "*=", "/="].includes(op))
        return l + " " + op + " " + r;
      fail(n, "unsupported binary operator " + op);
    }
    if (ts.isCallExpression(n)) {
      const callee = n.expression,
        args = n.arguments;
      if (ts.isPropertyAccessExpression(callee)) {
        const target = callee.expression,
          name = callee.name.text;
        if (
          target.getText() === "Array" &&
          name === "from" &&
          !scope.has("Array") &&
          args.length === 2 &&
          ts.isObjectLiteralExpression(args[0]) &&
          args[0].properties.length === 1 &&
          args[0].properties[0].name?.text === "length"
        )
          return mapArray(n, scope, expr(args[0], scope), args[1], true);
        if (
          target.getText() === "document.body" &&
          name === "appendChild" &&
          args.length === 1 &&
          ts.isPropertyAccessExpression(args[0]) &&
          args[0].name.text === "domElement"
        )
          return "ProcApi.mount(" + expr(args[0].expression, scope) + ")";
        if (
          target.getText() === "window" &&
          name === "addEventListener" &&
          args.length === 2 &&
          args[0].text === "keydown"
        )
          return "Host.onKey(" + expr(args[1], scope) + ")";
        if (name === "map" && args.length === 1)
          return mapArray(n, scope, expr(target, scope), args[0]);
        if (name === "push") {
          const base = temp(),
            items = args.map((a) => expr(a, scope)),
            values = items.map(() => temp());
          return (
            "({ var " +
            base +
            " = " +
            arr(expr(target, scope)) +
            "; " +
            items
              .map((a, i) => "var " + values[i] + " = " + a + "; ")
              .join("") +
            values.map((a) => base + ".push(" + a + "); ").join("") +
            base +
            ".length; })"
          );
        }
        if (
          name === "set" &&
          args.length === 1 &&
          ts.isSpreadElement(args[0])
        ) {
          const a = temp(),
            b = temp();
          return (
            "({ var " +
            b +
            " = " +
            expr(target, scope) +
            "; var " +
            a +
            " = " +
            arr(expr(args[0].expression, scope)) +
            "; ProcJs.setVector(" +
            b +
            ", " +
            a +
            "); })"
          );
        }
      }
      const actual = args.map((a) => expr(a, scope));
      if (ts.isIdentifier(callee)) {
        const expected = binding(callee, scope).arity;
        while (actual.length < expected) actual.push("null");
      }
      return expr(callee, scope) + "(" + actual.join(", ") + ")";
    }
    fail(n, "unsupported procedural expression " + ts.SyntaxKind[n.kind]);
  }
  function declare(d, scope) {
    if (!d.initializer) fail(d, "expected initialized variable");
    if (
      ts.isObjectBindingPattern(d.name) &&
      d.initializer.getText() === "Math" &&
      !scope.has("Math")
    ) {
      for (const el of d.name.elements) {
        const name = field(el.propertyName ?? el.name);
        if (!Object.hasOwn(math, name)) fail(el, "unknown Math member");
        scope.set(field(el.name), {
          code: methodMath(name),
          result: "Float",
          type: name === "PI" ? "Float" : undefined,
        });
      }
      return;
    }
    const code = expr(d.initializer, scope),
      type = kind(d.initializer, scope),
      vec = vector(d.initializer, scope);
    pattern(d.name, code, scope, {
      type,
      vector: vec,
      result: results.get(d.initializer),
      arity: d.initializer.parameters?.length,
      dynamic:
        !type &&
        !vec &&
        (ts.isElementAccessExpression(d.initializer) ||
          ts.isCallExpression(d.initializer) ||
          ts.isPropertyAccessExpression(d.initializer)),
    });
  }
  // A read-only record used exclusively as numeric operands can be projected
  // once per iteration. HashLink then loads its fields without boxing each access.
  function numericProjection(body, name) {
    const fields = new Set();
    let valid = true;
    function scan(n) {
      if (ts.isFunctionLike(n)) {
        valid = false;
        return;
      }
      if (ts.isIdentifier(n) && n.text === name) {
        const p = n.parent,
          op = p.parent;
        if (
          !ts.isPropertyAccessExpression(p) ||
          p.expression !== n ||
          !ts.isBinaryExpression(op) ||
          !["-", "*", "/", "%", "**", "<", "<=", ">", ">="].includes(
            op.operatorToken.getText(),
          )
        )
          valid = false;
        else fields.add(p.name.text);
      }
      ts.forEachChild(n, scan);
    }
    scan(body);
    return valid && fields.size ? fields : null;
  }
  function stat(n, scope) {
    if (ts.isImportDeclaration(n)) {
      if (n.moduleSpecifier.text !== "three") fail(n, "unresolved module");
      return;
    }
    if (ts.isBlock(n)) {
      const inner = scoped(scope);
      write("{");
      depth++;
      for (const s of n.statements) stat(s, inner);
      depth--;
      write("}");
      return;
    }
    if (ts.isVariableStatement(n)) {
      for (const d of n.declarationList.declarations) declare(d, scope);
      return;
    }
    if (ts.isFunctionDeclaration(n) && n.name) {
      const id = def(scope, n.name.text, { arity: n.parameters.length });
      write(callback(n, scope).replace(/^function\(/, "function " + id + "("));
      scope.get(n.name.text).result = results.get(n);
      return;
    }
    if (ts.isExpressionStatement(n)) {
      write(expr(n.expression, scope) + ";");
      return;
    }
    if (ts.isReturnStatement(n)) {
      if (n.expression) returned.add(kind(n.expression, scope));
      write(
        "return" + (n.expression ? " " + expr(n.expression, scope) : "") + ";",
      );
      return;
    }
    if (ts.isIfStatement(n)) {
      write("if (" + condition(n.expression, scope) + ") {");
      depth++;
      stat(n.thenStatement, scoped(scope));
      depth--;
      write("}");
      if (n.elseStatement) {
        write("else {");
        depth++;
        stat(n.elseStatement, scoped(scope));
        depth--;
        write("}");
      }
      return;
    }
    if (
      ts.isForStatement(n) &&
      ts.isVariableDeclarationList(n.initializer) &&
      n.initializer.declarations.length === 1 &&
      n.condition &&
      n.incrementor
    ) {
      const inner = scoped(scope),
        d = n.initializer.declarations[0];
      if (!ts.isIdentifier(d.name)) fail(d, "expected loop counter");
      write("{");
      depth++;
      declare(d, inner);
      const counter = binding(d.name, inner).code,
        body = scoped(inner),
        local = def(body, d.name.text, { type: inner.get(d.name.text).type });
      write("while (" + condition(n.condition, inner) + ") {");
      depth++;
      write("var " + local + " = " + counter + ";");
      const old = loop;
      loop = counter + " = " + local + "; " + expr(n.incrementor, inner) + ";";
      stat(n.statement, body);
      write(loop);
      loop = old;
      depth--;
      write("}");
      depth--;
      write("}");
      return;
    }
    if (ts.isForOfStatement(n) && ts.isVariableDeclarationList(n.initializer)) {
      const inner = scoped(scope),
        iter = temp(),
        d = n.initializer.declarations[0];
      write("for (" + iter + " in " + arr(expr(n.expression, scope)) + ") {");
      depth++;
      const projection =
        ts.isIdentifier(d.name) && numericProjection(n.statement, d.name.text);
      if (projection) {
        const name = def(inner, d.name.text, { numericFields: projection });
        write(
          "var " +
            name +
            ":{" +
            [...projection].map((k) => "var " + k + ":Float;").join(" ") +
            "} = " +
            iter +
            ";",
        );
      } else pattern(d.name, iter, inner);
      const old = loop;
      loop = "";
      stat(n.statement, inner);
      loop = old;
      depth--;
      write("}");
      return;
    }
    if (ts.isContinueStatement(n) && !n.label && loop !== null) {
      if (loop) write(loop);
      write("continue;");
      return;
    }
    if (ts.isEmptyStatement(n)) return;
    fail(n, "unsupported procedural statement " + ts.SyntaxKind[n.kind]);
  }
  const recordFields = new Set();
  function fields(n) {
    if (ts.isObjectLiteralExpression(n))
      for (const p of n.properties)
        if (p.name && ts.isIdentifier(p.name)) recordFields.add(p.name.text);
    ts.forEachChild(n, fields);
  }
  fields(file);
  for (const s of file.statements) stat(s, root);
  return (
    "import Three;\nimport Host;\nimport ProcJs;\n\nclass Sample {\n  static function main() {\n    Host.init();\n" +
    lines.join("\n") +
    "\n    Host.run();\n  }\n}\n"
  );
}
