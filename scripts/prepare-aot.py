"""Adapt pinned upstream sources for macOS and ahead-of-time WebGL constructors."""
from pathlib import Path
import re
import sys

base = Path(sys.argv[1])
for file, names in (("lib/InternalJavaScript", "internal_bytecode_sources"),
                    ("API/hermes/extensions", "extensions_js_sources")):
    path = base / "hermes" / file / "CMakeLists.txt"
    previous = path.read_text()
    text = previous.replace("${concatenate} ${" + names + "_native_path}",
                                    "${concatenate} ${" + names + "}")
    if text != previous:
        path.write_text(text)

path = base / "expo/common/EXWebGLRenderer.cpp"
source = path.read_text()
constructors = re.search(r'evalStubConstructors = R"\((.*?)\)";', source, re.S)
if not constructors:
    raise ValueError("Unknown Expo GL constructor declaration")
body = re.sub(r'^([A-Za-z]+\w*) = ', r'globalThis.\1 = ', constructors[1], flags=re.M)
(base / "constructors.js").write_text("globalThis.__installWebGLTypes = function() {" + body + "};\n")
old = 'runtime.evaluateJavaScript(evalBuffer, "expo-gl");'
replacement = 'runtime.global().getPropertyAsFunction(runtime, "__installWebGLTypes").call(runtime);'
if old not in source and replacement not in source:
    raise ValueError("Unknown Expo GL initialization")
path.write_text(source.replace(old, replacement).replace(
    "  auto evalBuffer = std::make_shared<jsi::StringBuffer>(evalStubConstructors);\n", ""))

includes = base / "include/OpenGLES"
(includes / "ES3").mkdir(parents=True, exist_ok=True)
(includes / "EAGL.h").write_text("// EAGL is replaced by EGL on macOS.\n")
(includes / "ES3/gl.h").write_text("#include <GLES3/gl3.h>\n")
(includes / "ES3/glext.h").write_text("#include <GLES2/gl2ext.h>\n")
