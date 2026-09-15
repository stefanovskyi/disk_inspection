#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
volume_name="SpaceLens"
app_dir="$project_dir/dist/SpaceLens.app"
output_dmg="$project_dir/dist/SpaceLens.dmg"
background_source="$project_dir/Support/Installer/SpaceLensDMGBackground.tiff"
layout_script="$project_dir/Scripts/configure_dmg.applescript"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/spacelens-dmg.XXXXXX")"
staging_dir="$temporary_dir/staging"
read_write_dmg="$temporary_dir/SpaceLens-read-write.dmg"
compressed_dmg="$temporary_dir/SpaceLens.dmg"
mount_dir="/Volumes/$volume_name"
is_mounted=false

cleanup() {
    if [[ "$is_mounted" == true ]]; then
        hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary_dir"
}

trap cleanup EXIT

if [[ ! -d "$app_dir" ]]; then
    echo "error: $app_dir does not exist; run make app first." >&2
    exit 1
fi

if [[ ! -f "$background_source" ]]; then
    echo "error: installer background is missing: $background_source" >&2
    exit 1
fi

if [[ -e "$mount_dir" ]]; then
    echo "error: $mount_dir is already mounted; eject it before building the installer." >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist" >/dev/null

mkdir -p "$staging_dir/.background"
ditto "$app_dir" "$staging_dir/SpaceLens.app"
ln -s /Applications "$staging_dir/Applications"
cp "$background_source" "$staging_dir/.background/SpaceLensDMGBackground.tiff"
chflags hidden "$staging_dir/.background"

hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$read_write_dmg" >/dev/null

hdiutil attach \
    "$read_write_dmg" \
    -readwrite \
    -noverify \
    -noautoopen >/dev/null
is_mounted=true

osascript "$layout_script" "$volume_name" "$mount_dir"
sync
hdiutil detach "$mount_dir" >/dev/null
is_mounted=false

hdiutil convert \
    "$read_write_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$compressed_dmg" >/dev/null

mkdir -p "$project_dir/dist"
mv -f "$compressed_dmg" "$output_dmg"
"$project_dir/Scripts/verify_dmg.sh" "$output_dmg"

echo "$output_dmg"
