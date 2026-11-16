import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";

const samples = {
  fundamentals:
    "fbcab5992b081c950940947bb01039a63f1bcd36688c33ab1cfb1519517a931f",
  "fundamentals-with-animation":
    "f6eb0e3dadea8d02ba5eaa4c19cfbe753072a490a7b6f2f8fe42b9ea23861a3b",
};
const output = new URL("../samples/r180/", import.meta.url);
await mkdir(output, { recursive: true });
for (const [name, expected] of Object.entries(samples)) {
  const url =
    "https://raw.githubusercontent.com/mrdoob/three.js/r180/manual/examples/" +
    name +
    ".html";
  const file = new URL(name + ".html", output);
  const digest = bytes => createHash("sha256").update(bytes).digest("hex");
  const cached = await readFile(file).catch(e => {
    if (e.code !== "ENOENT") throw e;
    return null;
  });
  if (cached && digest(cached) === expected) continue;
  const response = await fetch(url);
  if (!response.ok) throw new Error(url + " HTTP " + response.status);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (digest(bytes) !== expected)
    throw new Error("SHA-256: " + name);
  await writeFile(file, bytes);
  console.log(name + " (r180)");
}
