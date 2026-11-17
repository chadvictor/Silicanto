import assert from "node:assert/strict";
import { execFile, execFileSync } from "node:child_process";
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { parseArgs, promisify } from "node:util";
import ts from "typescript";
import { jdk } from "./jdk.mjs";
import { sourceTree, root, revision } from "./khronos-source.mjs";

const { values } = parseArgs({
  options: {
    checkout: { type: "string" },
    out: { type: "string" },
    filter: { type: "string" },
    target: { type: "string", default: "cpp" },
    jobs: { type: "string", default: "2" },
  },
});
const target = values.target,
  jobs = Number(values.jobs);
assert.ok(["java", "cpp"].includes(target));
assert.ok(Number.isInteger(jobs) && jobs > 0 && jobs <= 8);
const tree = join(sourceTree(values.checkout), "ogles"),
  glDir = join(tree, "GL");
// The upstream descriptor is JavaScript object-literal data, including comments and trailing commas.
function literal(n) {
  if (ts.isObjectLiteralExpression(n))
    return Object.fromEntries(
      n.properties.map((p) => {
        assert.ok(ts.isPropertyAssignment(p));
        return [p.name.text, literal(p.initializer)];
      }),
    );
  if (ts.isArrayLiteralExpression(n)) return n.elements.map(literal);
  if (ts.isStringLiteral(n)) return n.text;
  if (ts.isNumericLiteral(n)) return Number(n.text);
  if (ts.isPrefixUnaryExpression(n) && n.operator === ts.SyntaxKind.MinusToken)
    return -literal(n.operand);
  if (n.kind === ts.SyntaxKind.NullKeyword) return null;
  if (
    n.kind === ts.SyntaxKind.TrueKeyword ||
    n.kind === ts.SyntaxKind.FalseKeyword
  )
    return n.kind === ts.SyntaxKind.TrueKeyword;
  throw Error("Unsupported literal " + n.getText());
}
const cases = [];
for (const group of readdirSync(glDir, { withFileTypes: true }).filter(
  (e) => e.isDirectory() && e.name !== "build",
)) {
  const dir = join(glDir, group.name);
  for (const page of readdirSync(dir)
    .filter((s) => s.endsWith(".html"))
    .sort()) {
    const html = readFileSync(join(dir, page), "utf8");
    const block = html.match(/OpenGLESTestRunner\.run\(([\s\S]*?)\);/);
    if (!block) continue;
    const ast = ts.createSourceFile(
      page,
      "(" + block[1] + ")",
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.JS,
    );
    const descriptor = literal(ast.statements[0].expression.expression);
    for (const t of descriptor.tests) {
      if (t.pattern !== "compare") continue;
      const id = group.name + "/" + t.name;
      if (values.filter && !id.includes(values.filter)) continue;
      const sources = {};
      for (const pr of [t.testProgram, t.referenceProgram])
        for (const path of [pr.vertexShader, pr.fragmentShader])
          sources[path] = readFileSync(resolve(dir, path), "utf8");
      cases.push({ id, sources, test: t });
    }
  }
}
assert.ok(cases.length > 0, "No matching upstream rendering cases");
mkdirSync(join(root, "dist"), { recursive: true });
const work = mkdtempSync(join(root, "dist/ogles-render-"));
const results = new Array(cases.length),
  launch = promisify(execFile);
const report = () => {
  if (values.out)
    writeFileSync(
      values.out,
      JSON.stringify(
        {
          revision,
          target,
          selected: cases.length,
          results: results.filter(Boolean),
        },
        null,
        2,
      ) + "\n",
    );
};
try {
  copyFileSync(join(tree, "ogles-utils.js"), join(work, "ogles-utils.js"));
  copyFileSync(
    join(root, "tests/fixtures/khronos/host.js"),
    join(work, "host.js"),
  );
  writeFileSync(
    join(work, "start.js"),
    "OpenGLESTestRunner.run({tests:[descriptor.test]});",
  );
  writeFileSync(
    join(work, "index.html"),
    '<!doctype html><canvas width="500" height="500" id="example"></canvas><div id="console"></div><script src="host.js"></script><script src="ogles-utils.js"></script><script src="start.js"></script>',
  );
  const dest = join(work, "project");
  execFileSync(
    process.execPath,
    [
      "src/cli.mjs",
      "build",
      join(work, "index.html"),
      "--frontend",
      "generic",
      "--target",
      target,
      "--out",
      dest,
    ],
    { cwd: root },
  );
  let next = 0,
    done = 0;
  async function worker(slot) {
    const assets = join(work, "assets-" + slot);
    mkdirSync(assets);
    while (next < cases.length) {
      const i = next++,
        c = cases[i];
      writeFileSync(join(assets, "case.json"), JSON.stringify(c));
      const args = ["--asset-root", assets];
      try {
        const { stdout } =
          target === "cpp"
            ? await launch(join(dest, "cpp/Sample"), args, { timeout: 120000 })
            : await launch(
                jdk("java"),
                [
                  "-Djava.awt.headless=true",
                  "-jar",
                  join(dest, "java/Sample.jar"),
                  ...args,
                ],
                { timeout: 120000 },
              );
        const result = JSON.parse(stdout.trim().split("\n").at(-1));
        results[i] = {
          id: c.id,
          passed: result.passes > 0 && result.errors.length === 0,
          ...result,
        };
      } catch (e) {
        results[i] = {
          id: c.id,
          passed: false,
          errors: [String(e.stderr || e.stdout || e.message).slice(0, 600)],
        };
      }
      if (++done % 16 === 0) report();
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(jobs, cases.length) }, (_, s) => worker(s)),
  );
  report();
  const passed = results.filter((x) => x.passed).length;
  console.log(
    target +
      ": " +
      passed +
      "/" +
      results.length +
      " upstream OGLES reference-shader pixel comparisons passed",
  );
  if (passed !== results.length) {
    console.error(results.find((x) => !x.passed));
    process.exitCode = 1;
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
