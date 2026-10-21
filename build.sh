#!/bin/bash
# Build AutoScroll.app, install it to ~/Applications and launch it.
# `./build.sh --build-only` stops after building build/AutoScroll.app.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/AutoScroll.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
# Some Command Line Tools installs ship a stale usr/include/swift/module.modulemap that
# duplicates bridging.modulemap and breaks `import AppKit`; hide it with an empty overlay.
: > build/empty.modulemap
cat > build/overlay.yaml <<YAML
{ "version": 0, "roots": [ { "type": "file",
  "name": "$(xcode-select -p)/usr/include/swift/module.modulemap",
  "external-contents": "$PWD/build/empty.modulemap" } ] }
YAML
swiftc -O -swift-version 5 -vfsoverlay build/overlay.yaml -o "$APP/Contents/MacOS/AutoScroll" Sources/main.swift
codesign --force --sign - "$APP"
[ "${1:-}" = "--build-only" ] && exit 0

pkill -x AutoScroll || true
mkdir -p ~/Applications
rm -rf ~/Applications/AutoScroll.app
cp -R "$APP" ~/Applications/
open ~/Applications/AutoScroll.app
echo "Installed and launched ~/Applications/AutoScroll.app"
