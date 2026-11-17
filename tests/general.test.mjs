import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { resolveGraph } from "../src/frontend/graph.mjs";
import { emitModules } from "../src/frontend/modules.mjs";
import { compareFrame } from "./phaser4/reference.mjs";

test("an unknown npm package resolves browser exports and a nested cycle from source", async () => {
  const dir = mkdtempSync(join(tmpdir(), "silicanto-module-"));
  function put(name, src) {
    const p = join(dir, name);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, src);
  }
  try {
    put(
      "main.mjs",
      'import api from "unknown-library"; console.log(api.run());',
    );
    put(
      "node_modules/unknown-library/package.json",
      JSON.stringify({
        exports: { browser: "./browser.cjs", default: "./node.cjs" },
      }),
    );
    put(
      "node_modules/unknown-library/browser.cjs",
      'exports.name="A"; const b=require("private-child");exports.run=()=>b.read()+exports.name;',
    );
    put(
      "node_modules/unknown-library/node_modules/private-child/index.js",
      'const a=require("../../browser.cjs");exports.read=()=>a.name;',
    );
    const g = await resolveGraph(join(dir, "main.mjs"));
    assert.equal(g.modules.length, 3);
    assert.ok(g.modules.every((m) => !m.id.includes(dir)));
    assert.equal(
      g.modules.find((m) => m.id.endsWith("index.js")).edges[0].to,
      "node_modules/unknown-library/browser.cjs",
    );
    const result = emitModules(g);
    assert.equal(result.web, false);
    assert.equal(result.globals.includes("require"), false);
    assert.ok(Object.values(result.sources).every((s) => !s.includes("eval(")));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
test("a computed dependency receives a source diagnostic", async () => {
  const dir = mkdtempSync(join(tmpdir(), "silicanto-diagnostic-"));
  try {
    const file = join(dir, "entry.cjs");
    writeFileSync(file, "module.exports = name => require(name);");
    const g = await resolveGraph(file);
    assert.throws(
      () => emitModules(g),
      /entry.cjs:1:\d+ E-JAVASCRIPT: computed require/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
test("a blank output cannot pass a mostly-black reference frame", () => {
  const pixels = Buffer.alloc(3000);
  pixels[90] = 255;
  const ref = { width: 100, height: 10, pixels: pixels.toString("base64") },
    header = Buffer.from("P6\n100 10\n255\n");
  assert.throws(
    () => compareFrame(Buffer.concat([header, Buffer.alloc(3000)]), ref),
    /mismatch/i,
  );
  assert.equal(
    compareFrame(Buffer.concat([header, pixels]), ref).foregroundMatched,
    1,
  );
});
