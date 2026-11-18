import { scriptResources } from "./script-resources.mjs";
import { buildSync } from "esbuild";
import { parse } from "parse5";
import { parseSync } from "@babel/core";
import { basename, dirname, resolve } from "node:path";
import { readFileSync } from "node:fs";

const classicTypes = new Set([
  "",
  "application/ecmascript",
  "application/javascript",
  "application/x-ecmascript",
  "application/x-javascript",
  "text/ecmascript",
  "text/javascript",
  "text/javascript1.0",
  "text/javascript1.1",
  "text/javascript1.2",
  "text/javascript1.3",
  "text/javascript1.4",
  "text/javascript1.5",
  "text/jscript",
  "text/livescript",
  "text/x-ecmascript",
  "text/x-javascript",
]);

function scriptType(node) {
  const type = node.attrs?.find((a) => a.name === "type");
  if (type) return type.value.trim().toLowerCase();
  const language = node.attrs?.find((a) => a.name === "language")?.value;
  return language ? "text/" + language.toLowerCase() : "";
}

function storesScriptText(node) {
  if (!node.tagName) return false;
  if (node.tagName !== "script") return true;
  const type = scriptType(node);
  return type !== "module" && type !== "importmap" && !classicTypes.has(type);
}

export function readDocument(path, webRoot = dirname(path)) {
  const text = readFileSync(path, "utf8"),
    dir = dirname(path),
    scripts = [],
    elements = [],
    imports = {},
    styleInputs = [];
  const local = (url) => {
    if (!url || /^(?:[a-z]+:|\/\/)/i.test(url))
      throw Error(
        path + " E-MODULE: expected a local script URL, found " + url,
      );
    return url.startsWith("/")
      ? resolve(webRoot, "." + decodeURIComponent(url))
      : resolve(dir, decodeURIComponent(url));
  };
  function walk(n, parent = -1) {
    const attrs = Object.fromEntries(
      (n.attrs ?? []).map((a) => [a.name, a.value]),
    );
    if (n.tagName) {
      const index = elements.length;
      let sheet;
      if (
        n.tagName === "link" &&
        (attrs.rel ?? "").toLowerCase().split(/\s+/).includes("stylesheet") &&
        attrs.href &&
        !/^(?:[a-z]+:|\/\/)/i.test(attrs.href)
      ) {
        const file = local(attrs.href);
        const bundle = buildSync({
          absWorkingDir: dir,
          entryPoints: [file],
          bundle: true,
          write: false,
          metafile: true,
          logLevel: "silent",
          loader: {
            ".png": "dataurl",
            ".jpg": "dataurl",
            ".jpeg": "dataurl",
            ".svg": "dataurl",
            ".gif": "dataurl",
            ".woff": "dataurl",
            ".woff2": "dataurl",
          },
        });
        sheet = bundle.outputFiles[0].text;
        styleInputs.push(
          ...Object.keys(bundle.metafile.inputs).map((input) =>
            resolve(dir, input),
          ),
        );
      }
      const fragments = [];
      let at = 0;
      for (const child of n.childNodes ?? []) {
        if (
          child.nodeName === "#text" &&
          (n.tagName !== "script" || storesScriptText(n))
        )
          fragments.push({ at, text: child.value });
        else if (child.tagName) at++;
      }
      elements.push({
        attrs,
        fragments,
        sheet,
        parent,
        tag: n.tagName,
        id: attrs.id ?? "",
        width: attrs.width,
        height: attrs.height,
      });
      if (n.tagName === "body" && attrs.onload !== undefined) {
        const line = n.sourceCodeLocation?.attrs?.onload?.startLine ?? 1;
        // Validate the attribute as a function body before placing it inside
        // a generated function. Braces in the attribute cannot escape it.
        try {
          parseSync(attrs.onload, {
            babelrc: false, configFile: false, sourceType: "script",
            parserOpts: { allowReturnOutsideFunction: true, allowNewTargetOutsideFunction: true },
          });
        } catch (error) {
          throw Error(path + ":" + (line + (error.loc?.line ?? 1) - 1) +
            " E-SYNTAX: invalid body load handler: " + error.message.split("\n")[0]);
        }
        scripts.push({
          path: resolve(dir, basename(path) + ".body-onload.js"),
          kind: "handler",
          source: "(function onload(event) {\n" + attrs.onload + "\n});",
          line: line - 2,
        });
      }
      parent = index;
    }
    if (n.tagName === "script") {
      const type = scriptType(n),
        raw = (n.childNodes ?? []).map((c) => c.value ?? "").join("");
      if (type === "importmap") {
        const map = JSON.parse(raw);
        if (map.scopes)
          throw Error(
            path + " E-MODULE: scoped import maps are not implemented",
          );
        for (const [k, v] of Object.entries(map.imports ?? {}))
          imports[k] = local(v);
      } else if (type === "module" || classicTypes.has(type)) {
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
    for (const child of n.childNodes ?? []) walk(child, parent);
  }
  walk(parse(text, { sourceCodeLocationInfo: true }));
  if (!scripts.length)
    throw Error(path + " E-MODULE: document contains no executable scripts");
  return {
    scripts: [
      ...scripts.filter((s) => !s.deferred),
      ...scripts.filter((s) => s.deferred),
    ],
    resources: scriptResources(scripts, dir, webRoot),
    elements,
    styleInputs,
    imports,
  };
}
