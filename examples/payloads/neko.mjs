// An external logic payload. Put Haxe 4.3.7 and Neko on PATH before using it.
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { join } from "node:path";

export default {
  apiVersion: 1,
  target: "neko",
  platform: "neko-vm",
  graphics: "none",
  capabilities: ["logic"],
  build({ projectDir, name }) {
    mkdirSync(join(projectDir, "neko"));
    execFileSync(
      "haxe",
      ["-cp", "haxe", "-main", "Sample", "--neko", `neko/${name}.n`],
      {
        cwd: projectDir,
        stdio: "inherit",
      },
    );
  },
};
