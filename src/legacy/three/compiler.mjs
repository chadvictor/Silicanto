import ts from "typescript";
import { scriptBody, legacyClass, modernClass, checkVar } from "./js-forms.mjs";
import { usesProceduralGeometry, emitProcedural } from "./procedural.mjs";
import { parse } from "parse5";

const shapes = {
  Scene: [],
  PerspectiveCamera: ["Float", "Float", "Float", "Float"],
  BoxGeometry: ["Float", "Float", "Float"],
  Mesh: ["BoxGeometry", "MeshBasicMaterial"],
};
const properties = {
  Mesh: { position: "Vec", rotation: "Vec", scale: "Vec" },
  PerspectiveCamera: { position: "Vec" },
  Vec: { x: "Float", y: "Float", z: "Float" },
  Keyboard: { code: "String", repeat: "Bool" },
};
const methods = {
  Scene: { add: ["Mesh"] },
  Vec: { set: ["Float", "Float", "Float"] },
  PerspectiveCamera: { lookAt: ["Float", "Float", "Float"] },
  WebGLRenderer: {
    render: ["Scene", "PerspectiveCamera"],
    setSize: ["Float", "Float"],
  },
};

export function moduleInput(filename, text) {
  if (!filename.endsWith(".html")) return { source: text, offset: 0 };
  const root = parse(text, { sourceCodeLocationInfo: true });
  let module, canvas;
  function walk(node) {
    const attr = Object.fromEntries(
      (node.attrs ?? []).map((a) => [a.name, a.value]),
    );
    if (
      node.tagName &&
      !["html", "head", "body", "title", "meta", "script", "canvas"].includes(
        node.tagName,
      )
    )
      throw Error("E-HTML: unsupported element <" + node.tagName + ">");
    if (Object.keys(attr).some((a) => a.startsWith("on") || a === "style"))
      throw Error("E-HTML: unsupported HTML event or style");
    if (node.tagName === "script" && attr.type === "importmap") {
      const map = JSON.parse(node.childNodes.map((c) => c.value).join(""));
      if (
        Object.keys(map).length !== 1 ||
        !map.imports ||
        Object.keys(map.imports).length !== 1 ||
        !/^(?:\.\.\/)+build\/three\.module\.js$/.test(map.imports.three)
      )
        throw Error("E-IMPORTMAP: expected the upstream Three.js module");
    }
    if (node.tagName === "script" && attr.type !== "importmap") {
      if (attr.type !== "module" || attr.src || module)
        throw Error("E-HTML: expected one inline module");
      module = node.sourceCodeLocation;
    }
    if (node.tagName === "canvas") {
      if (canvas || !attr.id || Object.keys(attr).length !== 1)
        throw Error("E-CANVAS: expected one canvas with an id");
      canvas = "#" + attr.id;
    }
    for (const child of node.childNodes ?? []) walk(child);
  }
  walk(root);
  if (!module?.endTag) throw Error("E-HTML: missing inline module");
  const offset = module.startTag.endOffset;
  return {
    source: text.slice(offset, module.endTag.startOffset),
    offset,
    canvas,
  };
}

export function compile(...args) {
  return compileProject(...args).haxe;
}

export function compileProject(filename, text, loadScene, settings = {}) {
  const {
    source,
    offset,
    canvas = settings.canvas,
  } = moduleInput(filename, text);
  const file = ts.createSourceFile(
    filename.endsWith(".ts") ? "input.ts" : "input.js",
    source,
    ts.ScriptTarget.Latest,
    true,
  );
  function fail(n, msg) {
    const prefix = text.slice(
      0,
      offset + (typeof n === "number" ? n : n.getStart(file)),
    );
    if (settings.location) {
      const loc = settings.location(
        prefix.split("\n").length - 1,
        prefix.length - prefix.lastIndexOf("\n") - 1,
      );
      if (loc) throw Error(loc + " E-SUBSET: " + msg);
    }
    throw Error(
      filename +
        ":" +
        prefix.split("\n").length +
        ":" +
        (prefix.length - prefix.lastIndexOf("\n")) +
        " E-SUBSET: " +
        msg,
    );
  }
  if (file.parseDiagnostics.length) {
    const d = file.parseDiagnostics[0];
    fail(d.start, ts.flattenDiagnosticMessageText(d.messageText, " "));
  }
  if (usesProceduralGeometry(file))
    return { haxe: emitProcedural(file, fail), graphicsHost: true };
  const names = new Map(),
    classes = new Map();
  const script = scriptBody(file);
  if (script.global) names.set(script.global, { type: "HostGlobal" });
  let graphics = false,
    returnContext;
  function annotation(node) {
    if (!node) return undefined;
    const types = {
      number: "Float",
      boolean: "Bool",
      string: "String",
      void: "Void",
    };
    return (
      types[node.getText()] ?? fail(node, "unsupported type " + node.getText())
    );
  }
  let lines = [],
    additions = 0,
    renderers = 0;
  let indent = 2;
  const out = (line) => lines.push("  ".repeat(indent) + line);
  const value = (type, code, writable = false) => ({ type, code, writable });
  function expect(n, v, type) {
    if (v.type !== type && !(type === "Scene" && v.type === "PackedScene"))
      fail(n, "expected " + type + ", found " + v.type);
    return v.code;
  }
  function args(n, nodes, types, scope) {
    if (types.length !== nodes.length)
      fail(n, "expected " + types.length + " arguments");
    return nodes.map((a, i) => expect(a, expr(a, scope), types[i])).join(", ");
  }
  function options(n, scope, allowed) {
    const result = {};
    if (!n) return result;
    if (!ts.isObjectLiteralExpression(n)) fail(n, "expected literal options");
    for (const p of n.properties) {
      if (
        !(ts.isPropertyAssignment(p) || ts.isShorthandPropertyAssignment(p)) ||
        !ts.isIdentifier(p.name)
      )
        fail(p, "unsupported option");
      const key = p.name.text;
      if (!Object.hasOwn(allowed, key) || Object.hasOwn(result, key))
        fail(p, "unsupported or duplicate option " + key);
      result[key] = expect(
        p,
        expr(p.initializer ?? p.name, scope),
        allowed[key],
      );
    }
    return result;
  }
  function expr(n, scope) {
    if (ts.isNumericLiteral(n)) {
      const literal = Number(n.text);
      if (!Number.isFinite(literal)) fail(n, "numeric literal out of range");
      const digits = String(literal);
      return value("Float", /^[0-9]+$/.test(digits) ? digits + ".0" : digits);
    }
    if (ts.isStringLiteral(n)) return value("String", JSON.stringify(n.text));
    if (
      n.kind === ts.SyntaxKind.TrueKeyword ||
      n.kind === ts.SyntaxKind.FalseKeyword
    )
      return value("Bool", n.getText());
    if (ts.isParenthesizedExpression(n)) {
      const v = expr(n.expression, scope);
      return { ...v, code: "(" + v.code + ")" };
    }
    if (n.kind === ts.SyntaxKind.ThisKeyword && scope.has("this"))
      return scope.get("this");
    if (ts.isIdentifier(n)) {
      const v = scope.get(n.text);
      if (v?.type === "CapturedLocal")
        fail(n, "class method captures a module-local binding");
      if (v?.classType || v?.type === "HostGlobal")
        fail(
          n,
          "unsupported use of a class or host global as a first-class value",
        );
      if (v) return v;
      fail(n, "unknown identifier " + n.text);
    }
    if (ts.isArrayLiteralExpression(n)) {
      const items = n.elements.map((item) => expr(item, scope));
      const type = items[0]?.type ?? "Float";
      if (!["String", "Float", "Bool"].includes(type))
        fail(n, "unsupported array element type");
      return value(
        "Array<" + type + ">",
        "[" +
          items.map((it, i) => expect(n.elements[i], it, type)).join(", ") +
          "]",
      );
    }
    if (ts.isConditionalExpression(n)) {
      const condition = expect(n.condition, expr(n.condition, scope), "Bool");
      const yes = expr(n.whenTrue, scope),
        no = expr(n.whenFalse, scope);
      return value(
        yes.type,
        "(" +
          condition +
          " ? " +
          yes.code +
          " : " +
          expect(n.whenFalse, no, yes.type) +
          ")",
      );
    }
    if (ts.isElementAccessExpression(n)) {
      const base = expr(n.expression, scope);
      const index = expect(
        n.argumentExpression,
        expr(n.argumentExpression, scope),
        "Float",
      );
      if (base.type.startsWith("Array<"))
        return value(
          base.type.slice(6, -1),
          "WebArray.read(" + base.code + ", " + index + ")",
        );
      if (base.type !== "WebFloat32")
        fail(n, "numeric index on unsupported receiver");
      return value("Float", base.code + ".read(" + index + ")");
    }
    if (ts.isNewExpression(n)) {
      const ident = n.expression,
        params = n.arguments ?? [];
      if (
        ts.isIdentifier(ident) &&
        ident.text === "Float32Array" &&
        !scope.has(ident.text)
      ) {
        if (params.length > 1) fail(n, "unsupported typed-array view");
        const arg = params.length
          ? expr(params[0], scope)
          : value("Float", "0.0");
        return value(
          "WebFloat32",
          arg.type === "Array<Float>"
            ? "WebFloat32.fromArray(" + arg.code + ")"
            : "new WebFloat32(" + expect(n, arg, "Float") + ")",
        );
      }
      const local = ts.isIdentifier(ident) && scope.get(ident.text);
      if (local?.classType) {
        const info = classes.get(local.classType);
        const ctor = info.ctor?.emit();
        info.instantiated = true;
        return value(
          local.classType,
          "new " +
            local.classType +
            "(" +
            args(n, params, ctor?.parameters ?? [], scope) +
            ")",
        );
      }
      graphics = true;
      const ctor =
        ts.isPropertyAccessExpression(ident) &&
        ts.isIdentifier(ident.expression) &&
        scope.get(ident.expression.text)?.type === "namespace"
          ? ident.name.text
          : ts.isIdentifier(ident) && scope.get(ident.text)?.ctor;
      if (ctor === "ObjectLoader" && !params.length)
        return value("ObjectLoader", "");
      if (ctor === "WebGLRenderer") {
        if (++renderers > 1)
          fail(n, "the first Metal profile supports one renderer");
        if (params.length > 1) fail(n, "renderer options");
        const o = options(params[0], scope, {
          canvas: "Canvas",
          antialias: "Bool",
        });
        return value(
          ctor,
          "new WebGLRenderer(" + (o.antialias ?? "false") + ")",
        );
      }
      if (ctor === "MeshBasicMaterial") {
        if (params.length > 1) fail(n, "material options");
        const o = options(params[0], scope, { color: "Float" });
        return value(
          ctor,
          "new MeshBasicMaterial(" + (o.color ?? "16777215.0") + ")",
        );
      }
      if (!Object.hasOwn(shapes, ctor))
        fail(n, "unsupported constructor " + ident.getText());
      const a = args(n, params, shapes[ctor], scope);
      return value(ctor, "new " + ctor + "(" + a + ")");
    }
    if (ts.isPropertyAccessExpression(n)) {
      if (
        ts.isIdentifier(n.expression) &&
        !scope.has(n.expression.text) &&
        n.expression.text === "window"
      ) {
        if (["innerWidth", "innerHeight"].includes(n.name.text)) {
          graphics = true;
          return value("Float", "Host." + n.name.text);
        }
      }
      if (
        ts.isIdentifier(n.expression) &&
        !scope.has(n.expression.text) &&
        n.expression.text === "Math" &&
        n.name.text === "PI"
      )
        return value("Float", "Math.PI");
      const base = expr(n.expression, scope);
      if (
        (base.type.startsWith("Array<") || base.type === "WebFloat32") &&
        n.name.text === "length"
      )
        return value("Float", "(1.0 * " + base.code + ".length)");
      const own = classes.get(base.type)?.fields.get(n.name.text);
      if (own) return value(own, base.code + ".p_" + n.name.text, true);
      const type = properties[base.type]?.[n.name.text];
      if (!type) fail(n, "unsupported property " + n.getText());
      return value(type, base.code + "." + n.name.text, base.type === "Vec");
    }
    if (
      ts.isPostfixUnaryExpression(n) ||
      (ts.isPrefixUnaryExpression(n) &&
        [ts.SyntaxKind.PlusPlusToken, ts.SyntaxKind.MinusMinusToken].includes(
          n.operator,
        ))
    ) {
      const operand = expr(n.operand, scope);
      if (!operand.writable || operand.type !== "Float")
        fail(n, "expected writable number");
      const op = n.operator === ts.SyntaxKind.PlusPlusToken ? "++" : "--";
      return value(
        "Float",
        ts.isPostfixUnaryExpression(n) ? operand.code + op : op + operand.code,
      );
    }
    if (ts.isPrefixUnaryExpression(n)) {
      const v = expr(n.operand, scope);
      if (n.operator === ts.SyntaxKind.ExclamationToken)
        return value("Bool", "!" + expect(n, v, "Bool"));
      if (n.operator === ts.SyntaxKind.MinusToken)
        return value("Float", "-" + expect(n, v, "Float"));
      fail(n, "unsupported prefix operator");
    }
    if (ts.isBinaryExpression(n)) {
      if (
        n.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
        ts.isPropertyAccessExpression(n.left) &&
        n.left.expression.kind === ts.SyntaxKind.ThisKeyword &&
        scope.has("this")
      ) {
        const receiver = scope.get("this"),
          info = classes.get(receiver.type),
          field = n.left.name.text;
        const rhs = expr(n.right, scope);
        if (!info.fields.has(field)) {
          if (!receiver.initializing)
            fail(
              n.left,
              "new instance fields must be initialized in the constructor",
            );
          info.fields.set(field, rhs.type);
        }
        return value(
          rhs.type,
          "this.p_" + field + " = " + expect(n, rhs, info.fields.get(field)),
        );
      }
      if (
        n.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
        ts.isElementAccessExpression(n.left)
      ) {
        const base = expr(n.left.expression, scope);
        if (base.type !== "WebFloat32")
          fail(n, "unsupported indexed assignment");
        const index = expect(
          n.left,
          expr(n.left.argumentExpression, scope),
          "Float",
        );
        return value(
          "Float",
          base.code +
            ".write(" +
            index +
            ", " +
            expect(n, expr(n.right, scope), "Float") +
            ")",
        );
      }
      const a = expr(n.left, scope),
        b = expr(n.right, scope),
        op = n.operatorToken.getText();
      if (op === ">>>")
        return value(
          "Float",
          "WebBits.shiftUnsigned(" +
            expect(n, a, "Float") +
            ", " +
            expect(n, b, "Float") +
            ")",
        );
      if (op === "|")
        return value(
          "Float",
          "(1.0 * (WebBits.signed(" +
            expect(n, a, "Float") +
            ") | WebBits.signed(" +
            expect(n, b, "Float") +
            ")))",
        );
      if (["+", "-", "*", "/", "%"].includes(op))
        return value(
          "Float",
          "(" +
            expect(n, a, "Float") +
            " " +
            op +
            " " +
            expect(n, b, "Float") +
            ")",
        );
      if (["<", "<=", ">", ">="].includes(op))
        return value(
          "Bool",
          "(" +
            expect(n, a, "Float") +
            " " +
            op +
            " " +
            expect(n, b, "Float") +
            ")",
        );
      if (op === "&&" || op === "||")
        return value(
          "Bool",
          "(" +
            expect(n, a, "Bool") +
            " " +
            op +
            " " +
            expect(n, b, "Bool") +
            ")",
        );
      if (
        ["===", "!=="].includes(op) &&
        ["String", "Bool", "Float"].includes(a.type)
      )
        return value(
          "Bool",
          "(" +
            a.code +
            (op === "===" ? " == " : " != ") +
            expect(n, b, a.type) +
            ")",
        );
      if (
        ["=", "+=", "*=", "-=", "/="].includes(op) &&
        a.writable &&
        (op === "=" || a.type === "Float")
      )
        return value(a.type, a.code + " " + op + " " + expect(n, b, a.type));
      fail(n, "unsupported operation " + op);
    }
    if (ts.isArrowFunction(n) || ts.isFunctionExpression(n))
      return callback(n, scope);
    if (ts.isCallExpression(n)) {
      const target = n.expression,
        params = n.arguments;
      if (ts.isIdentifier(target)) {
        if (
          target.text === "requestAnimationFrame" &&
          !scope.has(target.text)
        ) {
          graphics = true;
          return value(
            "Void",
            "Host.requestFrame(" + args(n, params, ["Frame"], scope) + ")",
          );
        }
        const fn = scope.get(target.text);
        if (fn?.parameters)
          return value(
            fn.result,
            fn.code + "(" + args(n, params, fn.parameters, scope) + ")",
          );
        if (!fn || !["Frame", "Action"].includes(fn.type))
          fail(n, "unknown function " + target.text);
        return value(
          "Void",
          fn.code +
            "(" +
            args(n, params, fn.type === "Frame" ? ["Float"] : [], scope) +
            ")",
        );
      }
      if (ts.isPropertyAccessExpression(target)) {
        const obj = target.expression,
          method = target.name.text;
        if (
          ts.isIdentifier(obj) &&
          obj.text === "Math" &&
          !scope.has("Math") &&
          method === "imul"
        )
          return value(
            "Float",
            "WebBits.imul(" + args(n, params, ["Float", "Float"], scope) + ")",
          );
        const owner = ts.isIdentifier(obj) && scope.get(obj.text)?.classType;
        if (owner) {
          const member = classes.get(owner).statics.get(method)?.emit();
          if (!member) fail(target, "unsupported static method " + method);
          return value(
            member.result,
            owner +
              ".s_" +
              method +
              "(" +
              args(n, params, member.parameters, scope) +
              ")",
          );
        }
        const hostConsole =
          ts.isPropertyAccessExpression(obj) &&
          obj.name.text === "console" &&
          ts.isIdentifier(obj.expression) &&
          scope.get(obj.expression.text)?.type === "HostGlobal";
        if (hostConsole || (ts.isIdentifier(obj) && !scope.has(obj.text))) {
          if (["window", "document"].includes(obj.text)) graphics = true;
          if (
            (hostConsole || obj.text === "console") &&
            method === "log" &&
            params.length === 1
          ) {
            const item = expr(params[0], scope);
            if (!["Float", "String", "Bool"].includes(item.type))
              fail(n, "console.log expects one primitive");
            return value("Void", "WebConsole.log(" + item.code + ")");
          }
        }
        if (
          ts.isIdentifier(obj) &&
          !scope.has(obj.text) &&
          obj.text === "document" &&
          method === "querySelector" &&
          params.length === 1 &&
          ts.isStringLiteral(params[0]) &&
          canvas &&
          params[0].text === canvas
        )
          return value("Canvas", "true");
        if (
          ts.isIdentifier(obj) &&
          obj.text === "window" &&
          !scope.has("window") &&
          method === "addEventListener" &&
          params.length === 2 &&
          ts.isStringLiteral(params[0]) &&
          params[0].text === "keydown" &&
          ts.isArrowFunction(params[1])
        ) {
          return value(
            "Void",
            "Host.onKey(" + callback(params[1], scope, "KeyHandler").code + ")",
          );
        }
        if (
          obj.getText() === "document.body" &&
          !scope.has("document") &&
          method === "appendChild" &&
          params.length === 1 &&
          ts.isPropertyAccessExpression(params[0]) &&
          params[0].name.text === "domElement"
        ) {
          expect(n, expr(params[0].expression, scope), "WebGLRenderer");
          return value("Void", "Host.mount()");
        }
        if (
          ts.isIdentifier(obj) &&
          obj.text === "Math" &&
          !scope.has("Math") &&
          [
            "sin",
            "cos",
            "tan",
            "sqrt",
            "abs",
            "exp",
            "log",
            "max",
            "min",
            "pow",
            "atan2",
            "floor",
            "ceil",
          ].includes(method)
        ) {
          return value(
            "Float",
            "Math." +
              ({ floor: "ffloor", ceil: "fceil" }[method] ?? method) +
              "(" +
              args(
                n,
                params,
                ["max", "min", "pow", "atan2"].includes(method)
                  ? ["Float", "Float"]
                  : ["Float"],
                scope,
              ) +
              ")",
          );
        }
        const base = expr(obj, scope),
          signature = methods[base.type]?.[method];
        const member = classes.get(base.type)?.methods.get(method)?.emit();
        if (member)
          return value(
            member.result,
            base.code +
              ".m_" +
              method +
              "(" +
              args(n, params, member.parameters, scope) +
              ")",
          );
        if (
          base.type === "WebFloat32" &&
          method === "set" &&
          (params.length === 1 || params.length === 2)
        ) {
          const values = expect(
            params[0],
            expr(params[0], scope),
            "Array<Float>",
          );
          const offset =
            params.length === 2
              ? expect(params[1], expr(params[1], scope), "Float")
              : "0.0";
          return value(
            "Void",
            base.code + ".set(" + values + ", " + offset + ")",
          );
        }
        if (
          base.type.startsWith("Array<") &&
          method === "push" &&
          params.length === 1
        ) {
          return value(
            "Float",
            "(1.0 * " +
              base.code +
              ".push(" +
              expect(n, expr(params[0], scope), base.type.slice(6, -1)) +
              "))",
          );
        }
        if (
          base.type === "ObjectLoader" &&
          method === "parse" &&
          params.length === 1
        ) {
          const id = expect(n, expr(params[0], scope), "SceneJSON");
          return value("PackedScene", "Scene.fromAsset(" + id + ")");
        }
        if (base.type === "Scene" && method === "add" && ++additions > 1)
          fail(n, "the initial Metal profile supports one opaque mesh");
        if (signature)
          return value(
            "Void",
            base.code +
              "." +
              method +
              "(" +
              args(n, params, signature, scope) +
              ")",
          );
        if (
          base.type === "WebGLRenderer" &&
          method === "setAnimationLoop" &&
          params.length === 1
        ) {
          const f = expr(params[0], scope);
          if (f.type === "Frame") return value("Void", "Host.loop = " + f.code);
          if (f.type === "Action")
            return value("Void", "Host.loop = function(_) (" + f.code + ")()");
        }
      }
      fail(n, "unsupported call " + target.getText());
    }
    fail(n, "unsupported " + ts.SyntaxKind[n.kind]);
  }
  function callback(n, scope, kind) {
    if (n.modifiers?.length || n.asteriskToken || n.name)
      fail(n, "expected a synchronous anonymous function");
    if (kind === "KeyHandler" && n.parameters.length !== 1)
      fail(n, "expected one keyboard event");
    const inner = new Map(scope);
    const types = n.parameters.map((p) => {
      if (!ts.isIdentifier(p.name) || p.initializer || p.dotDotDotToken)
        fail(p, "unsupported callback parameter");
      const type =
        kind === "KeyHandler" ? "Keyboard" : (annotation(p.type) ?? "Float");
      inner.set(p.name.text, value(type, "v_" + p.name.text, true));
      return type;
    });
    const previous = returnContext,
      saved = lines;
    returnContext = { expected: annotation(n.type), observed: null };
    lines = [];
    indent++;
    if (ts.isBlock(n.body)) {
      for (const s of n.body.statements) statement(s, inner);
    } else {
      const item = expr(n.body, inner);
      out((item.type === "Void" ? "" : "return ") + item.code + ";");
      returnContext.observed = item.type;
    }
    indent--;
    const result = returnContext.expected ?? returnContext.observed ?? "Void";
    const body = lines.join("\n");
    lines = saved;
    returnContext = previous;
    const type =
      kind ??
      (result === "Void" && types.length === 0
        ? "Action"
        : result === "Void" && types.length === 1 && types[0] === "Float"
          ? "Frame"
          : "Callable");
    const args = n.parameters
      .map((p, i) => "v_" + p.name.text + ":" + types[i])
      .join(", ");
    return {
      ...value(
        type,
        "function(" +
          args +
          "):" +
          result +
          " {\n" +
          body +
          "\n" +
          "  ".repeat(indent) +
          "}",
      ),
      parameters: types,
      result,
    };
  }
  function classDeclaration(
    node,
    name,
    scope,
    definitions = modernClass(node, fail),
  ) {
    if (scope !== names)
      fail(node, "local class declarations require closure conversion");
    const id = "JsClass_" + name;
    if (scope.has(name)) fail(node, "class redeclaration");
    const info = {
      id,
      fields: new Map(),
      methods: new Map(),
      statics: new Map(),
      bodies: [],
      instantiated: false,
    };
    classes.set(id, info);
    scope.set(name, { classType: id });
    for (const { name: field, fn, isStatic } of definitions) {
      const ctor = field === null;
      let signature,
        emitting = false;
      // Method bodies are inert until called. Resolve their result from the
      // body on first use, including calls to methods declared later.
      const descriptor = {
        emit() {
          if (signature) return signature;
          if (emitting)
            fail(fn, "recursive method needs an explicit result type");
          emitting = true;
          const inner = new Map(
            [...names].map(([key, v]) => [
              key,
              v.classType || v.type === "HostGlobal"
                ? v
                : { type: "CapturedLocal" },
            ]),
          );
          if (!isStatic)
            inner.set("this", { ...value(id, "this"), initializing: ctor });
          const types = fn.parameters.map((p) => {
            if (!ts.isIdentifier(p.name) || p.initializer || p.dotDotDotToken)
              fail(p, "unsupported method parameter");
            const type = annotation(p.type) ?? "Float";
            inner.set(p.name.text, value(type, "v_" + p.name.text, true));
            return type;
          });
          const expected = ctor ? "Void" : annotation(fn.type);
          if (expected) signature = { parameters: types, result: expected };
          const previous = { lines, indent, returnContext };
          lines = [];
          indent = 2;
          returnContext = { expected, observed: null };
          for (const stmt of fn.body.statements) statement(stmt, inner);
          const result = expected ?? returnContext.observed ?? "Void";
          const params = fn.parameters
            .map((p, i) => "v_" + p.name.text + ":" + types[i])
            .join(", ");
          const head = ctor
            ? "new(" + params + ")"
            : (isStatic ? "s_" : "m_") + field + "(" + params + "):" + result;
          info.bodies.push(
            "  public " +
              (isStatic ? "static " : "") +
              "function " +
              head +
              " {\n" +
              lines.join("\n") +
              "\n  }",
          );
          ({ lines, indent, returnContext } = previous);
          signature = { parameters: types, result };
          return signature;
        },
      };
      if (ctor) info.ctor = descriptor;
      else {
        const members = isStatic ? info.statics : info.methods;
        if (members.has(field)) fail(fn, "method redefinition");
        members.set(field, descriptor);
      }
    }
  }
  function statement(n, scope) {
    if (ts.isClassDeclaration(n) && n.name)
      return classDeclaration(n, n.name.text, scope);
    if (ts.isImportDeclaration(n)) {
      const clause = n.importClause,
        binding = clause?.namedBindings;
      if (
        clause?.name &&
        !binding &&
        /^\.\.?\/.*\.json$/.test(n.moduleSpecifier.text) &&
        n.attributes?.elements.some(
          (a) => a.name.text === "type" && a.value.text === "json",
        )
      ) {
        graphics = true;
        if (!loadScene) fail(n, "a scene asset resolver is required");
        scope.set(
          clause.name.text,
          value("SceneJSON", JSON.stringify(loadScene(n.moduleSpecifier.text))),
        );
        return;
      }
      if (
        n.moduleSpecifier.text !== "three" ||
        !binding ||
        clause.name ||
        clause.isTypeOnly
      )
        fail(n, "only imports from three are supported");
      if (ts.isNamespaceImport(binding))
        scope.set(binding.name.text, { type: "namespace" });
      else
        for (const el of binding.elements)
          scope.set(el.name.text, {
            type: "constructor",
            ctor: (el.propertyName ?? el.name).text,
          });
    } else if (ts.isVariableStatement(n)) {
      if (
        !(n.declarationList.flags & ts.NodeFlags.BlockScoped) &&
        !(settings.bundled && n.parent === file)
      )
        for (const d of n.declarationList.declarations) checkVar(d, fail);
      for (const d of n.declarationList.declarations) {
        if (!ts.isIdentifier(d.name) || !d.initializer)
          fail(d, "expected initialized variable");
        if (ts.isClassExpression(d.initializer)) {
          classDeclaration(d.initializer, d.name.text, scope);
          continue;
        }
        const v = expr(d.initializer, scope),
          symbol = "v_" + d.name.text;
        if (
          ![
            "Float",
            "Bool",
            "String",
            "Canvas",
            "PackedScene",
            "WebFloat32",
            ...Object.keys(shapes),
            "MeshBasicMaterial",
            "WebGLRenderer",
          ].includes(v.type) &&
          !v.parameters &&
          !classes.has(v.type) &&
          !v.type.startsWith("Array<")
        )
          fail(d, "unsupported binding type");
        scope.set(d.name.text, {
          ...v,
          code: symbol,
          writable: !(n.declarationList.flags & ts.NodeFlags.Const),
        });
        out(
          "var " +
            symbol +
            ":" +
            (v.parameters
              ? "(" + v.parameters.join(",") + ")->" + v.result
              : v.type === "Canvas"
                ? "Bool"
                : v.type === "PackedScene"
                  ? "Scene"
                  : v.type) +
            " = " +
            v.code +
            ";",
        );
      }
    } else if (ts.isFunctionDeclaration(n)) {
      if (!n.name || !n.body || n.asteriskToken || n.modifiers?.length)
        fail(n, "unsupported function signature");
      const inner = new Map(scope),
        id = "v_" + n.name.text;
      const types = n.parameters.map((p) => {
        if (!ts.isIdentifier(p.name) || p.initializer || p.dotDotDotToken)
          fail(p, "unsupported parameter");
        const type = annotation(p.type) ?? "Float";
        inner.set(p.name.text, value(type, "v_" + p.name.text, true));
        return type;
      });
      const binding = {
        ...value("Callable", id),
        parameters: types,
        result: annotation(n.type) ?? "Void",
      };
      if (
        binding.result === "Void" &&
        types.length === 1 &&
        types[0] === "Float"
      )
        binding.type = "Frame";
      scope.set(n.name.text, binding);
      inner.set(n.name.text, binding);
      const outer = returnContext;
      returnContext = { expected: annotation(n.type), observed: null };
      const start = lines.length;
      out("");
      indent++;
      for (const stmt of n.body.statements) statement(stmt, inner);
      indent--;
      binding.result =
        returnContext.expected ?? returnContext.observed ?? "Void";
      returnContext = outer;
      binding.type = "Callable";
      if (binding.result === "Void") {
        if (!types.length) binding.type = "Action";
        if (types.length === 1 && types[0] === "Float") binding.type = "Frame";
      }
      lines[start] =
        "  ".repeat(indent) +
        "function " +
        id +
        "(" +
        n.parameters
          .map((p, i) => "v_" + p.name.text + ":" + types[i])
          .join(", ") +
        "):" +
        binding.result +
        " {";
      out("}");
    } else if (ts.isReturnStatement(n)) {
      if (!returnContext) fail(n, "return outside a translated function");
      const item = n.expression ? expr(n.expression, scope) : value("Void", "");
      expect(
        n,
        item,
        returnContext.expected ?? returnContext.observed ?? item.type,
      );
      returnContext.observed = item.type;
      out(n.expression ? "return " + item.code + ";" : "return;");
    } else if (ts.isForStatement(n)) {
      if (
        !n.initializer ||
        !ts.isVariableDeclarationList(n.initializer) ||
        n.initializer.declarations.length !== 1 ||
        !(n.initializer.flags & ts.NodeFlags.Let) ||
        !n.condition ||
        !n.incrementor
      )
        fail(n, "expected a for loop with a let counter, condition and update");
      const d = n.initializer.declarations[0],
        inner = new Map(scope);
      if (!ts.isIdentifier(d.name) || !d.initializer)
        fail(d, "expected initialized counter");
      const counter = "v_" + d.name.text;
      out("{");
      indent++;
      out(
        "var " +
          counter +
          ":Float = " +
          expect(d, expr(d.initializer, scope), "Float") +
          ";",
      );
      inner.set(d.name.text, value("Float", counter, true));
      // A closure over a JS for-let counter requires a fresh binding per iteration.
      function checkLoop(node) {
        if (ts.isFunctionLike(node))
          fail(node, "closures inside for-let loops are not yet supported");
        ts.forEachChild(node, checkLoop);
      }
      checkLoop(n.statement);
      out(
        "while (" +
          expect(n.condition, expr(n.condition, inner), "Bool") +
          ") {",
      );
      indent++;
      statement(n.statement, new Map(inner));
      out(expr(n.incrementor, inner).code + ";");
      indent--;
      out("}");
      indent--;
      out("}");
    } else if (ts.isForOfStatement(n)) {
      const iterable = expr(n.expression, scope),
        decl = n.initializer.declarations?.[0];
      if (
        n.awaitModifier ||
        !iterable.type.startsWith("Array<") ||
        !decl ||
        !ts.isIdentifier(decl.name) ||
        !(n.initializer.flags & ts.NodeFlags.BlockScoped) ||
        n.initializer.declarations.length !== 1
      )
        fail(n, "expected for-of over an array");
      const inner = new Map(scope),
        id = "v_" + decl.name.text;
      inner.set(
        decl.name.text,
        value(
          iterable.type.slice(6, -1),
          id,
          !(n.initializer.flags & ts.NodeFlags.Const),
        ),
      );
      out("for (" + id + " in " + iterable.code + ") {");
      indent++;
      statement(n.statement, inner);
      indent--;
      out("}");
    } else if (ts.isWhileStatement(n)) {
      out(
        "while (" +
          expect(n.expression, expr(n.expression, scope), "Bool") +
          ") {",
      );
      indent++;
      statement(n.statement, new Map(scope));
      indent--;
      out("}");
    } else if (ts.isIfStatement(n)) {
      out(
        "if (" +
          expect(n.expression, expr(n.expression, scope), "Bool") +
          ") {",
      );
      indent++;
      statement(n.thenStatement, new Map(scope));
      indent--;
      out("}");
      if (n.elseStatement) {
        out("else {");
        indent++;
        statement(n.elseStatement, new Map(scope));
        indent--;
        out("}");
      }
    } else if (ts.isBlock(n)) {
      const inner = new Map(scope);
      out("{");
      indent++;
      for (const item of n.statements) statement(item, inner);
      indent--;
      out("}");
    } else if (ts.isExpressionStatement(n)) {
      out(expr(n.expression, scope).code + ";");
    } else if (ts.isEmptyStatement(n)) {
      return;
    } else fail(n, "unsupported statement " + ts.SyntaxKind[n.kind]);
  }
  for (let i = 0; i < script.statements.length; ) {
    const legacy = legacyClass(script.statements, i);
    if (legacy) {
      classDeclaration(
        script.statements[i],
        legacy.name,
        names,
        legacy.members,
      );
      i = legacy.next;
    } else statement(script.statements[i++], names);
  }
  const classSources = [];
  for (const info of classes.values()) {
    if (!info.bodies.length && !info.instantiated) continue;
    const fields = [...info.fields].map(
      ([field, type]) => "  public var p_" + field + ":" + type + ";",
    );
    if (info.instantiated && !info.ctor)
      fields.push("  public function new() {}");
    classSources.push(
      "private class " +
        info.id +
        " {\n" +
        [...fields, ...info.bodies].join("\n") +
        "\n}\n",
    );
  }
  const haxe =
    (graphics ? "import Three;\nimport Host;\n\n" : "") +
    "class Sample {\n  static function main() {\n" +
    (graphics ? "    Host.init();\n" : "") +
    lines.join("\n") +
    (graphics ? "\n    Host.run();" : "") +
    "\n  }\n}\n" +
    classSources.join("\n");
  return { haxe, graphicsHost: graphics };
}
