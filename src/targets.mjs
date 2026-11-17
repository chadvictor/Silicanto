// Payloads consume an emitted Haxe project. Translators never choose a windowing API.
import { execFileSync } from "node:child_process";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const mac = "macos-arm64";
export const buildHost =
  ({ darwin: "macos", win32: "windows" }[process.platform] ??
    process.platform) +
  "-" +
  process.arch;
const nativeProfiles = ["logic", "scene", "packed-scene"];
const all = [...nativeProfiles, "canvas"];
const script = (path, args) =>
  execFileSync("bash", [join(root, path), ...args], { stdio: "inherit" });

function haxeBackend({ projectDir, target, manifest, mode, name, backend }) {
  script("scripts/haxe-target.sh", [
    projectDir,
    backend ? "external" : target,
    manifest.graphicsHost ? "graphics" : "logic",
    mode,
    name,
    backend || "",
  ]);
}
function java({ projectDir, manifest, mode, name }) {
  script("payloads/java/build.sh", [
    projectDir,
    manifest.graphicsHost ? "graphics" : "logic",
    mode,
    name,
  ]);
}

const payload = (
  target,
  platform,
  graphics,
  capabilities,
  build,
  extra = {},
) => ({
  apiVersion: 1,
  target,
  platform,
  graphics,
  capabilities,
  build,
  ...extra,
});
const builtins = [
  payload("haxe", "portable", "deferred", all, () => {}),
  ...["c", "cpp"].map((t) =>
    payload(t, mac, "metal", nativeProfiles, haxeBackend, {
      buildHosts: [mac],
    }),
  ),
  ...["c", "cpp"].map((t) =>
    payload(t, mac, "raster", ["canvas"], haxeBackend, { buildHosts: [mac] }),
  ),
  payload("js", "web", "webgl", ["logic", "scene"], haxeBackend),
  payload("neko", "neko", "none", ["logic"], haxeBackend),
  payload("neko", "neko", "raster", ["canvas"], haxeBackend),
  payload("python", "portable", "none", ["logic"], haxeBackend),
  payload("java", "jvm", "raster", ["canvas"], java, {
    compatiblePlatforms: [
      "macos-arm64",
      "macos-x64",
      "linux-arm64",
      "linux-x64",
      "windows-arm64",
      "windows-x64",
    ],
  }),
  payload("java", "jvm", "none", ["logic"], java, {
    // Class files use the Java SE 17 API and carry no host-specific libraries.
    compatiblePlatforms: [
      "macos-arm64",
      "macos-x64",
      "linux-arm64",
      "linux-x64",
      "windows-arm64",
      "windows-x64",
    ],
  }),
  payload("java", mac, "metal", ["scene"], java, { buildHosts: [mac] }),
];

export function projectProfile(manifest) {
  if (manifest.webHost) return "canvas";
  return Object.keys(manifest.sceneAssets ?? {}).length
    ? "packed-scene"
    : manifest.graphicsHost
      ? "scene"
      : "logic";
}
const key = (p) => [p.target, p.platform, p.graphics].join("/");
export async function registry(file) {
  if (!file) return builtins;
  // A payload is executable build tooling, loaded only when explicitly selected by the caller.
  const mod = await import(pathToFileURL(resolve(file)).href);
  const list = [...builtins],
    ids = new Set(list.map(key));
  for (const p of [mod.default].flat()) {
    if (
      p?.apiVersion !== 1 ||
      ![p.target, p.platform, p.graphics].every(
        (s) => typeof s === "string" && /^[a-z][a-z0-9-]*$/.test(s),
      ) ||
      typeof p.build !== "function" ||
      !Array.isArray(p.capabilities) ||
      !p.capabilities.length ||
      !p.capabilities.every((c) => all.includes(c)) ||
      [p.buildHosts, p.compatiblePlatforms].some(
        (ids) =>
          ids !== undefined &&
          (!Array.isArray(ids) ||
            !ids.every(
              (id) => typeof id === "string" && /^[a-z][a-z0-9-]*$/.test(id),
            )),
      )
    )
      throw Error(
        "E-PAYLOAD: expected a version 1 target descriptor with capabilities and a build function",
      );
    if (ids.has(key(p))) throw Error("E-PAYLOAD: duplicate " + key(p));
    ids.add(key(p));
    list.push(p);
  }
  return list;
}
export function selectPayload(
  list,
  { target, platform, graphics, backend, profile, mode },
) {
  if (backend) {
    if (platform || graphics)
      throw Error(
        "E-TARGET: use a payload descriptor to declare a platform or graphics backend",
      );
    return payload(target, "external", "external", all, haxeBackend);
  }
  const byTarget = list.filter((p) => p.target === target);
  const eligible = byTarget.filter(
    (p) =>
      (!graphics || p.graphics === graphics) &&
      p.capabilities.includes(profile),
  );
  const exact = eligible.filter((p) => p.platform === platform);
  const matches = !platform
    ? eligible
    : exact.length
      ? exact
      : eligible.filter((p) => p.compatiblePlatforms?.includes(platform));
  if (matches.length !== 1)
    throw Error(
      "E-TARGET: " +
        (matches.length ? "ambiguous" : "no compatible") +
        " payload for " +
        [target, platform, graphics, profile].filter(Boolean).join("/") +
        ". Available: " +
        (byTarget.map((p) => key(p) + " [" + p.capabilities + "]").join("; ") ||
          "none"),
    );
  const p = matches[0];
  if (mode === "build" && p.buildHosts && !p.buildHosts.includes(buildHost))
    throw Error(
      "E-TARGET: building " +
        key(p) +
        " requires " +
        p.buildHosts.join(" or ") +
        "; this host is " +
        buildHost,
    );
  return p;
}
