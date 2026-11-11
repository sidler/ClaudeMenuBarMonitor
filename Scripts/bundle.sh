#!/bin/sh
# Builds ClaudeMonitor.app. Usage: Scripts/bundle.sh [debug|release]
set -eu

config="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)"
app="$root/build/ClaudeMonitor.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/ClaudeMonitor" "$app/Contents/MacOS/ClaudeMonitor"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

# Ad-hoc signature: enough locally, including notifications and the login item.
codesign --force --sign - "$app" >/dev/null

echo "Done: $app"
echo "Run with: open \"$app\""
