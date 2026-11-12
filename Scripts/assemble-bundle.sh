#!/bin/sh
# Assembles ClaudeMonitor.app and signs it.
#
# Shared by the development build and the release build, which differ only in
# which identity signs and whether the hardened runtime is on. One copy means a
# change to the bundle's shape cannot reach one path and miss the other.
#
#   assemble-bundle.sh <output.app> <binary> <identifier> <sign-args...>
#
# With `--sign -` the bundle is signed ad-hoc, which is not an identity: the
# keychain and the notification centre treat every rebuild as a new app.
set -eu

app="$1"
binary="$2"
identifier="$3"
shift 3

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"

# The build number is written in here rather than kept in the repository: it has
# to rise with every build that anything might compare, and the commit count does
# that without anybody having to remember. Outside a checkout the plist's own
# value stands.
build=$(git rev-list --count HEAD 2>/dev/null || echo "")
if [ -n "$build" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
fi

cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$binary" "$app/Contents/MacOS/ClaudeMonitor"

# Nothing is nested in this bundle — no frameworks, no helpers — so one signature
# covers it. Worth knowing before adding a dependency that brings its own: those
# have to be signed from the inside out, and `--deep` is not a substitute.
codesign --force --identifier "$identifier" "$@" "$app"
