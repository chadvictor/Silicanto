#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
archive=angle-macos-arm64-a96fca8d5ee2ca61e8de419e38cd577579281c9e.tar.gz
digest=c8d1f7e51ae89a21cf4caafd0405430dce498e97f9080cdf9c1e265cccb0148e
dest="$root/.toolchain/angle"
[[ "$(uname -sm)" == "Darwin arm64" ]] || { echo 'This ANGLE payload requires Apple Silicon.' >&2; exit 1; }
[[ -f "$dest/.revision" && "$(cat "$dest/.revision")" == "$digest" ]] && exit 0
mkdir -p "$root/.toolchain/downloads" "$dest"
pkg="$root/.toolchain/downloads/$archive"
if [[ ! -f "$pkg" ]]; then
  temp=$(mktemp "$pkg.XXXXXX")
  trap 'rm -f "$temp"' EXIT
  curl -fL --retry 3 "https://github.com/yorickreum/angle-libs/releases/download/a96fca8/$archive" -o "$temp"
  shasum -a 256 -c <<< "$digest  $temp"
  mv "$temp" "$pkg"
fi
shasum -a 256 -c <<< "$digest  $pkg"
tar xzf "$pkg" -C "$dest" --strip-components=1
echo "$digest" > "$dest/.revision"
