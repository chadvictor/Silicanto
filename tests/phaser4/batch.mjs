// A test-only Haxe entry point selects one translated example per OS process.
// The engine module is compiled unchanged. Only module ID allocation and the
// entry point differ from building an individual HTML document with the CLI.
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { emitModules } from "../../src/frontend/modules.mjs";
import { resolveGraph } from "../../src/frontend/graph.mjs";

export async function batchSuite({
  project,
  out,
  cases,
  documentFor,
  target,
  report,
  save,
  build,
  observe,
  batchSize,
  jobs: parallelism,
}) {
  let batchId = 0;
  const main = readFileSync(join(project, "haxe/Sample.hx"), "utf8");
  const init = main.slice(
    main.indexOf("WebPlatform.init("),
    main.indexOf("WebPlatform.run();"),
  );
  const metadata = JSON.parse(readFileSync(join(project, "manifest.json")));
  const base = metadata.moduleGraph.modules.length;
  let next = base;
  const jobs = [];
  for (const [index, c] of cases.entries()) {
    try {
      const graph = await resolveGraph(documentFor(c), { webRoot: out });
      for (const m of graph.modules) m.index = next++;
      const { sources } = emitModules(graph);
      jobs.push({
        c,
        index,
        sources,
        start: graph.roots
          .map((m) => "JsModule" + m.index + ".load();")
          .join("\n"),
      });
    } catch (err) {
      report.cases.push({
        ...c,
        status: "failed",
        stage: "translate",
        executed: false,
        diagnostic: err.message,
      });
    }
  }
  save();
  async function group(items) {
    if (!items.length) return;
    const id = batchId++,
      folder = join(out, "batch-" + id),
      source = join(folder, "input");
    mkdirSync(source, { recursive: true });
    // The original bootstrap project is unchanged and stays independently runnable.
    cpSync(join(project, "manifest.json"), join(source, "manifest.json"));
    cpSync(join(project, "haxe"), join(source, "haxe"), { recursive: true });
    for (const j of items)
      for (const [file, text] of Object.entries(j.sources))
        writeFileSync(join(source, "haxe", file), text);
    writeFileSync(
      join(source, "haxe/Sample.hx"),
      "class Sample { static function main() {\n" +
        init +
        'switch(Sys.getEnv("SILICANTO_EXAMPLE")){\n' +
        items.map((j) => 'case "' + j.index + '": ' + j.start).join("\n") +
        '\ndefault: throw "Unknown example";}\nWebPlatform.run();}}\n',
    );
    const binary = join(folder, "binary");
    try {
      build(source, binary);
    } catch (error) {
      rmSync(folder, { recursive: true, force: true });
      // A source-level Haxe failure in one example must not suppress all its neighbors.
      const diag = error.message;
      const bad = items.filter((j) =>
        Object.keys(j.sources).some(
          (file) =>
            diag.includes("/" + file + ":") ||
            diag.includes("/" + file.replace(".hx", ".java") + ":"),
        ),
      );
      if (items.length === 1 || (bad.length && bad.length < items.length)) {
        const failed = items.length === 1 ? items : bad;
        for (const j of failed)
          report.cases.push({
            ...j.c,
            status: "failed",
            stage: "build",
            executed: false,
            diagnostic: diag.slice(-1800),
          });
        save();
        if (failed.length < items.length)
          await group(items.filter((i) => !bad.includes(i)));
        return;
      }
      const mid = Math.ceil(items.length / 2);
      await group(items.slice(0, mid));
      await group(items.slice(mid));
      return;
    }
    let cursor = 0;
    async function worker() {
      while (cursor < items.length) {
        const pos = cursor++,
          j = items[pos];
        const trace = join(folder, "frames-" + j.index + ".json");
        let stage = "run";
        try {
          const measurement = await observe(binary, trace, j.index);
          report.cases.push({
            ...j.c,
            status: "native-observed",
            executed: true,
            measurement,
          });
        } catch (error) {
          report.cases.push({
            ...j.c,
            status: "failed",
            stage,
            executed: true,
            diagnostic: error.message.slice(0, 1500),
          });
        }
        if (existsSync(trace)) rmSync(trace);
        if ((pos + 1) % 16 === 0) save();
      }
    }
    await Promise.all(
      Array.from({ length: Math.min(parallelism, items.length) }, worker),
    );
    save();
    rmSync(folder, { recursive: true, force: true });
  }
  for (let i = 0; i < jobs.length; i += batchSize)
    await group(jobs.slice(i, i + batchSize));
}
