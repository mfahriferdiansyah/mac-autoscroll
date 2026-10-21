#!/bin/bash
# Build AutoScroll.app, install it to ~/Applications and launch it.
# `./build.sh --build-only` stops after building build/AutoScroll.app.
# `./build.sh --dmg` also packages build/AutoScroll.dmg (drag-to-Applications) and stops.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/AutoScroll.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp assets/AppIcon.icns "$APP/Contents/Resources/"
# Some Command Line Tools installs ship a stale usr/include/swift/module.modulemap that
# duplicates bridging.modulemap and breaks `import AppKit`; hide it with an empty overlay.
: > build/empty.modulemap
cat > build/overlay.yaml <<YAML
{ "version": 0, "roots": [ { "type": "file",
  "name": "$(xcode-select -p)/usr/include/swift/module.modulemap",
  "external-contents": "$PWD/build/empty.modulemap" } ] }
YAML
# Universal binary (Apple Silicon + Intel) for macOS 13+, matching LSMinimumSystemVersion.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -vfsoverlay build/overlay.yaml -target "$arch-apple-macos13.0" \
    -o "build/AutoScroll-$arch" Sources/main.swift
done
lipo -create build/AutoScroll-arm64 build/AutoScroll-x86_64 -output "$APP/Contents/MacOS/AutoScroll"
codesign --force --sign - "$APP"
[ "${1:-}" = "--build-only" ] && exit 0
if [ "${1:-}" = "--dmg" ]; then
  mkdir build/dmg
  cp -R "$APP" build/dmg/
  ln -s /Applications build/dmg/Applications
  hdiutil create -quiet -volname AutoScroll -srcfolder build/dmg -ov -format UDZO build/AutoScroll.dmg
  echo "Packaged build/AutoScroll.dmg"
  exit 0
fi

pkill -x AutoScroll || true
mkdir -p ~/Applications
rm -rf ~/Applications/AutoScroll.app
cp -R "$APP" ~/Applications/
open ~/Applications/AutoScroll.app
echo "Installed and launched ~/Applications/AutoScroll.app"
