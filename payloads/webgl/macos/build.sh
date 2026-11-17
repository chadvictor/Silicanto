#!/bin/bash
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/../../.." && pwd)
dest=$1
angle="$root/.toolchain/angle"
mkdir -p "$dest"
cp "$angle/libEGL.dylib" "$angle/libGLESv2.dylib" "$dest/"
for lib in libEGL libGLESv2; do
  install_name_tool -id "@rpath/$lib.dylib" "$dest/$lib.dylib"
  codesign --force --sign - "$dest/$lib.dylib" 2>/dev/null
done
native=("$dir/Dispatch.mm")
if [[ ${2:-} == java ]]; then
  native+=("$dir/Jni.cpp" "-I$JAVA_HOME/include" "-I$JAVA_HOME/include/darwin")
fi
xcrun clang++ -std=c++17 -mmacosx-version-min=12.0 -fobjc-arc -O2 -dynamiclib -install_name @rpath/libsilicanto_webgl.dylib \
  "-I$angle/include" "${native[@]}" "-L$dest" -lEGL -lGLESv2 \
  -framework Foundation -Wl,-rpath,@loader_path -Wno-objc-method-access -o "$dest/libsilicanto_webgl.dylib"
cp "$angle/LICENSE" "$dest/ANGLE-LICENSE.txt"
