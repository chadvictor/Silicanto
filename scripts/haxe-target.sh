#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
stage=$1 target=$2 graphics=$3 action=$4 name=$5
if [[ "$target" == c || "$target" == cpp ]]; then
  [[ -x "$root/.toolchain/haxe/haxe" ]] || { echo 'Run npm run setup:mac first' >&2; exit 1; }
  source "$root/scripts/tool-env.sh"
else
  source "$root/scripts/haxe-env.sh"
fi
cd "$stage"
args=(-cp haxe -main Sample)
if [[ "$graphics" == graphics && ( "$target" == c || "$target" == cpp ) ]]; then
  args+=(-lib hxn-window -lib hxn-gpu-metal -resource haxe/box.metal@box.metal -resource haxe/scene.metal@scene.metal)
fi
case "$target" in
  c)
    if [[ -f haxe/WebImage.hx ]]; then args+=(--dce full); fi
    haxe "${args[@]}" -D no-compilation --hl c/main.c
    if [[ "$action" == build ]]; then
      bash "$root/scripts/link-hlc.sh" "$stage/c" "$name"
      [[ ! -d assets ]] || cp -R assets c/
      cp "$root/.toolchain/hl/src/LICENSE" licenses/hashlink.txt
      cp "$root/.toolchain/hl/src/include/pcre/LICENCE" licenses/pcre.txt
    fi
    ;;
  cpp)
    if [[ "$graphics" == graphics ]]; then
      bash "$root/scripts/generate.sh" "$stage"
      cp "$root/runtime/legacy/three/build.sh" build.sh
      if [[ "$action" == build ]]; then bash build.sh; fi
    else
      flags=(-D HXCPP_ARM64 -D LEGACY_MACOSX_SDK -D MACOSX_VER=)
      flags+=(-D no-compilation -D silicanto_apple_image)
      if [[ -f haxe/WebWindow.hx ]]; then
        flags+=(-D silicanto_window)
        mkdir -p platform
        cp "$root/payloads/canvas/macos/CanvasWindow.mm" platform/
        if [[ "$action" == build ]]; then
          xcrun clang++ -O2 -fobjc-arc -c platform/CanvasWindow.mm -o platform/canvas.o
          ar rcs platform/libcanvas.a platform/canvas.o
        fi
      fi
      export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
      haxe "${args[@]}" --cpp cpp "${flags[@]}"
      if [[ "$action" == build ]]; then (cd cpp && neko "$HXCPP/hxcpp.n" Build.xml haxe); fi
      cp "$HXCPP/LICENSE.txt" licenses/hxcpp.txt
    fi
    if [[ "$action" == build && "$name" != Sample ]]; then mv cpp/Sample "cpp/$name"; fi
    ;;
  js)
    mkdir -p js
    if [[ "$graphics" == graphics ]]; then args+=(--macro 'includeFile("haxe/three-browser.js","top")'); fi
    haxe "${args[@]}" --js js/program.js
    if [[ "$graphics" == graphics ]]; then
      cp "$root"/node_modules/three/build/{three.module.js,three.core.js} js/
      cat > js/index.html <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Silicanto</title>
<canvas></canvas>
<script type="module" src="./program.js"></script>
HTML
    fi
    ;;
  external) haxe "${args[@]}" "$6" ;;
  neko) mkdir -p neko; haxe "${args[@]}" --neko "neko/$name.n" ;;
  python) mkdir -p python; haxe "${args[@]}" --python python/program.py ;;
  *) echo "Unknown Haxe target $target" >&2; exit 1 ;;
esac
if [[ "$graphics" == graphics && "$target" == c ]]; then
  for lib in hxn hxn-window hxn-gpu-metal; do cp "$(haxelib libpath "$lib")/LICENSE" "licenses/$lib.txt"; done
fi
if [[ "$graphics" == graphics && "$target" == c && "$action" == build ]]; then
  bash "$root/scripts/bundle-hlc.sh" "$stage" "$name"
fi
