#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache dist
build_stage=$(mktemp -d "$PWD/.build/stage.XXXXXX")
trap 'rm -rf "$build_stage"' EXIT
app_path="$build_stage/Still Focus.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/StillFocus.icns "$app_path/Contents/Resources/StillFocus.icns"
# A universal binary supports Apple silicon and Intel Macs.
for cpu in arm64 x86_64; do
    xcrun swiftc Source/main.swift -module-cache-path .build/cache \
        -target "$cpu-apple-macosx14.0" -framework Cocoa -framework SwiftUI -framework Charts \
        -o "$build_stage/StillFocus-$cpu"
done
xcrun lipo -create "$build_stage/StillFocus-arm64" "$build_stage/StillFocus-x86_64" \
    -output "$app_path/Contents/MacOS/StillFocus"
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
# Only build output is replaced; personal history is outside this directory.
if [[ -d "dist/Still Focus.app" ]]; then
    mv "dist/Still Focus.app" "$build_stage/previous.app"
fi
mv "$app_path" "dist/Still Focus.app"
print 'Built dist/Still Focus.app (Apple silicon + Intel). Quit any old version before opening it.'
