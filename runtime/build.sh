#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/cpp"
: "${HXCPP:?Source scripts/tool-env.sh from the Silicanto checkout first, or configure the documented Haxe toolchain}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET=13.0
# Re-resolve native library locations when the generated project is moved.
window_dir="$(haxelib libpath hxn-window)"
metal_dir="$(haxelib libpath hxn-gpu-metal)"
neko "$HXCPP/hxcpp.n" Build.xml haxe "-DXWINDOW_INCLUDE=$window_dir/include" \
  "-DXWINDOW_LIB=$window_dir/native/aarch64-apple-darwin/libxwindow_cpp.a" \
  "-DXWINDOW_LINK=$window_dir/native/aarch64-apple-darwin/link.xml" \
  "-DGPU_METAL_INCLUDE=$metal_dir/include" "-DGPU_METAL_LIB=$metal_dir/native/aarch64-apple-darwin/libgpu_metal_cpp.a" \
  "-DGPU_METAL_LINK=$metal_dir/native/aarch64-apple-darwin/link.xml" "-DHXN_INCLUDE=$window_dir/include"

if [[ -d ../assets ]]; then mkdir -p assets; cp ../assets/* assets/; fi
