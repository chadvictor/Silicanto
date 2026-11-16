#!/bin/bash
set -euo pipefail
stage=$1
name=$2
bundle="$stage/$name.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Frameworks" "$bundle/Resources"
cp "$stage/c/$name" "$bundle/MacOS/"
cp "$stage/c/lib/"* "$bundle/Frameworks/"
install_name_tool -rpath @executable_path/lib @executable_path/../Frameworks "$bundle/MacOS/$name"
if [[ -d "$stage/assets" ]]; then cp -R "$stage/assets" "$bundle/Resources/"; fi
cp -R "$stage/licenses" "$bundle/Resources/"
plutil -create xml1 "$bundle/Info.plist"
plutil -insert CFBundleExecutable -string "$name" "$bundle/Info.plist"
plutil -insert CFBundleName -string "$name" "$bundle/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Info.plist"
plutil -insert CFBundleIdentifier -string "org.silicanto.$name" "$bundle/Info.plist"
for lib in "$bundle/Frameworks/"*; do codesign --force --sign - "$lib"; done
codesign --force --sign - "$stage/$name.app"
