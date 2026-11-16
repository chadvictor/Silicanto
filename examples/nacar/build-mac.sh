#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
node src/cli.mjs build examples/nacar/main.js --out "${1:-dist/nacar-haxe}" --target c --name Nacar
