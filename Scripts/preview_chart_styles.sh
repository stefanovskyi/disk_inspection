#!/bin/zsh

# Throwaway chart lab. A separate bundle identity keeps the running app untouched.
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
swift build

preview_dir="$project_dir/.build/chart-style-prototype"
app_dir="$preview_dir/SpaceLens.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/debug/SpaceLens" "$app_dir/Contents/MacOS/SpaceLens"
cp -R "$project_dir/.build/debug/SpaceLens_SpaceLens.bundle" "$app_dir/Contents/Resources/"
sed 's/@VERSION@/1.3.0/g' "$project_dir/Support/Info.plist.in" > "$app_dir/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.spacelens.chart-style-prototype "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
open -n "$app_dir" --args --chart-style-prototype
