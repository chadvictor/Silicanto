import { lowerAsync } from "./async.mjs";
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
        JSON.stringify(module.source) +
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
      JSON.stringify(JSON.stringify(graph.document?.elements ?? [])) +
      ");\n    "
    : "";
  return {
    sources,
    web,
    asyncLowering,
    globals: [...globals].sort(),
    haxe: `class Sample {\n  static function main() {\n    ${init}${graph.roots.map((root) => "JsModule" + root.index + ".load();").join("\n    ")}${web ? "\n    WebPlatform.run();" : "\n    JsPromise.checkpoint();"}\n  }\n}\n`,
  };
}
