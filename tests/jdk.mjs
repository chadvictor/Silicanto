import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const bundled = fileURLToPath(new URL("../.toolchain/jdk", import.meta.url));
export const jdk = (tool) => {
  const home =
    process.env.JAVA_HOME ||
    (existsSync(join(bundled, "bin", tool)) && bundled);
  return home ? join(home, "bin", tool) : tool;
};
