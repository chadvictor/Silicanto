import { resolveGraph } from "./frontend/graph.mjs";
import { emitModules } from "./frontend/modules.mjs";

export { resolveGraph };
export async function translate(input, loadScene, frontend = "auto", webRoot) {
  const graph = await resolveGraph(input, {
    externals: frontend === "auto" ? ["three"] : [],
    webRoot,
  });
  const modules = graph.modules;
  const legacy = modules.some((m) =>
    m.edges.some((e) => e.external && e.to === "three"),
  );
  if (
    frontend === "auto" &&
    (legacy ||
      (!graph.document &&
        ((modules.length === 1 && !modules[0].edges.length) ||
          !modules.some((m) => m.format === "cjs" || m.format === "json"))))
  ) {
    try {
      const { translate: typed } = await import("./legacy/three/translate.mjs");
      const pack = legacy
        ? (await import("./legacy/three/scene-asset.mjs")).packScene
        : null;
      const result = await typed(input, (path) => loadScene(path, pack));
      return {
        ...result,
        graph: graph.manifest,
        frontend: result.graphicsHost ? "legacy-three" : "typed",
      };
    } catch (error) {
      if (legacy || !/E-(?:SUBSET|MODULE)/.test(error.message)) throw error;
    }
  }
  return {
    ...emitModules(graph),
    graphicsHost: false,
    inputs: graph.inputs,
    graph: graph.manifest,
    frontend: "generic",
  };
}
