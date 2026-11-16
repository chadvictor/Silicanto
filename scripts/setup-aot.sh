#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -sm) == "Darwin arm64" ]] || { echo "Requires macOS arm64" >&2; exit 1; }
mkdir -p .toolchain/aot
root="$PWD"
cd .toolchain/aot
fetch() {
  local url=$1 dest=$2 sha=$3
  if ! [[ -f "$dest" ]] || ! echo "$sha  $dest" | shasum -a 256 --status -c; then
    curl -fLsS --retry 3 "$url" -o "$dest.part"
    echo "$sha  $dest.part" | shasum -a 256 --status -c
    mv "$dest.part" "$dest"
  fi
}
fetch https://codeload.github.com/facebook/hermes/tar.gz/6792d10598749ac5fafe795ae149831aefe10a7f hermes.tar.gz b59d1fdd1ea46c640f5413bd7e876cc1cd386a969c4aeed6f00b13d2125f8718
fetch https://registry.npmjs.org/expo-gl/-/expo-gl-58.0.4.tgz expo.tgz 9e02a6bf151bf9a3e48540e54d6fdf4dc80270898707604d61d851c3f3693ba1
fetch https://github.com/electron/electron/releases/download/v39.0.0/electron-v39.0.0-darwin-arm64.zip angle.zip 678e51190e5b29af4eb5842d4724db35409efb706ce17b1a40faf823720a9c70
mkdir -p hermes expo libraries objects
[[ -f hermes/CMakeLists.txt ]] || tar xzf hermes.tar.gz --strip-components=1 -C hermes
tar xzf expo.tgz --strip-components=1 -C expo
unzip -joq angle.zip '*/Libraries/libEGL.dylib' '*/Libraries/libGLESv2.dylib' -d libraries
unzip -p angle.zip LICENSES.chromium.html > libraries/CHROMIUM-LICENSES.html
unzip -p angle.zip LICENSE > libraries/Electron-LICENSE
angle=46005797c554ed7712b9f60939d231e00572e309
for h in EGL/egl.h EGL/eglext.h EGL/eglplatform.h EGL/eglext_angle.h GLES3/gl3.h GLES3/gl3platform.h GLES2/gl2ext.h GLES2/gl2ext_angle.h KHR/khrplatform.h; do
  mkdir -p "include/$(dirname "$h")"
  curl -fLsS --retry 3 "https://raw.githubusercontent.com/google/angle/$angle/include/$h" -o "include/$h"
done
python3 "$root/scripts/prepare-aot.py" "$PWD"
[[ -x build-tools/bin/cmake ]] || { python3 -m venv build-tools && build-tools/bin/pip install cmake==3.31.6 ninja==1.11.1.4; }
export PATH="$PWD/build-tools/bin:$PATH"
cmake -S hermes -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang -DHERMES_ENABLE_INTL=OFF -DHERMES_BUILD_APPLE_FRAMEWORK=OFF
cmake --build build --target shermes hermesvm -j 8
for source in expo/common/*.cpp; do
  clang++ -std=c++20 -O2 -DNDEBUG -Iinclude -Ihermes/API/jsi -include expo/common/pch.h -c "$source" -o "objects/$(basename "$source" .cpp).o"
done
libtool -static -o libraries/libexgl.a objects/EX*.o
