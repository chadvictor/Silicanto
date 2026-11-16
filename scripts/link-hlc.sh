#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$1
name=$2
hl="$root/.toolchain/hl/src"
[[ -e "$hl/libhl.dylib" ]] || { echo 'Run npm run setup:c to build libhl.' >&2; exit 1; }
cd "$out"
mkdir -p lib
cp "$hl/libhl.dylib" lib/
libraries=(lib/libhl.dylib)
if [[ -f hxn/gpu/metal/Device.c ]]; then
  for spec in hxn-window-0.2.0/xwindow hxn-gpu-metal-0.2.0/gpu_metal; do
    file="${spec##*/}.hdll"
    cp "$root/.toolchain/${spec%/*}/native/aarch64-apple-darwin/$file" "lib/$file"
    install_name_tool -id "@rpath/$file" "lib/$file"
    codesign -fs - "lib/$file"
    libraries+=("lib/$file")
  done
fi
python3 "$root/scripts/hlc-bindings.py" .
clang -O2 -std=gnu11 -I"$hl/src" -I. main.c hxn_bindings.c "${libraries[@]}" -Wl,-rpath,@executable_path/lib -o "$name"
