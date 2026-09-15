#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
background="$project_dir/Support/Installer/SpaceLensDMGBackground.tiff"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/spacelens-dmg-test.XXXXXX")"

trap 'rm -rf "$temporary_dir"' EXIT

fail() {
    echo "DMG packaging test failed: $1" >&2
    exit 1
}

zsh -n \
    "$project_dir/Scripts/package_dmg.sh" \
    "$project_dir/Scripts/verify_dmg.sh" \
    "$project_dir/Scripts/test_dmg_packaging.sh"

osacompile \
    -o "$temporary_dir/configure-dmg.scpt" \
    "$project_dir/Scripts/configure_dmg.applescript"

[[ -f "$background" ]] || fail "installer background is missing"
background_info="$(tiffutil -info "$background")"
[[ "$background_info" == *"Image Width: 720 Image Length: 440"* ]] || fail "1x background is not 720 x 440"
[[ "$background_info" == *"Image Width: 1440 Image Length: 880"* ]] || fail "2x background is not 1440 x 880"

echo "DMG packaging tests passed"
