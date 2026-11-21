#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -m)" != arm64 ]]; then
  echo "Build on an Apple Silicon Mac with a native terminal." >&2
  exit 1
fi

mkdir -p build
stage=$(mktemp -d "$PWD/build/.staging.XXXXXX")
trap 'rm -rf "$stage"' EXIT

app="$stage/TorneHelper.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"

cp Resources/AppIcon.icns "$app/Contents/Resources/"
xcrun swiftc -swift-version 5 Sources/Restart/main.swift -o "$app/Contents/MacOS/TorneReturn"
xcrun swiftc -swift-version 5 Sources/Helper/*.swift -o "$app/Contents/MacOS/TorneHelper"

codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
if [[ -e build/TorneHelper.app ]]; then
  mv build/TorneHelper.app "$stage/previous.app"
fi
if ! mv "$app" build/TorneHelper.app; then
  if [[ -e "$stage/previous.app" ]]; then
    mv "$stage/previous.app" build/TorneHelper.app
  fi
  exit 1
fi
printf '\nBuilt: %s/build/TorneHelper.app\n' "$PWD"
