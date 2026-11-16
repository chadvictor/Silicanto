"""Link HLC's typed native declarations to the primitives exported by hx-n HDLLs."""
import re
import sys
from pathlib import Path

directory = Path(sys.argv[1])
header = (directory / "hl/natives.h").read_text(encoding="utf-8-sig")
declarations = re.compile(r"^HL_API ([\w*]+) ((gpu_metal|xwindow)_([\w]+))\(([^()]*)\);$", re.M)
lines = ['#include <hlc.h>', '#include <hl/natives.h>']
for result, symbol, library, primitive, signature in declarations.findall(header):
    types = [] if signature in ("", "void") else signature.split(",")
    arguments = ", ".join(f"{t} a{i}" for i, t in enumerate(types)) or "void"
    names = ", ".join(f"a{i}" for i in range(len(types)))
    lines.extend([
        f"extern void *hlp_{primitive}(const char **);",
        f"{result} {symbol}({arguments}) {{",
        "  const char *signature;",
        f"  typedef {result} (*Primitive)({signature or 'void'});",
        f"  Primitive fn = (Primitive)hlp_{primitive}(&signature);",
        f"  {'return ' if result != 'void' else ''}fn({names});",
        "}",
    ])
(directory / "hxn_bindings.c").write_text("\n".join(lines) + "\n")
