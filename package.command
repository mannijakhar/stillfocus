#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.command
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
mkdir -p downloads
archive="Still-Focus-${version}-macOS-universal.zip"
ditto -c -k --norsrc --noextattr --keepParent "dist/Still Focus.app" "downloads/$archive"
(cd downloads && shasum -a 256 "$archive" > SHA256SUMS.txt)
print "Packaged downloads/$archive"
