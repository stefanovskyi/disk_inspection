#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
dmg_path="${1:-$project_dir/dist/SpaceLens.dmg}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/spacelens-dmg-verify.XXXXXX")"
mount_dir="$temporary_dir/mount"
is_mounted=false

cleanup() {
    if [[ "$is_mounted" == true ]]; then
        hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary_dir"
}

fail() {
    echo "DMG verification failed: $1" >&2
    exit 1
}

trap cleanup EXIT

[[ -f "$dmg_path" ]] || fail "image not found: $dmg_path"

hdiutil verify "$dmg_path" >/dev/null
mkdir -p "$mount_dir"
hdiutil attach \
    "$dmg_path" \
    -readonly \
    -noverify \
    -noautoopen \
    -mountpoint "$mount_dir" >/dev/null
is_mounted=true

[[ -d "$mount_dir/SpaceLens.app" ]] || fail "SpaceLens.app is missing"
[[ -L "$mount_dir/Applications" ]] || fail "Applications link is missing"
[[ "$(readlink "$mount_dir/Applications")" == "/Applications" ]] || fail "Applications link has the wrong target"
[[ -f "$mount_dir/.background/SpaceLensDMGBackground.tiff" ]] || fail "installer background is missing"
[[ -f "$mount_dir/.DS_Store" ]] || fail "Finder layout metadata is missing"

codesign --verify --deep --strict --verbose=2 "$mount_dir/SpaceLens.app"
plutil -lint "$mount_dir/SpaceLens.app/Contents/Info.plist" >/dev/null

hdiutil detach "$mount_dir" >/dev/null
is_mounted=false

echo "DMG verification passed: $dmg_path"
