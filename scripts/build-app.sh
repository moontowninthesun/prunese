#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "$0")/.."

swift build --configuration release --arch arm64
binary_dir=$(swift build --configuration release --arch arm64 --show-bin-path)
app="$PWD/dist/Prunese.app"
mkdir -p "$app/Contents/MacOS"
install -m 0755 "$binary_dir/Prunese" "$app/Contents/MacOS/Prunese"
install -m 0644 App/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf '%s\n' "$app"
