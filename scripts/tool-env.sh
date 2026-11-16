#!/bin/bash
# Source this file from bash before invoking the pinned Haxe tools.
threec_tools=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.toolchain" && pwd)
export PATH="$threec_tools/haxe:$threec_tools/neko:$PATH"
export HAXE_STD_PATH="$threec_tools/haxe/std"
export HAXELIB_PATH="$threec_tools/lib"
export HXCPP="$threec_tools/hxcpp-4.3.184"
export NEKOPATH="$threec_tools/neko"
export DYLD_LIBRARY_PATH="$threec_tools/neko${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export HXCPP_CONFIG="$threec_tools/hxcpp-config.xml"
export HXCPP_COMPILE_CACHE="$threec_tools/cache"
