#!/bin/bash
set -euo pipefail
payload=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$payload/../.." && pwd)
stage=$1 profile=$2 mode=$3 name=$4
source "$root/scripts/haxe-env.sh"
[[ -e "$root/.toolchain/lib/hxjava/.dev" ]] || { echo 'Run npm run setup:java first' >&2; exit 1; }
cd "$stage"
args=(-cp haxe -main Sample)
if [[ -f haxe/WebWindow.hx ]]; then args+=(-D silicanto_window); fi
if [[ "$profile" == graphics ]]; then
  mkdir -p java/host java/resources/shaders
  cp "$payload/haxe/DesktopSurface.hx" java/host/
  # Projects emitted before the desktop host contract used a Metal-only Host.
  if [[ ! -f haxe/DesktopSurface.hx ]]; then
    cp "$root/runtime/legacy/three/"{Host,FrameUniforms}.hx java/host/
  fi
  args+=(-cp java/host)
  cp haxe/{box,scene}.metal java/resources/shaders/
fi
haxe "${args[@]}" --java java -D no-compilation
rm -f java/hxjava_build.txt
if [[ -f haxe/WebWindow.hx ]]; then cp -R "$root/payloads/canvas/java/org" java/src/; fi
cp "$root/.toolchain/hxjava-4.2.0/LICENSE" licenses/hxjava.txt
cp "$root/licenses/haxe-std.txt" licenses/haxe-std.txt
if [[ "$profile" == graphics ]]; then
  cp -R "$payload/src/org" java/src/
  cp -R "$payload/native" java/
fi
[[ "$mode" == build ]] || exit 0
source "$root/scripts/jdk-env.sh"
if [[ "$profile" == graphics && "$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *os.arch = //p')" != aarch64 ]]; then
  echo "The macOS Metal payload needs an ARM64 JDK; check JAVA_HOME." >&2; exit 1
fi
work=$(mktemp -d "$stage/.javac-XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/classes" "$work/headers"
# Only relative generated file names enter the javac argument file.
find java/src -name '*.java' > "$work/sources"
javac --release 17 -encoding UTF-8 -d "$work/classes" -h "$work/headers" @"$work/sources"
if [[ "$profile" == graphics ]]; then
  libdir="$work/classes/native/macos-arm64"
  mkdir -p "$libdir"
  xcrun clang++ -std=c++17 -O2 -arch arm64 -dynamiclib -fobjc-arc \
    -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/darwin" -I"$work/headers" \
    -framework Metal -framework Foundation java/native/MetalDisplay.mm -o "$libdir/libsilicanto_metal.dylib"
  cp -R java/resources/. "$work/classes/"
fi
if [[ -f haxe/WebGLNative.hx && "$(uname -sm)" == "Darwin arm64" ]]; then
  bash "$root/scripts/setup-webgl.sh"
  bash "$root/payloads/webgl/macos/build.sh" "$work/classes/native/webgl/macos-arm64" java
fi
mkdir -p "$work/classes/META-INF/licenses"
cp licenses/* "$work/classes/META-INF/licenses/"
jar --create --file "java/$name.jar" --main-class haxe.root.Sample -C "$work/classes" .
if [[ "$profile" == graphics ]]; then
  mkdir -p "$work/package"
  cp "java/$name.jar" "$work/package/"
  jpackage --type app-image --name "$name" --input "$work/package" --main-jar "$name.jar" \
    --add-modules java.desktop,java.management --dest "$stage"
fi
