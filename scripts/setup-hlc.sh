#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -sm) == 'Darwin arm64' ]] || { echo 'Native C build currently targets macOS arm64.' >&2; exit 1; }
mkdir -p .toolchain/hl
cd .toolchain/hl
sha=c392ce6e1d3670bcb60c85d83a161591707de9cdb6b00b48e79f9ea7807fc5a9
if ! echo "$sha  src.tgz" | shasum -a 256 --status -c 2>/dev/null; then
  curl -fLsS --retry 2 https://codeload.github.com/HaxeFoundation/hashlink/tar.gz/refs/tags/1.16 -o src.tgz.part
  echo "$sha  src.tgz.part" | shasum -a 256 -c
  mv src.tgz.part src.tgz
fi
mkdir -p src
tar xzf src.tgz -C src --strip-components=1
make -C src -j6 libhl.dylib
