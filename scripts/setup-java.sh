#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/scripts/haxe-env.sh"
source "$root/scripts/jdk-env.sh"
tools="$root/.toolchain"
archive="$tools/downloads/hxjava-4.2.0.zip"
mkdir -p "$tools/downloads" "$tools/lib/hxjava" "$tools/hxjava-4.2.0"
if [[ ! -f "$archive" ]]; then
  curl -fLsS --retry 3 'https://lib.haxe.org/files/3.0/hxjava-4,2,0.zip' -o "$archive.tmp"
  mv "$archive.tmp" "$archive"
fi
echo "c5298509940c914c9eae89d09141bde5c66ec3f229fc5efccbac1523f2bec53b  $archive" | shasum -a 256 -c -
unzip -qo "$archive" -d "$tools/hxjava-4.2.0"
printf '%s\n' "$tools/hxjava-4.2.0" > "$tools/lib/hxjava/.dev"
echo "Ready: Haxe $(haxe --version), hxjava 4.2.0, $(javac -version)"
