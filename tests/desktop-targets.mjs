import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import {
  cpSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";
import { jdk } from "./jdk.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
mkdirSync(join(root, "dist"), { recursive: true });
const work = mkdtempSync(join(root, "dist/desktop-contract-"));
const source = join(work, "source");
cpSync(join(root, "tests/fixtures/desktop"), source, { recursive: true });
const server = createServer(async (req, res) => {
  if (req.url === "/slow") {
    const timer = setTimeout(() => res.end("late"), 1500);
    res.on("close", () => clearTimeout(timer));
    return;
  }
  if (req.url !== "/echo") {
    res.writeHead(404);
    res.end("missing");
    return;
  }
  const body = [];
  for await (const bytes of req) body.push(bytes);
  res.writeHead(201, {
    "content-type": "application/json",
    "x-server": "native",
  });
  res.end(
    JSON.stringify({
      text: Buffer.concat(body).toString(),
      client: req.headers["x-client"],
    }),
  );
});
const ws = new WebSocketServer({ server });
ws.on("connection", (socket) => {
  socket.on("message", (data, binary) =>
    socket.send(data, { binary }, () => {
      if (binary) socket.close(1000, "done");
    }),
  );
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = "http://127.0.0.1:" + server.address().port;
writeFileSync(
  join(source, "settings.js"),
  "const TEST_ORIGIN=" + JSON.stringify(origin) + ";",
);
const frames = 1764,
  wav = Buffer.alloc(44 + frames * 2);
wav.write("RIFF");
wav.writeUInt32LE(36 + frames * 2, 4);
wav.write("WAVEfmt ", 8);
wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20);
wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(11025, 24);
wav.writeUInt32LE(22050, 28);
wav.writeUInt16LE(2, 32);
wav.writeUInt16LE(16, 34);
wav.write("data", 36);
wav.writeUInt32LE(frames * 2, 40);
for (let i = 0; i < frames; i++)
  wav.writeInt16LE(
    Math.round(Math.sin((i * 440 * 2 * Math.PI) / 11025) * 2400),
    44 + 2 * i,
  );
writeFileSync(join(source, "tone.wav"), wav);
writeFileSync(
  join(work, "input.json"),
  JSON.stringify([
    { frame: 3, type: "pointerdown", x: 10, y: 10, button: 0, buttons: 1 },
    { frame: 4, type: "pointerup", x: 10, y: 10, button: 0, buttons: 0 },
    { frame: 5, type: "keydown", key: " ", code: "Space", keyCode: 32 },
  ]),
);
function run(exe, args) {
  return new Promise((resolve, reject) => {
    const p = spawn(exe, args, {
      cwd: root,
      timeout: 300000,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let log = "";
    p.stdout.on("data", (b) => (log = (log + b).slice(-12000)));
    p.stderr.on("data", (b) => (log = (log + b).slice(-12000)));
    p.on("error", reject);
    p.on("close", (code, signal) =>
      code === 0
        ? resolve(log)
        : reject(Error(exe + " exited " + (code ?? signal) + "\n" + log)),
    );
  });
}
try {
  const nativeTest = join(work, "appkit-events");
  await run("xcrun", [
    "clang++",
    "-std=c++17",
    "-fobjc-arc",
    "tests/fixtures/input/AppKitEvents.mm",
    "payloads/canvas/macos/CanvasWindow.mm",
    "-framework",
    "AppKit",
    "-framework",
    "QuartzCore",
    "-o",
    nativeTest,
  ]);
  await run(jdk("javac"), [
    "-d",
    work,
    "tests/fixtures/input/AwtEvents.java",
    "payloads/canvas/java/org/silicanto/canvas/CanvasInput.java",
  ]);
  for (const [target, command, args] of [
    ["AppKit", nativeTest, []],
    [
      "AWT",
      jdk("java"),
      [
        "-Djava.awt.headless=true",
        "-cp",
        work,
        "org.silicanto.canvas.AwtEvents",
      ],
    ],
  ]) {
    const output = await run(command, args),
      events = JSON.parse(
        output
          .trim()
          .split("\n")
          .find((line) => line.startsWith("[")),
      );
    for (const type of ["pointerdown", "pointerup"]) {
      const event = events.find((e) => e.type === type);
      assert.ok(event, target + " " + type);
      assert.equal(event.x, 12);
      assert.equal(event.y, 14);
      assert.equal(event.button, 0);
    }
    const key = events.find((e) => e.type === "keydown");
    assert.equal(key.code, "KeyA");
    assert.equal(key.key, "A");
    assert.ok(key.shiftKey);
    console.log(
      target + " window input queue delivered click and keyboard events",
    );
  }
  for (const t of ["cpp", "java"]) {
    const dir = join(work, t),
      trace = join(dir, "trace.json"),
      page = join(dir, "page.ppm");
    await run(process.execPath, [
      "src/cli.mjs",
      "build",
      join(source, "index.html"),
      "--frontend",
      "generic",
      "--target",
      t,
      "--out",
      dir,
    ]);
    const cmd =
      t === "cpp"
        ? [join(dir, "cpp/Sample")]
        : [
            jdk("java"),
            "-Djava.awt.headless=true",
            "-jar",
            join(dir, "java/Sample.jar"),
          ];
    const log = await run(cmd[0], [
      ...cmd.slice(1),
      "--asset-root",
      source,
      "--realtime",
      "--frames",
      "45",
      "--input",
      join(work, "input.json"),
      "--timeline",
      trace,
      "1,15,45",
      "--capture-page",
      page,
    ]);
    assert.match(log, /native contracts passed/);
    const samples = JSON.parse(readFileSync(trace));
    assert.deepEqual(
      samples.map((s) => s.frame),
      [1, 15, 45],
    );
    assert.equal(new Set(samples.map((s) => s.sha256)).size, 3);
    const ppm = readFileSync(page),
      header = Buffer.from("P6\n800 600\n255\n");
    assert.ok(ppm.subarray(0, header.length).equals(header));
    const pixel = (x, y) => [
      ...ppm.subarray(
        header.length + 3 * (800 * y + x),
        header.length + 3 * (800 * y + x) + 3,
      ),
    ];
    assert.deepEqual(pixel(1, 1), [45, 255, 0]);
    assert.deepEqual(pixel(100, 35), [250, 100, 10]);
    assert.deepEqual(pixel(157, 100), [18, 104, 55]);
    assert.deepEqual(pixel(165, 100), [222, 167, 33]);
    console.log(
      t +
        ": GPU, page pixels, media playback, HTTP, pointer and keyboard contracts passed across 45 frames",
    );
  }
} finally {
  for (const s of ws.clients) s.terminate();
  ws.close();
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
  if (!process.env.SILICANTO_KEEP_TEST_OUTPUT)
    rmSync(work, { recursive: true, force: true });
  else console.log(work);
}
