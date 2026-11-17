"""Build the pinned native CSS layout library for the macOS desktop payload."""
import concurrent.futures
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

REVISION = "9bc84b8b8d15a4e50f18b327aa30955048b441c2"
SHA256 = "ff09151e75079bad74cb4f1dc5411e4cbc39452a9e86834df7c56289833dc53f"
cache = Path(__file__).resolve().parents[1] / ".toolchain"
cache.mkdir(exist_ok=True)
dest = cache / ("layout-" + REVISION)
with (cache / "layout.lock").open("w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if not (dest / "liblayout.a").is_file():
        with tempfile.TemporaryDirectory(dir=cache) as work:
            work = Path(work)
            archive = work / "source.tgz"
            urllib.request.urlretrieve("https://codeload.github.com/litehtml/litehtml/tar.gz/" + REVISION, archive)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
                raise RuntimeError("Unrecognized litehtml source")
            subprocess.run(["tar", "-xf", archive, "-C", work], check=True)
            src = work / ("litehtml-" + REVISION)
            gumbo = src / "src/gumbo"
            bundle = work / "bundle"
            bundle.mkdir()
            def compile_one(path):
                cpp = path.suffix == ".cpp"
                obj = work / (path.name + ".o")
                subprocess.run(["xcrun", "clang++" if cpp else "clang",
                                "-std=c++17" if cpp else "-std=c99", "-mmacosx-version-min=12.0",
                                "-O2", "-fPIC", "-I" + str(src/"include"), "-I" + str(src/"include/litehtml"),
                                "-I" + str(gumbo/"include"), "-I" + str(gumbo/"include/gumbo"),
                                "-c", path, "-o", obj], check=True)
                return obj
            with concurrent.futures.ThreadPoolExecutor(max_workers=min(os.cpu_count() or 1, 8)) as workers:
                objects = list(workers.map(compile_one, sorted((src/"src").glob("*.cpp")) + sorted(gumbo.glob("*.c"))))
            subprocess.run(["ar", "rcs", bundle/"liblayout.a", *objects], check=True)
            shutil.copytree(src/"include", bundle/"include")
            shutil.copy(src/"LICENSE", bundle/"litehtml-LICENSE.txt")
            shutil.copy(gumbo/"LICENSE", bundle/"gumbo-LICENSE.txt")
            os.rename(bundle, dest)
print(dest)
