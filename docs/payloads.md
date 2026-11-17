# Adding a target or graphics backend

The compiler translates the JavaScript module graph once. `silicanto target` reads the generated Haxe directory, its manifest and any packed assets. It can build a new target after you have edited the Haxe or removed the original JavaScript. A payload supplies the generator, platform bindings and packaging for one combination of target language, platform and graphics API.

Run `npx --no-install silicanto targets` to see the built-in combinations. For example, a Java project that only computes vertex positions can use the portable JVM payload. A Java application that opens a Three.js window needs a graphics payload. The built-in Java graphics payload runs on Apple Silicon with Metal.

## Register a payload

Export a descriptor (or an array of descriptors) as the default export of an ES module. Pass the file explicitly to `--payload`; it runs as trusted build code with the permissions of the caller. No installation or compiler change is required.

| Field | Meaning |
| --- | --- |
| `apiVersion` | The contract version; currently `1`. |
| `target`, `platform`, `graphics` | Unique combination of lowercase IDs. Use `none` for a payload without a graphics API. |
| `capabilities` | Project profiles the payload accepts: `logic` (no graphics host), `scene` (runtime scene or simple cube), `packed-scene` (uses the static asset adapter). |
| `buildHosts` (optional) | Machines that can **build** the artifact, such as `macos-arm64`. Does not restrict source emission. |
| `compatiblePlatforms` (optional) | Additional **run** platforms served by the same artifact. An exact platform match takes priority. |
| `build(context)` | Synchronous or async function. Generate sources in `emit` mode; build the runnable output in `build` mode. Throw on failure. |

The context contains `projectDir` (absolute staging directory), `manifest`, `target`, `name` (validated output name) and `mode`. Resolve the entry relative to `projectDir` using `manifest.entry`. Write outputs under that directory and use relative paths in launchers: Silicanto moves it to the final destination only on success. The manifest is already available on disk when your builder starts. The project profile describes the services used by the supported input; a payload does not add new JavaScript syntax or DOM operations to the frontend.

The [working Neko example](../examples/payloads/neko.mjs) calls an existing Haxe generator and produces executable VM bytecode. With Haxe 4.3.7 and Neko on PATH (or after sourcing `scripts/tool-env.sh` in Bash on a configured Mac):

```sh
npx --no-install silicanto emit tests/fixtures/modules/main.js --out dist/logic
npx --no-install silicanto target dist/logic --payload examples/payloads/neko.mjs \
  --target neko --platform neko-vm --name Terrain --out dist/terrain-neko
neko dist/terrain-neko/neko/Terrain.n
```

For a graphics payload, supply a platform-specific Haxe `DesktopSurface` on a higher-priority classpath or implement an equivalent host. The [Java adapter](../payloads/java/haxe/DesktopSurface.hx) consumes the shared [scene upload](../runtime/legacy/three/SceneUpload.hx) and [camera uniforms](../runtime/legacy/three/FrameUniforms.hx); it never sees the original JS. Its Swing/JNI implementation receives generic geometry, lights, camera and frame data. Another platform can reuse that interface and supply its own window, input, renderer and packaging.

## Selection and failure

If exactly one registered payload supports the target and project profile, the CLI selects it. Use `--platform` and `--graphics` to disambiguate. Duplicate IDs, ambiguous selections, unavailable build hosts and incompatible profiles fail before the output directory is created. A custom HXML backend remains available when a generator alone is sufficient. Validate new bindings against original JS output; for graphics, compare fixed camera times against the WebGL reference.
