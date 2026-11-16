#!/bin/bash
set -euo pipefail
[[ $(uname -sm) == 'Darwin arm64' ]] || { echo 'This target requires macOS on Apple Silicon.' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)/.toolchain
mkdir -p "$root/downloads" "$root/haxe" "$root/neko" "$root/lib/hxcpp"
cd "$root/downloads"
fetch() {
  local file=$1 sha=$2 url=$3
  if [[ ! -f "$file" ]] || ! echo "$sha  $file" | shasum -a 256 --check --status; then
    curl --fail --location --retry 2 "$url" -o "$file.part"
    echo "$sha  $file.part" | shasum -a 256 --check
    mv "$file.part" "$file"
  fi
}
fetch haxe.tar.gz 1d355cb28bc25784b33acce023caeb28d50ccb14e953134a62b889697947efdc https://github.com/HaxeFoundation/haxe/releases/download/4.3.7/haxe-4.3.7-osx.tar.gz
fetch neko.tar.gz 511fe81fa73fa813464b4e0296ec1e7121d6a6434ca25df59e7ba19849a64173 https://github.com/HaxeFoundation/neko/releases/download/v2-4-1/neko-2.4.1-osx-arm64.tar.gz
fetch hxcpp.zip 2b3c53ffbebae544a83bf3dec3f74a77157305fcb95cc099d902925ad75f409d https://github.com/HaxeFoundation/hxcpp/releases/download/v4.3.184/hxcpp-4.3.184.zip
tar -xzf haxe.tar.gz -C "$root/haxe" --strip-components=1
tar -xzf neko.tar.gz -C "$root/neko" --strip-components=1
unzip -qo hxcpp.zip -d "$root"
printf '%s\n' "$root/hxcpp-4.3.184" > "$root/lib/hxcpp/.dev"
printf '%s\n' '<xml />' > "$root/hxcpp-config.xml"
install_hxn() {
  local name=$1 version=$2 archive=$3 sha=$4
  fetch "$archive" "$sha" "https://github.com/hx-n/$name/releases/download/v$version/$archive"
  mkdir -p "$root/lib/$name" "$root/$name-$version"
  unzip -qo "$archive" -d "$root/$name-$version"
  printf '%s\n' "$root/$name-$version" > "$root/lib/$name/.dev"
}
install_hxn hxn 0.3.5 hxn-haxelib-0.3.5.zip c5a13d759cb5962138ce8630e6d9ab68fc0adbeb34df3dc3e2614f5d298fd8d6
install_hxn hxn-window 0.2.0 hxn-window-0.2.0.zip 8d22773500cb53ee85a3a27ac4b56427f130f315b622d062ece8597d9f625912
# Haxe invokes haxelib through a system shell on macOS. DYLD_* is stripped there.
chmod u+w "$root/haxe/haxelib"
install_name_tool -add_rpath '@executable_path/../neko' "$root/haxe/haxelib"
codesign --force --sign - "$root/haxe/haxelib"
install_hxn hxn-gpu-metal 0.2.0 hxn-gpu-metal-0.2.0.zip dd4f5baf4f68d7e5a117e57fd623598802350cc4233ef1bd3f43a3393e9e45f2
echo "Installed the Haxe toolchain and Metal libraries in $root"
