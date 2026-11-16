#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/tool-env.sh"
cd "$1"
haxe -cp haxe -main Sample -lib hxn-window -lib hxn-gpu-metal -resource haxe/box.metal@box.metal -resource haxe/scene.metal@scene.metal \
  -cpp cpp -D no-compilation -D HXCPP_ARM64 -D LEGACY_MACOSX_SDK -D MACOSX_VER=
mkdir -p licenses
cp "$threec_tools/../LICENSE" licenses/silicanto-MIT.txt
cp "$HXCPP/LICENSE.txt" licenses/hxcpp.txt
for lib in hxn hxn-window hxn-gpu-metal; do
  cp "$(haxelib libpath "$lib")/LICENSE" "licenses/$lib.txt"
done
