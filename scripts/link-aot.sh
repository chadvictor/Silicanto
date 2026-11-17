#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
stage=$1
name=$2
bundle="$stage/$name.app/Contents"
mac="$bundle/MacOS"
libs="$bundle/Frameworks"
licenses="$bundle/Resources/licenses"
mkdir -p "$mac" "$libs" "$licenses"
cd .toolchain/aot
cp libraries/{libEGL,libGLESv2}.dylib build/lib/libhermesvm.dylib "$libs/"
for lib in libEGL libGLESv2; do
  install_name_tool -id "@rpath/$lib.dylib" "$libs/$lib.dylib"
done
clang -O1 -DNDEBUG -fno-strict-aliasing -fno-strict-overflow -Ihermes/include -Ihermes/public -Ibuild/lib/config -c "$stage/app.c" -o "$stage/app.o"
clang++ -std=c++20 -fobjc-arc -DNDEBUG -O2 -Iinclude -Ihermes/API/jsi -Ihermes/API -Ihermes/public -Iexpo/common -include expo/common/pch.h "$root/runtime/legacy/three/aot/host.mm" "$stage/app.o" libraries/libexgl.a -L"$libs" -lhermesvm -lEGL -lGLESv2 -framework AppKit -framework QuartzCore -Wl,-rpath,@executable_path/../Frameworks -o "$mac/$name"
cp hermes/LICENSE "$licenses/hermes.txt"
cp expo/LICENSE "$licenses/expo-gl.txt"
cp "$root/node_modules/three/LICENSE" "$licenses/three.txt"
cp libraries/{CHROMIUM-LICENSES.html,Electron-LICENSE} "$licenses/"
plutil -create xml1 "$bundle/Info.plist"
plutil -insert CFBundleExecutable -string "$name" "$bundle/Info.plist"
plutil -insert CFBundleName -string "$name" "$bundle/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Info.plist"
plutil -insert CFBundleIdentifier -string "org.silicanto.$name" "$bundle/Info.plist"
for lib in "$libs"/*.dylib; do codesign -fs - "$lib"; done
codesign -fs - "$stage/$name.app"
