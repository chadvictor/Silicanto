"""Build Silicanto's native layout engine from pinned, verified sources."""
import concurrent.futures
import fcntl
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import urllib.request

LITEHTML = ("litehtml/litehtml", "9bc84b8b8d15a4e50f18b327aa30955048b441c2",
            "ff09151e75079bad74cb4f1dc5411e4cbc39452a9e86834df7c56289833dc53f")
TAFFY = ("inobelar/taffy_cpp", "6b81709e834cfefdb54149cefb2e0d467b333260",
         "6cc2401a00596c745801121a9caf2846ef199e56a08b74ebe37c3ebe9a334ed0")
root = Path(__file__).resolve().parents[1]
cache = root / ".toolchain"
extension = root / "payloads/layout"


def source(package, work):
    repo, commit, expected = package
    name = repo.split("/")[-1] + "-" + commit
    archive = work / (name + ".tgz")
    urllib.request.urlretrieve("https://codeload.github.com/" + repo + "/tar.gz/" + commit, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise ValueError("Source checksum mismatch for " + repo)
    subprocess.run(["tar", "-xf", archive, "-C", work], check=True)
    return work / name


def build(work, dest):
    html = source(LITEHTML, work)
    grid = source(TAFFY, work)
    with (extension / "taffy-implicit-tracks.patch").open("rb") as patch:
        subprocess.run(["patch", "-s", "-p1"], cwd=grid, stdin=patch, check=True)
    with (extension / "litehtml-grid.patch").open("rb") as patch:
        subprocess.run(["patch", "-s", "-p1"], cwd=html, stdin=patch, check=True)
    shutil.copyfile(extension / "render_grid.cpp", html / "src/render_grid.cpp")
    shutil.copyfile(extension / "render_grid.h", html / "include/litehtml/render_grid.h")
    gumbo = html / "src/gumbo"
    bundle = work / "bundle"
    bundle.mkdir()

    def compile_one(path):
        cpp = path.suffix == ".cpp"
        obj = work / (path.name + ".o")
        include = [html / "include", html / "include/litehtml", gumbo / "include", gumbo / "include/gumbo"]
        flags = []
        if path.name == "render_grid.cpp":
            include.extend([grid / "include", *sorted((grid / "third_party").glob("*/include"))])
            flags = ["-DTAFFY_FEATURE_TAFFY_TREE", "-DTAFFY_FEATURE_GRID"]
        subprocess.run(["xcrun", "clang++" if cpp else "clang", "-std=c++17" if cpp else "-std=c99",
                        "-mmacosx-version-min=12.0", "-O2", "-fPIC", *flags,
                        *["-I" + str(p) for p in include], "-c", path, "-o", obj], check=True)
        return obj

    sources = sorted((html / "src").glob("*.cpp")) + sorted(gumbo.glob("*.c"))
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(os.cpu_count() or 1, 8)) as workers:
        objects = list(workers.map(compile_one, sources))
    subprocess.run(["ar", "rcs", bundle / "liblayout.a", *objects], check=True)
    shutil.copytree(html / "include", bundle / "include")
    for file, label in [(html / "LICENSE", "litehtml"), (gumbo / "LICENSE", "gumbo"), (grid / "LICENSE", "taffy-cpp")]:
        shutil.copy(file, bundle / (label + "-LICENSE.txt"))
    for license_file in (grid / "third_party").glob("*/LICENSE.txt"):
        shutil.copy(license_file, bundle / (license_file.parent.name + "-LICENSE.txt"))
    slot_map = (grid / "third_party/slot_map/include/stdext/slot_map.hpp").read_text()
    (bundle / "slot-map-LICENSE.txt").write_text(slot_map.split("*/", 1)[0] + "*/\n")
    os.rename(bundle, dest)


cache.mkdir(exist_ok=True)
digest = hashlib.sha256(Path(__file__).read_bytes())
for path in sorted(extension.iterdir()):
    if path.is_file():
        digest.update(path.read_bytes())
dest = cache / ("layout-" + platform.machine() + "-" + digest.hexdigest()[:20])
with (cache / "layout.lock").open("w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if not (dest / "liblayout.a").is_file():
        with tempfile.TemporaryDirectory(dir=cache) as work:
            build(Path(work), dest)
print(dest)
