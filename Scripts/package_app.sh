#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
build_dir="$project_dir/.build/$configuration"
app_dir="$project_dir/dist/SpaceLens.app"
contents_dir="$app_dir/Contents"

cd "$project_dir"
swift build -c "$configuration"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$build_dir/SpaceLens" "$contents_dir/MacOS/SpaceLens"

sed "s/@VERSION@/1.0.0/g" "$project_dir/Support/Info.plist.in" > "$contents_dir/Info.plist"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
