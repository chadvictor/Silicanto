import { lowerAsync } from "./async.mjs";
import { haxeString } from "./haxe-string.mjs";
import { Units } from "./units.mjs";
import { syntax } from "./graph.mjs";
import { emitModule } from "./javascript.mjs";

export function emitModules(graph) {
  const sources = {},
    globals = new Set();
  let asyncLowering = false;
  for (const module of graph.modules) {
    const name = "JsModule" + module.index;
    let body;
    const units = new Units(module.index);
    if (module.format === "json")
      body =
        'Js.put(module,"exports",Js.json(' +
        haxeString(module.source) +
        "));";
    else if (module.disabled) body = "";
    else {
      const lowered = lowerAsync(module, syntax(module));
      asyncLowering ||= Boolean(lowered.map);
      body = emitModule(graph, module, lowered.file, units, globals, lowered);
    }
    Object.assign(sources, units.sources());
    sources[name + ".hx"] =
      `// ${module.id.replace(/[\r\n]/g, " ")}\nclass ${name} {\n  public static function load():Dynamic {\n    return Js.load(${module.index}, function(module:Dynamic, exports:Dynamic) {\n${body}\n    });\n  }\n}\n`;
  }
  const web =
    !!graph.document ||
    [
      "window",
      "self",
      "document",
      "requestAnimationFrame",
      "cancelAnimationFrame",
      "Audio",
      "XMLHttpRequest",
      "fetch",
      "WebGL2RenderingContext",
      "Image",
      "AudioContext",
      "WebSocket",
    ].some((k) => globals.has(k));
  const init = web
    ? "WebPlatform.init(" +
      haxeString(JSON.stringify(graph.document?.elements ?? [])) +
      ");\n    "
    : "";
  const scriptBindings = (graph.scriptModules ?? [])
    .flatMap(({ aliases, module }) =>
      aliases.map(
        (url) =>
          "WebScriptElement.register(" +
          haxeString(url) +
          "," +
          module.index +
          ",JsModule" +
          module.index +
          ".load);",
      ),
    )
    .join("\n    ");
  const runRoots = graph.roots.map((root) => {
    const load = "JsModule" + root.index + ".load()";
    return root.bodyLoad ? 'Js.put(Js.realm,"onload",' + load + ');' : load + ";";
  });
  return {
    sources,
    scriptBindings,
    web,
    asyncLowering,
    globals: [...globals].sort(),
    haxe: `class Sample {\n  static function main() {\n    ${init}${scriptBindings}${runRoots.join("\n    ")}${web ? "\n    WebPlatform.run();" : "\n    JsPromise.checkpoint();"}\n  }\n}\n`,
  };
}
