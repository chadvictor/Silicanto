import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
export const root = fileURLToPath(new URL("../", import.meta.url));
export const revision = "39443210f7f81db4773eb104facadfb85d05dfa4";
const base = "sdk/tests/conformance";
export function sourceTree(path) {
  const checkout = resolve(path ?? join(root, ".toolchain/khronos-webgl"));
  mkdirSync(checkout, { recursive: true });
  const git = (...args) =>
    execFileSync("git", ["-C", checkout, ...args], { encoding: "utf8" }).trim();
  if (!existsSync(join(checkout, ".git"))) {
    git("init", "-q");
    git("remote", "add", "origin", "https://github.com/KhronosGroup/WebGL.git");
    git("sparse-checkout", "init", "--cone");
    git("sparse-checkout", "set", base + "/ogles", base + "/context");
    git("fetch", "--filter=blob:none", "--depth=1", "origin", revision);
    git("checkout", "--detach", "FETCH_HEAD");
  }
  assert.equal(git("rev-parse", "HEAD"), revision);
  assert.equal(
    git("status", "--porcelain", "--", base + "/ogles", base + "/context"),
    "",
  );
  return join(checkout, base);
}
