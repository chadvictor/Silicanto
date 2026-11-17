import { parse } from "parse5";
import { basename, dirname, resolve } from "node:path";
import { readFileSync } from "node:fs";

export function readDocument(path) {
  const text = readFileSync(path, "utf8"),
    dir = dirname(path),
    scripts = [],
    elements = [],
    imports = {};
  const local = (url) => {
    if (!url || /^(?:[a-z]+:|\/\/|\/)/i.test(url))
      throw Error(
        path + " E-MODULE: expected a local script URL, found " + url,
      );
    return resolve(dir, decodeURIComponent(url));
  };
  function walk(n) {
    const attrs = Object.fromEntries(
      (n.attrs ?? []).map((a) => [a.name, a.value]),
    );
    if (
      n.tagName &&
      n.tagName !== "script" &&
      (attrs.id || n.tagName === "canvas")
    )
      elements.push({
        tag: n.tagName,
        id: attrs.id ?? "",
        width: attrs.width,
        height: attrs.height,
      });
    if (n.tagName === "script") {
      const type = (attrs.type ?? "").toLowerCase(),
        raw = (n.childNodes ?? []).map((c) => c.value ?? "").join("");
      if (type === "importmap") {
        const map = JSON.parse(raw);
        if (map.scopes)
          throw Error(
            path + " E-MODULE: scoped import maps are not implemented",
          );
        for (const [k, v] of Object.entries(map.imports ?? {}))
          imports[k] = local(v);
      } else if (
        ["", "module", "application/javascript", "text/javascript"].includes(
          type,
        )
      ) {
        if ("async" in attrs || "nomodule" in attrs)
          throw Error(
            path +
              " E-MODULE: asynchronous or conditional script scheduling is unsupported",
          );
        const kind = type === "module" ? "module" : "classic";
        const script = {
          path: attrs.src
            ? local(attrs.src)
            : resolve(
                dir,
                basename(path) + ".inline-" + scripts.length + ".js",
              ),
          kind,
          deferred: kind === "module" || ("defer" in attrs && !!attrs.src),
        };
        if (!attrs.src) {
          script.source = raw;
          script.line = n.sourceCodeLocation.startTag.endLine - 1;
        }
        scripts.push(script);
      }
    }
    for (const child of n.childNodes ?? []) walk(child);
  }
  walk(parse(text, { sourceCodeLocationInfo: true }));
  if (!scripts.length)
    throw Error(path + " E-MODULE: document contains no executable scripts");
  return {
    scripts: [
      ...scripts.filter((s) => !s.deferred),
      ...scripts.filter((s) => s.deferred),
    ],
    elements,
    imports,
  };
}
