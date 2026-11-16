# Use the pinned checkout toolchain when present, otherwise use a matching Haxe on PATH.
if [[ -x "$root/.toolchain/haxe/haxe" ]]; then
  source "$root/scripts/tool-env.sh"
else
  export HAXELIB_PATH="$root/.toolchain/lib"
fi
if ! command -v haxe >/dev/null || [[ "$(haxe --version)" != 4.3.7 ]]; then
  echo "Install Haxe 4.3.7 (npm run setup:mac on Apple Silicon) first." >&2; exit 1
fi
