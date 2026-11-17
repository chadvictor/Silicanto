import ts from "typescript";

const K = ts.SyntaxKind;
const quoted = (s) => JSON.stringify(String(s));
const numericOps = new Set(["-", "*", "/", "%"]);
const bitOps = new Set(["&", "|", "^", "<<", ">>"]);

export function emitModule(graph, module, file, units, globals, lowered = {}) {
  const frames = [],
    loopUpdates = [];
  let next = 0;
  const fresh = (name) =>
    "j_" + name.replace(/[^a-zA-Z0-9_]/g, "_") + "_" + next++;
  function strictDirective(statements) {
    for (const statement of statements ?? []) {
      if (
        !ts.isExpressionStatement(statement) ||
        !ts.isStringLiteral(statement.expression)
      )
        break;
      if (
        statement.expression.getText(file) === '"use strict"' ||
        statement.expression.getText(file) === "'use strict'"
      )
        return true;
    }
    return false;
  }
  const scope = (parent = null) => ({
    strict:
      parent?.strict ??
      (module.format === "esm" || strictDirective(file.statements)),
    parent,
    selfOwner: parent?.selfOwner,
    names: new Map(),
    self:
      parent?.self ??
      (module.format === "cjs"
        ? "exports"
        : module.format === "classic"
          ? "Js.realm"
          : "Js.u"),
  });
  const root = scope(),
    initial = [],
    imports = [],
    exports = [],
    hoisted = [],
    preamble = [];
  // Only functions with a direct eval in their lexical subtree need a runtime
  // environment. Each getter closes over one binding, even in large modules.
  const evalOwners = new Set();
  if (/\beval\b/.test(file.text)) {
    function mark(node) {
      if (
        ts.isCallExpression(node) &&
        ts.isIdentifier(node.expression) &&
        node.expression.text === "eval"
      )
        for (let p = node.parent; p; p = p.parent)
          if (ts.isFunctionLike(p)) evalOwners.add(p);
      ts.forEachChild(node, mark);
    }
    mark(file);
  }
  if (evalOwners.size && module.format !== "classic") {
    root.evalEnv = fresh("environment");
    initial.push(
      "var " + root.evalEnv + " = new JsEvalScope(JsEval.globalRead);",
    );
  }
  const position = (n) => {
    const loc = file.getLineAndCharacterOfPosition(n.getStart(file));
    const original = lowered.map?.findEntry(loc.line, loc.character);
    return original?.originalLine == null
      ? loc
      : { line: original.originalLine, character: original.originalColumn };
  };
  const fail = (node, msg) => {
    const { line, character } = position(node);
    throw Error(
      `${module.id}:${line + 1 + module.line}:${character + 1} E-JAVASCRIPT: ${msg}`,
    );
  };
  const block = (lines) => "{\n" + lines.filter(Boolean).join("\n") + "\n}";
  const statementList = (list, s) =>
    list.map((n) => stmt(n, s)).filter(Boolean);
  const plainName = (n) =>
    ts.isIdentifier(n) || ts.isStringLiteral(n) || ts.isNumericLiteral(n)
      ? n.text
      : fail(n, "expected a property name");
  function capture(owner) {
    for (const f of frames) {
      let local = false;
      for (let p = owner; p; p = p.parent) {
        if (p === f.scope) {
          local = true;
          break;
        }
      }
      if (!local) f.closed = false;
    }
  }
  function find(s, name) {
    for (let p = s; p; p = p.parent) {
      const v = p.names.get(name);
      if (v) {
        capture(p);
        return v;
      }
    }
  }
  function define(s, name, init, lines, mutable = true, lex = false) {
    if (s.names.has(name)) return s.names.get(name);
    const id = fresh(name),
      sym = {
        id,
        read: lex ? "Js.binding(" + id + "," + quoted(name) + ")" : id,
        mutable,
      };
    s.names.set(name, sym);
    lines.push("var " + id + ":Dynamic = " + init + ";");
    if (s.evalEnv && s !== root)
      lines.push(
        s.evalEnv +
          ".add(" +
          quoted(name) +
          ",function():Dynamic return " +
          sym.read +
          ");",
      );
    return sym;
  }
  function bindingNames(n) {
    if (ts.isIdentifier(n)) return [n.text];
    if (ts.isBindingPattern(n))
      return n.elements
        .filter((e) => !ts.isOmittedExpression(e))
        .flatMap((e) => bindingNames(e.name));
    fail(n, "unsupported binding target");
  }
  function bindPattern(n, source, s) {
    if (ts.isIdentifier(n)) return find(s, n.text).id + " = " + source + ";";
    const id = fresh("unpack"),
      lines = ["var " + id + ":Dynamic = " + source + ";"];
    n.elements.forEach((e, i) => {
      if (ts.isOmittedExpression(e)) return;
      const array = ts.isArrayBindingPattern(n);
      if (e.dotDotDotToken && !array) fail(e, "object rest binding");
      const key = array
        ? String(i)
        : ts.isComputedPropertyName(e.propertyName ?? {})
          ? expr(e.propertyName.expression, s)
          : quoted(plainName(e.propertyName ?? e.name));
      let read = e.dotDotDotToken
        ? "Js.items(" + id + ").slice(" + i + ")"
        : "Js.get(" + id + "," + key + ")";
      if (e.initializer)
        read = sequence(
          [read],
          ([v]) =>
            "(" +
            v +
            " == Js.u ? (" +
            expr(e.initializer, s) +
            ":Dynamic) : " +
            v +
            ")",
          true,
        );
      lines.push(bindPattern(e.name, read, s));
    });
    return block(lines);
  }
  function collectVars(nodes, s, lines) {
    function visit(n) {
      if (ts.isFunctionLike(n) || ts.isClassLike(n)) return;
      if (
        ts.isVariableDeclarationList(n) &&
        !(n.flags & ts.NodeFlags.BlockScoped)
      )
        for (const d of n.declarations)
          for (const name of bindingNames(d.name))
            define(s, name, "Js.u", lines);
      ts.forEachChild(n, visit);
    }
    nodes.forEach(visit);
  }
  function declareList(nodes, s, lines) {
    for (const n of nodes) {
      if (ts.isFunctionDeclaration(n) && n.name)
        define(s, n.name.text, "Js.u", lines);
      if (ts.isClassDeclaration(n) && n.name)
        define(s, n.name.text, "Js.tdz", lines, true, true);
      if (
        ts.isVariableStatement(n) &&
        n.declarationList.flags & ts.NodeFlags.BlockScoped
      )
        for (const d of n.declarationList.declarations)
          for (const name of bindingNames(d.name))
            define(
              s,
              name,
              "Js.tdz",
              lines,
              !(n.declarationList.flags & ts.NodeFlags.Const),
              true,
            );
    }
  }
  function hoistFunctions(nodes, s, lines) {
    for (const n of nodes)
      if (ts.isFunctionDeclaration(n) && n.name)
        lines.push(find(s, n.name.text).id + " = " + func(n, s) + ";");
  }
  function nested(nodes, parent) {
    const s = scope(parent),
      lines = [];
    declareList(nodes, s, lines);
    hoistFunctions(nodes, s, lines);
    return block([...lines, ...statementList(nodes, s)]);
  }
  function func(n, outer, constructor = null) {
    if (n.asteriskToken || n.modifiers?.some((m) => m.kind === K.AsyncKeyword))
      fail(n, "unsupported generator or async function form");
    const s = scope(outer),
      lines = [],
      self = fresh("this"),
      args = fresh("args");
    const frame = { scope: s, closed: true };
    frames.push(frame);
    if (evalOwners.has(n)) {
      s.evalEnv = fresh("environment");
      lines.push(
        "var " + s.evalEnv + " = new JsEvalScope(" + evalLookup(outer) + ");",
      );
    }
    const arrow = ts.isArrowFunction(n);
    s.strict =
      outer.strict ||
      ts.isClassLike(n.parent) ||
      strictDirective(n.body?.statements);
    if (!s.strict && !arrow)
      lines.push(
        "if (" +
          self +
          " == Js.u || " +
          self +
          " == null) " +
          self +
          " = Js.realm;",
      );
    if (constructor) s.constructorInfo = constructor;
    s.self = arrow ? outer.self : self;
    s.selfOwner = arrow ? outer.selfOwner : s;
    if (!arrow) {
      s.names.set("arguments", { id: args, read: args, mutable: false });
      if (s.evalEnv)
        lines.push(
          s.evalEnv +
            '.add("arguments",function():Dynamic return ' +
            args +
            ");",
        );
    }
    for (const [i, p] of n.parameters.entries()) {
      if (!ts.isIdentifier(p.name)) {
        for (const name of bindingNames(p.name))
          define(s, name, "Js.tdz", lines, true, true);
        const arg = fresh("parameter");
        lines.push("var " + arg + ":Dynamic = Js.at(" + args + "," + i + ");");
        if (p.initializer)
          lines.push(
            "if (" +
              arg +
              " == Js.u) " +
              arg +
              " = " +
              expr(p.initializer, s) +
              ";",
          );
        lines.push(bindPattern(p.name, arg, s));
        continue;
      }
      const v = define(
        s,
        plainName(p.name),
        p.dotDotDotToken
          ? args + ".slice(" + i + ")"
          : "Js.at(" + args + "," + i + ")",
        lines,
      );
      if (p.initializer)
        lines.push(
          "if (" +
            v.id +
            " == Js.u) " +
            v.id +
            " = " +
            expr(p.initializer, s) +
            ";",
        );
    }
    if (ts.isBlock(n.body)) {
      if (constructor && !constructor.base)
        lines.push(...constructor.init(self, s));
      collectVars(n.body.statements, s, lines);
      declareList(n.body.statements, s, lines);
      hoistFunctions(n.body.statements, s, lines);
      lines.push(...statementList(n.body.statements, s));
      if (!ts.isReturnStatement(n.body.statements.at(-1) ?? {}))
        lines.push("return Js.u;");
    } else lines.push("return " + expr(n.body, s) + ";");
    frames.pop();
    const code =
      "Js.fn(function(" +
      self +
      ":Dynamic," +
      args +
      ":Array<Dynamic>):Dynamic " +
      block(lines) +
      "," +
      (!arrow && !ts.isMethodDeclaration(n)) +
      ")";
    if (frame.closed && file.text.length > 64000 && code.length > 96)
      return (
        units.method("", "JsObject", block(["return " + code + ";"])) + "()"
      );
    return code;
  }
  function dependency(n, specifier) {
    const edge = module.edges.find((e) => e.request === specifier);
    if (!edge || !graph.byId.has(edge.to))
      fail(n, "unresolved dependency " + specifier);
    return graph.byId.get(edge.to);
  }
  const load = (m) => "JsModule" + m.index + ".load()";
  function wire(n) {
    const spec = n.moduleSpecifier?.text;
    if (!spec) return;
    const m = dependency(n, spec),
      v = fresh("import"),
      ref = (k) =>
        k === "default" && m.format !== "esm"
          ? v
          : "Js.get(" + v + "," + quoted(k) + ")";
    const alias = (id, read) => root.names.set(id, { read, mutable: false });
    initial.push("var " + v + ":Dynamic = Js.tdz;");
    imports.push(v + " = " + load(m) + ";");
    if (ts.isImportDeclaration(n)) {
      const c = n.importClause;
      if (c?.name) alias(c.name.text, ref("default"));
      if (c?.namedBindings) {
        if (ts.isNamespaceImport(c.namedBindings))
          alias(c.namedBindings.name.text, v);
        else
          for (const e of c.namedBindings.elements)
            alias(e.name.text, ref((e.propertyName ?? e.name).text));
      }
    } else if (n.exportClause && ts.isNamedExports(n.exportClause)) {
      for (const e of n.exportClause.elements)
        expose(e.name.text, ref((e.propertyName ?? e.name).text));
    } else fail(n, "star re-exports require namespace linking");
  }
  function expose(key, read) {
    exports.push(
      "Js.expose(exports," +
        quoted(key) +
        ",function():Dynamic return " +
        read +
        ");",
    );
  }
  if (module.format === "cjs") {
    root.names.set("exports", {
      id: "exports",
      read: "exports",
      mutable: true,
    });
    root.names.set("module", { id: "module", read: "module", mutable: true });
  }
  for (const n of file.statements)
    if (ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) wire(n);
  collectVars(file.statements, root, initial);
  declareList(file.statements, root, initial);
  for (const n of file.statements) {
    if (
      ts.isExportDeclaration(n) &&
      !n.moduleSpecifier &&
      n.exportClause &&
      ts.isNamedExports(n.exportClause)
    )
      for (const e of n.exportClause.elements)
        expose(e.name.text, identifier(e.propertyName ?? e.name, root));
    if (n.modifiers?.some((m) => m.kind === K.ExportKeyword)) {
      if ((ts.isFunctionDeclaration(n) || ts.isClassDeclaration(n)) && n.name)
        expose(
          n.modifiers.some((m) => m.kind === K.DefaultKeyword)
            ? "default"
            : n.name.text,
          find(root, n.name.text).read,
        );
      if (ts.isVariableStatement(n))
        for (const d of n.declarationList.declarations)
          expose(plainName(d.name), find(root, plainName(d.name)).read);
    }
  }
  hoistFunctions(file.statements, root, hoisted);
  function identifier(n, s) {
    const sym = find(s, n.text);
    if (sym) return sym.read;
    if (n.text === "undefined") return "Js.u";
    if (n.text === "NaN") return "Math.NaN";
    if (n.text === "Infinity") return "Math.POSITIVE_INFINITY";
    globals.add(n.text);
    return "Js.global(" + quoted(n.text) + ")";
  }
  function evalLookup(s) {
    const cases = [];
    const seen = new Set();
    let fallback = "JsEval.globalRead";
    for (let p = s; p; p = p.parent) {
      if (p.evalEnv) {
        capture(p);
        fallback = p.evalEnv + ".read";
        break;
      }
      for (const [name, sym] of p.names) {
        if (seen.has(name)) continue;
        seen.add(name);
        if (
          p === root &&
          module.format === "classic" &&
          (!lowered.identifiers || lowered.identifiers.has(name))
        )
          continue;
        capture(p);
        cases.push("case " + quoted(name) + ": " + sym.read + ";");
      }
    }
    if (!cases.length) return fallback;
    return (
      "function(name:String, typeOnly:Bool):Dynamic { var v:Dynamic = switch name {" +
      cases.join("\n") +
      "default: return " +
      fallback +
      "(name,typeOnly); }; return typeOnly ? Js.type(v) : v; }"
    );
  }
  function sequence(values, finish, save = false) {
    // No expression can change another operand if they are all local reads/literals.
    if (
      values.length === 0 ||
      (!save &&
        values.every((v) =>
          /^(?:j_\w+|"(?:[^"\\]|\\.)*"|-?[\d.eE+-]+|true|false|null|Js\.u)$/.test(
            v,
          ),
        ))
    )
      return finish(values);
    const ids = values.map(() => fresh("value"));
    return block([
      ...values.map((v, i) => "var " + ids[i] + ":Dynamic = " + v + ";"),
      finish(ids) + ";",
    ]);
  }
  function access(n, s) {
    if (ts.isPropertyAccessExpression(n))
      return [expr(n.expression, s), quoted(n.name.text)];
    if (ts.isElementAccessExpression(n))
      return [expr(n.expression, s), expr(n.argumentExpression, s)];
  }
  function assign(n, s, convert, post = false) {
    const perform = (get, write) =>
      typeof post === "string"
        ? sequence(
            [get],
            ([v]) => {
              const when =
                post === "??="
                  ? v + "==null || " + v + "==Js.u"
                  : (post === "||=" ? "!" : "") + "Js.truth(" + v + ")";
              return (
                "(" +
                when +
                " ? (" +
                write(convert(v)) +
                ":Dynamic) : " +
                v +
                ")"
              );
            },
            true,
          )
        : post
          ? sequence(
              [get],
              ([old]) => block([write(convert(old)) + ";", old + ";"]),
              true,
            )
          : write(convert(get));
    if (ts.isIdentifier(n)) {
      const v = find(s, n.text);
      if (!v) {
        globals.add(n.text);
        return perform(
          "Js.global(" + quoted(n.text) + ")",
          (x) =>
            "Js.assignGlobal(" +
            quoted(n.text) +
            "," +
            x +
            "," +
            !s.strict +
            ")",
        );
      }
      if (!v.mutable)
        return perform(v.read, (x) => "Js.constantWrite(" + x + ")");
      return perform(v.read, (x) => v.id + " = " + x);
    }
    const a = access(n, s);
    if (!a) fail(n, "unsupported assignment target");
    return sequence(a, ([o, k]) =>
      perform(
        "Js.get(" + o + "," + k + ")",
        (x) => "Js.put(" + o + "," + k + "," + x + ")",
      ),
    );
  }
  function op(token, x, y) {
    if (numericOps.has(token))
      return "(Js.num(" + x + ") " + token + " Js.num(" + y + "))";
    if (bitOps.has(token))
      return (
        "(WebBits.signed(Js.num(" +
        x +
        ")) " +
        token +
        " WebBits.signed(Js.num(" +
        y +
        ")))"
      );
    const funcs = {
      "+": "add",
      "===": "equal",
      "!==": "equal",
      "==": "loose",
      "!=": "loose",
      "<": "less",
      ">": "less",
      "<=": "lessEqual",
      ">=": "lessEqual",
    };
    if (funcs[token]) {
      if ([">", ">="].includes(token)) [x, y] = [y, x];
      return (
        (token.startsWith("!") ? "!" : "") +
        "Js." +
        funcs[token] +
        "(" +
        x +
        "," +
        y +
        ")"
      );
    }
    if (token === ">>>")
      return "WebBits.shiftUnsigned(Js.num(" + x + "),Js.num(" + y + "))";
    if (token === "**") return "Math.pow(Js.num(" + x + "),Js.num(" + y + "))";
    throw Error("E-JAVASCRIPT: unsupported operator " + token);
  }
  function argumentArray(args, s) {
    const id = fresh("argv"),
      lines = ["var " + id + ":Array<Dynamic> = [];"];
    for (const a of args)
      lines.push(
        ts.isSpreadElement(a)
          ? "for (v in Js.items(" +
              expr(a.expression, s) +
              ")) " +
              id +
              ".push(v);"
          : id + ".push(" + expr(a, s) + ");",
      );
    return block([...lines, id + ";"]);
  }
  function expr(n, s) {
    if (!n) throw Error("E-JAVASCRIPT: missing AST expression");
    if (n.questionDotToken)
      fail(n, "optional chaining requires a short-circuiting reference");
    if (ts.isIdentifier(n)) return identifier(n, s);
    if (ts.isClassExpression(n)) return classValue(n, s);
    if (n.kind === K.RegularExpressionLiteral) {
      const raw = n.getText(file),
        slash = raw.lastIndexOf("/");
      return (
        "new JsPattern(" +
        quoted(raw.slice(1, slash)) +
        "," +
        quoted(raw.slice(slash + 1)) +
        ")"
      );
    }
    if (ts.isTemplateExpression(n)) {
      let v = quoted(n.head.text);
      for (const span of n.templateSpans)
        v +=
          " + Js.str(" +
          expr(span.expression, s) +
          ") + " +
          quoted(span.literal.text);
      return "(" + v + ")";
    }
    if (ts.isStringLiteralLike(n)) {
      // Class-file UTF-8 constants are limited to 65535 bytes. Join at runtime
      // so javac cannot fold adjacent literal chunks back into one constant.
      if (n.text.length <= 12000) return quoted(n.text);
      const chunks = n.text.match(/[\s\S]{1,12000}/gu) ?? [];
      return "[" + chunks.map(quoted).join(",") + '].join("")';
    }
    if (ts.isNumericLiteral(n))
      return /^\d+$/.test(String(+n.text))
        ? String(+n.text) + ".0"
        : String(+n.text);
    if (n.kind === K.TrueKeyword) return "true";
    if (n.kind === K.FalseKeyword) return "false";
    if (n.kind === K.NullKeyword) return "null";
    if (n.kind === K.ThisKeyword) {
      capture(s.selfOwner ?? root);
      return s.self;
    }
    if (
      ts.isParenthesizedExpression(n) ||
      ts.isAsExpression(n) ||
      ts.isNonNullExpression(n)
    )
      return expr(n.expression, s);
    if (
      ts.isArrayLiteralExpression(n) &&
      n.elements.length > 128 &&
      n.elements.every(
        (e) =>
          ts.isNumericLiteral(e) ||
          ts.isStringLiteral(e) ||
          e.kind === K.NullKeyword,
      )
    ) {
      const parts = [];
      for (let i = 0; i < n.elements.length; i += 128) {
        const lines = n.elements
          .slice(i, i + 128)
          .map((e) => "out.push(" + expr(e, s) + ");");
        parts.push(
          units.method("out:Array<Dynamic>", "Void", block(lines)) + "(out);",
        );
      }
      return block(["var out:Array<Dynamic> = [];", ...parts, "out;"]);
    }
    if (ts.isArrayLiteralExpression(n) && n.elements.some(ts.isSpreadElement))
      return argumentArray(n.elements, s);
    if (ts.isArrayLiteralExpression(n))
      return sequence(
        n.elements.map((e) => expr(e, s)),
        (vs) => "([" + vs.join(",") + "]:Array<Dynamic>)",
      );
    if (ts.isObjectLiteralExpression(n)) {
      const o = fresh("object"),
        lines = ["var " + o + " = Js.obj();"];
      for (const p of n.properties) {
        if (ts.isSpreadAssignment(p)) {
          lines.push(
            "JsProperties.copy(" + o + "," + expr(p.expression, s) + ");",
          );
          continue;
        }
        const k = ts.isComputedPropertyName(p.name ?? {})
          ? expr(p.name.expression, s)
          : plainName(p.name ?? p);
        const key = ts.isComputedPropertyName(p.name ?? {}) ? k : quoted(k);
        let val;
        if (ts.isGetAccessorDeclaration(p) || ts.isSetAccessorDeclaration(p)) {
          lines.push(
            "JsProperties.accessor(" +
              o +
              "," +
              key +
              "," +
              quoted(ts.isGetAccessorDeclaration(p) ? "get" : "set") +
              "," +
              func(p, s) +
              ");",
          );
          continue;
        }
        if (ts.isPropertyAssignment(p)) val = expr(p.initializer, s);
        else if (ts.isShorthandPropertyAssignment(p))
          val = identifier(p.name, s);
        else if (ts.isMethodDeclaration(p)) val = func(p, s);
        else fail(p, "unsupported object member");
        lines.push("Js.put(" + o + "," + key + "," + val + ");");
      }
      if (
        lines.length > 150 &&
        lines
          .slice(1)
          .every((line) =>
            /^Js\.put\(j_object_\d+,"[^"]+",JsUnit\d+_\d+\.part\d+\(\)\);$/.test(
              line,
            ),
          )
      ) {
        const chunks = [];
        for (let i = 1; i < lines.length; i += 64)
          chunks.push(
            units.method(
              o + ":JsObject",
              "Void",
              block(lines.slice(i, i + 64)),
            ) +
              "(" +
              o +
              ");",
          );
        return block([lines[0], ...chunks, o + ";"]);
      }
      return block([...lines, o + ";"]);
    }
    if (ts.isFunctionExpression(n) || ts.isArrowFunction(n)) {
      if (n.name) {
        const inner = scope(s),
          lines = [],
          f = define(inner, n.name.text, "Js.u", lines, false);
        return block([
          ...lines,
          f.id + " = " + func(n, inner) + ";",
          f.id + ";",
        ]);
      }
      return func(n, s);
    }
    const member = access(n, s);
    if (member)
      return ts.isPropertyAccessExpression(n)
        ? "Js.get(" + member.join(",") + ")"
        : sequence(member, ([o, k]) => "Js.get(" + o + "," + k + ")");
    if (
      ts.isCallExpression(n) &&
      (ts.isPropertyAccessExpression(n.expression) ||
        ts.isElementAccessExpression(n.expression)) &&
      n.expression.expression.kind === K.SuperKeyword
    ) {
      let p = s;
      while (p && !p.superInfo) p = p.parent;
      if (!p) fail(n, "super outside a method");
      capture(p);
      const { base, isStatic } = p.superInfo,
        member = n.expression;
      const key = ts.isPropertyAccessExpression(member)
        ? quoted(member.name.text)
        : expr(member.argumentExpression, s);
      return sequence(
        [
          "Js.get(" +
            (isStatic ? base : "Js.get(" + base + ',"prototype")') +
            "," +
            key +
            ")",
          ...n.arguments.map((a) => expr(a, s)),
        ],
        ([f, ...args]) => "Js.call(" + f + "," + s.self + ",[" + args + "])",
      );
    }
    if (ts.isCallExpression(n) && n.expression.kind === K.SuperKeyword) {
      let p = s;
      while (p && !p.constructorInfo) p = p.parent;
      const c = p?.constructorInfo;
      if (!c?.base) fail(n, "super outside a derived constructor");
      capture(c.owner);
      return block([
        "Js.call(" +
          c.base +
          "," +
          s.self +
          ",[" +
          n.arguments.map((a) => expr(a, s)) +
          "]);",
        ...c.init(s.self, s),
        s.self + ";",
      ]);
    }
    if (ts.isNewExpression(n) || ts.isCallExpression(n)) {
      if (
        ts.isCallExpression(n) &&
        ts.isIdentifier(n.expression) &&
        n.expression.text === "require" &&
        !find(s, "require")
      ) {
        if (n.arguments.length !== 1 || !ts.isStringLiteralLike(n.arguments[0]))
          fail(n, "computed require needs a finite dependency set");
        return load(dependency(n, n.arguments[0].text));
      }
      if (
        ts.isCallExpression(n) &&
        ts.isIdentifier(n.expression) &&
        n.expression.text === "eval"
      ) {
        capture(s.selfOwner ?? root);
        const args = n.arguments.some(ts.isSpreadElement)
          ? argumentArray(n.arguments, s)
          : sequence(
              n.arguments.map((arg) => expr(arg, s)),
              (values) => "[" + values + "]",
            );
        return sequence(
          [identifier(n.expression, s), args],
          ([fn, actual]) =>
            "JsEval.direct(" +
            fn +
            "," +
            actual +
            "," +
            evalLookup(s) +
            "," +
            s.self +
            ")",
          true,
        );
      }
      const variadic = n.arguments?.some(ts.isSpreadElement);
      const args = variadic ? [] : (n.arguments ?? []).map((a) => expr(a, s));
      const pos = position(n);
      const site = quoted(
        module.id +
          ":" +
          (pos.line + 1 + module.line) +
          ":" +
          (pos.character + 1) +
          " " +
          n.expression.getText(file).slice(0, 80),
      );
      const invoke = (f, self) =>
        variadic
          ? ts.isNewExpression(n)
            ? "Js.construct(" +
              f +
              "," +
              argumentArray(n.arguments, s) +
              "," +
              site +
              ")"
            : "Js.call(" +
              f +
              "," +
              self +
              "," +
              argumentArray(n.arguments, s) +
              "," +
              site +
              ")"
          : sequence(args, (as) =>
              ts.isNewExpression(n)
                ? "Js.construct(" + f + ",[" + as + "]," + site + ")"
                : "Js.call(" + f + "," + self + ",[" + as + "]," + site + ")",
            );
      const m = !ts.isNewExpression(n) && access(n.expression, s);
      if (m)
        return sequence(
          m,
          ([o, k]) =>
            sequence(
              ["Js.get(" + o + "," + k + ")"],
              ([f]) => invoke(f, o),
              true,
            ),
          true,
        );
      return sequence(
        [expr(n.expression, s)],
        ([f]) => invoke(f, "Js.u"),
        true,
      );
    }
    if (ts.isConditionalExpression(n))
      return (
        "(Js.truth(" +
        expr(n.condition, s) +
        ") ? (" +
        expr(n.whenTrue, s) +
        ":Dynamic) : (" +
        expr(n.whenFalse, s) +
        ":Dynamic))"
      );
    if (ts.isTypeOfExpression(n))
      return ts.isIdentifier(n.expression) && !find(s, n.expression.text)
        ? "Js.globalType(" + quoted(n.expression.text) + ")"
        : "Js.type(" + expr(n.expression, s) + ")";
    if (ts.isDeleteExpression(n)) {
      const m = access(n.expression, s);
      if (!m) fail(n, "delete requires a property");
      return sequence(m, ([o, k]) => "Js.remove(" + o + "," + k + ")");
    }
    if (ts.isVoidExpression(n))
      return block([expr(n.expression, s) + ";", "Js.u;"]);
    if (ts.isPrefixUnaryExpression(n) || ts.isPostfixUnaryExpression(n)) {
      const t = ts.tokenToString(n.operator);
      if (t === "++" || t === "--")
        return assign(
          n.operand,
          s,
          (x) => "(Js.num(" + x + ")" + (t === "++" ? "+" : "-") + "1.0)",
          ts.isPostfixUnaryExpression(n),
        );
      const v = expr(n.operand, s);
      if (t === "!") return "!Js.truth(" + v + ")";
      if (t === "~") return "~WebBits.signed(Js.num(" + v + "))";
      if (t === "-" || t === "+")
        return (t === "-" ? "-" : "") + "Js.num(" + v + ")";
    }
    if (ts.isBinaryExpression(n)) {
      const t = n.operatorToken.getText(file),
        y = expr(n.right, s);
      if (t === "=") return assign(n.left, s, () => y);
      if (["??=", "||=", "&&="].includes(t))
        return assign(n.left, s, () => y, t);
      if (
        n.operatorToken.kind >= K.FirstCompoundAssignment &&
        n.operatorToken.kind <= K.LastCompoundAssignment
      )
        return assign(n.left, s, (x) =>
          sequence([x, y], ([a, b]) => op(t.slice(0, -1), a, b)),
        );
      const x = expr(n.left, s);
      if (t === "&&" || t === "||" || t === "??")
        return sequence([x], ([v]) => {
          const test =
            t === "??"
              ? v + "==null || " + v + "==Js.u"
              : (t === "||" ? "!" : "") + "Js.truth(" + v + ")";
          return "(" + test + " ? (" + y + ":Dynamic) : " + v + ")";
        });
      if (t === "in")
        return sequence([x, y], ([k, o]) => "Js.has(" + o + "," + k + ")");
      if (t === "instanceof")
        return sequence([x, y], ([o, f]) => "Js.instance(" + o + "," + f + ")");
      if (t === ",") return block([x + ";", y + ";"]);
      return sequence([x, y], ([a, b]) => op(t, a, b));
    }
    fail(n, "unsupported expression " + K[n.kind]);
  }
  function classValue(n, s) {
    const parent = n.heritageClauses?.find((c) => c.token === K.ExtendsKeyword)
      ?.types[0]?.expression;
    const base = fresh("base"),
      ctor = fresh("class"),
      proto = fresh("prototype"),
      lines = [];
    if (parent)
      lines.push("var " + base + ":Dynamic = " + expr(parent, s) + ";");
    const c = n.members.find(ts.isConstructorDeclaration);
    const fields = n.members.filter(
      (m) =>
        ts.isPropertyDeclaration(m) &&
        !m.modifiers?.some((x) => x.kind === K.StaticKeyword),
    );
    const inner = scope(s);
    inner.self = "receiver";
    const init = (receiver, sx) =>
      fields.map(
        (m) =>
          "Js.put(" +
          receiver +
          "," +
          quoted(plainName(m.name)) +
          "," +
          (m.initializer ? expr(m.initializer, sx) : "Js.u") +
          ");",
      );
    // Derived constructors capture the generated base reference, even without a JS identifier for it.
    if (
      c &&
      parent &&
      !c.body.statements.some(
        (stmt) =>
          ts.isExpressionStatement(stmt) &&
          ts.isCallExpression(stmt.expression) &&
          stmt.expression.expression.kind === K.SuperKeyword,
      )
    )
      fail(c, "derived constructor needs a direct super call");
    const constructor = c
      ? func(c, s, { base: parent ? base : null, init, owner: s })
      : "Js.fn(function(receiver:Dynamic,args:Array<Dynamic>):Dynamic " +
        block([
          parent ? "Js.call(" + base + ",receiver,args);" : "",
          ...init("receiver", inner),
          "return Js.u;",
        ]) +
        ",true)";
    lines.push("var " + ctor + ":JsObject = " + constructor + ";");
    if (parent) lines.push(ctor + ".prototype = " + base + ";");
    lines.push("var " + proto + ":JsObject = " + ctor + '.read("prototype");');
    if (parent)
      lines.push(proto + ".prototype = Js.get(" + base + ',"prototype");');
    for (const m of n.members) {
      if (m === c || fields.includes(m) || m.kind === K.SemicolonClassElement)
        continue;
      if (m.name && ts.isComputedPropertyName(m.name))
        fail(m, "computed class member");
      const isStatic = m.modifiers?.some((x) => x.kind === K.StaticKeyword);
      const methodScope = scope(s);
      if (parent) methodScope.superInfo = { base, isStatic };
      if (ts.isMethodDeclaration(m))
        lines.push(
          (isStatic ? ctor : proto) +
            ".values.set(" +
            quoted(plainName(m.name)) +
            "," +
            func(m, methodScope) +
            ");",
        );
      else if (ts.isPropertyDeclaration(m) && isStatic)
        lines.push(
          "Js.put(" +
            ctor +
            "," +
            quoted(plainName(m.name)) +
            "," +
            (m.initializer ? expr(m.initializer, s) : "Js.u") +
            ");",
        );
      else fail(m, "unsupported class member " + K[m.kind]);
    }
    return block([...lines, ctor + ";"]);
  }
  function initialize(list, s) {
    return list.declarations
      .map((d) => {
        if (!ts.isIdentifier(d.name))
          return bindPattern(d.name, expr(d.initializer, s), s);
        const name = plainName(d.name),
          v = find(s, name);
        if (!v) fail(d, "missing declaration " + name);
        return d.initializer
          ? v.id + " = " + expr(d.initializer, s) + ";"
          : list.flags & ts.NodeFlags.BlockScoped
            ? v.id + " = Js.u;"
            : "";
      })
      .join("\n");
  }

  function loop(n, s, update, code) {
    loopUpdates.push(update);
    try {
      return code();
    } finally {
      loopUpdates.pop();
    }
  }
  function stmt(n, s) {
    if (
      ts.isImportDeclaration(n) ||
      ts.isExportDeclaration(n) ||
      ts.isFunctionDeclaration(n) ||
      ts.isEmptyStatement(n) ||
      ts.isInterfaceDeclaration(n) ||
      ts.isTypeAliasDeclaration(n)
    )
      return "";
    if (ts.isClassDeclaration(n)) {
      if (!n.name) fail(n, "anonymous class declaration");
      return find(s, n.name.text).id + " = " + classValue(n, s) + ";";
    }
    if (ts.isVariableStatement(n)) return initialize(n.declarationList, s);
    if (ts.isExportAssignment(n))
      return 'Js.put(exports,"default",' + expr(n.expression, s) + ");";
    if (ts.isBlock(n)) return nested(n.statements, s);
    if (ts.isExpressionStatement(n)) return expr(n.expression, s) + ";";
    if (ts.isDebuggerStatement(n)) return "";
    if (ts.isReturnStatement(n))
      return "return " + (n.expression ? expr(n.expression, s) : "Js.u") + ";";
    if (ts.isThrowStatement(n)) return "throw " + expr(n.expression, s) + ";";
    if (ts.isIfStatement(n))
      return (
        "if (Js.truth(" +
        expr(n.expression, s) +
        ")) " +
        block([stmt(n.thenStatement, s)]) +
        (n.elseStatement ? " else " + block([stmt(n.elseStatement, s)]) : "")
      );
    if (ts.isWhileStatement(n) || ts.isDoStatement(n))
      return loop(n, s, "", () => {
        const body = block([stmt(n.statement, s)]),
          test = "(Js.truth(" + expr(n.expression, s) + "))";
        return ts.isWhileStatement(n)
          ? "while " + test + " " + body
          : "do " + body + " while " + test + ";";
      });
    if (ts.isLabeledStatement(n)) {
      const name = quoted(n.label.text);
      return (
        "try " +
        block([stmt(n.statement, s)]) +
        " catch (jump:JsBreak) { if (jump.label != " +
        name +
        ") throw jump; }"
      );
    }
    if (ts.isTryStatement(n)) {
      let body = stmt(n.tryBlock, s);
      const clause = n.catchClause;
      if (clause) {
        const inner = scope(s),
          error = fresh("error"),
          catchBody = [];
        if (clause.variableDeclaration)
          define(
            inner,
            plainName(clause.variableDeclaration.name),
            error,
            catchBody,
          );
        body =
          "try " +
          body +
          " catch (jump:JsBreak) { throw jump; } catch (" +
          error +
          ":Dynamic) " +
          block([...catchBody, stmt(clause.block, inner)]);
      }
      if (!n.finallyBlock) return body;
      // Reject nonlocal returns and jumps until we can unwind their completion
      // records. A thrown value is saved and rethrown after one finalizer.
      function crosses(node) {
        if (ts.isFunctionLike(node)) return false;
        if (
          ts.isReturnStatement(node) ||
          ts.isBreakStatement(node) ||
          ts.isContinueStatement(node)
        )
          return true;
        return ts.forEachChild(node, crosses);
      }
      if (crosses(n.tryBlock) || (clause && crosses(clause.block)))
        fail(n, "nonlocal control flow across finally");
      const pending = fresh("pending"),
        value = fresh("thrown"),
        caught = fresh("caught");
      return block([
        "var " + pending + " = false;",
        "var " + value + ":Dynamic = null;",
        "try " +
          block([body]) +
          " catch (" +
          caught +
          ":Dynamic) { " +
          pending +
          " = true; " +
          value +
          " = " +
          caught +
          "; }",
        stmt(n.finallyBlock, s),
        "if (" + pending + ") throw " + value + ";",
      ]);
    }
    if (ts.isForInStatement(n) || ts.isForOfStatement(n)) {
      const local = scope(s),
        key = fresh("item"),
        lines = [];
      if (ts.isVariableDeclarationList(n.initializer)) {
        const pattern = n.initializer.declarations[0].name;
        if (n.initializer.flags & ts.NodeFlags.BlockScoped)
          for (const name of bindingNames(pattern))
            define(
              local,
              name,
              "Js.tdz",
              lines,
              !(n.initializer.flags & ts.NodeFlags.Const),
              true,
            );
        lines.push(bindPattern(pattern, key, local));
      } else lines.push(assign(n.initializer, local, () => key) + ";");
      return (
        "for (" +
        key +
        " in Js." +
        (ts.isForInStatement(n) ? "keys" : "items") +
        "(" +
        expr(n.expression, s) +
        ")) " +
        loop(n, local, "", () => block([...lines, stmt(n.statement, local)]))
      );
    }
    if (ts.isSwitchStatement(n)) {
      const subject = fresh("switch"),
        start = fresh("case"),
        clauses = n.caseBlock.clauses,
        lines = [
          "var " + subject + ":Dynamic = " + expr(n.expression, s) + ";",
          "var " + start + " = -1;",
        ];
      let fallback = clauses.length;
      clauses.forEach((c, i) => {
        if (ts.isDefaultClause(c)) fallback = i;
        else
          lines.push(
            "if (" +
              start +
              " < 0 && Js.equal(" +
              subject +
              "," +
              expr(c.expression, s) +
              ")) " +
              start +
              " = " +
              i +
              ";",
          );
      });
      lines.push("if (" + start + " < 0) " + start + " = " + fallback + ";");
      const body = clauses.map(
        (c, i) =>
          "if (" +
          start +
          " <= " +
          i +
          ") " +
          block(statementList(c.statements, s)),
      );
      return block([...lines, "do " + block(body) + " while (false);"]);
    }
    if (ts.isForStatement(n)) {
      const inner = scope(s),
        lines = [];
      if (n.initializer && ts.isVariableDeclarationList(n.initializer)) {
        if (n.initializer.flags & ts.NodeFlags.BlockScoped)
          for (const d of n.initializer.declarations)
            for (const name of bindingNames(d.name))
              define(
                inner,
                name,
                "Js.tdz",
                lines,
                !(n.initializer.flags & ts.NodeFlags.Const),
                true,
              );
        lines.push(initialize(n.initializer, inner));
      } else if (n.initializer) lines.push(expr(n.initializer, inner) + ";");
      const update = n.incrementor ? expr(n.incrementor, inner) + ";" : "";
      return block([
        ...lines,
        "while (" +
          (n.condition
            ? "Js.truth(" + expr(n.condition, inner) + ")"
            : "true") +
          ") " +
          loop(n, inner, update, () =>
            block([stmt(n.statement, inner), update]),
          ),
      ]);
    }
    if (ts.isBreakStatement(n) || ts.isContinueStatement(n)) {
      if (n.label) {
        if (ts.isContinueStatement(n)) fail(n, "labeled continue");
        return "throw new JsBreak(" + quoted(n.label.text) + ");";
      }
      return ts.isBreakStatement(n)
        ? "break;"
        : block([loopUpdates.at(-1), "continue;"]);
    }
    fail(n, "unsupported statement " + K[n.kind]);
  }
  if (module.format === "classic") {
    for (const [name, sym] of root.names) {
      if (lowered.identifiers && !lowered.identifiers.has(name)) continue;
      const getter = "function():Dynamic return " + sym.read;
      if (sym.read === sym.id) {
        preamble.push(
          "Js.linkGlobal(" +
            quoted(name) +
            "," +
            getter +
            ",function(value:Dynamic) { " +
            sym.id +
            " = value; });",
        );
      } else
        preamble.push(
          "Js.lexical(" +
            quoted(name) +
            "," +
            getter +
            (sym.mutable
              ? ",function(value:Dynamic) { " + sym.id + " = value; }"
              : "") +
            ");",
        );
    }
  }
  if (root.evalEnv) {
    for (const [name, sym] of root.names) {
      preamble.push(
        root.evalEnv +
          ".add(" +
          quoted(name) +
          ",function():Dynamic return " +
          sym.read +
          ");",
      );
    }
  }
  return [
    ...initial,
    ...preamble,
    ...exports,
    ...hoisted,
    ...imports,
    ...statementList(file.statements, root),
  ].join("\n");
}
