#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
build_dir="$project_dir/.build/$configuration"
app_dir="$project_dir/dist/SpaceLens.app"
contents_dir="$app_dir/Contents"
icon_source="$project_dir/Support/SpaceLensIcon.png"
signing_identity="$("$project_dir/Scripts/resolve_signing_identity.sh")"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/spacelens-package.XXXXXX")"
iconset_dir="$temporary_dir/SpaceLens.iconset"

trap 'rm -rf "$temporary_dir"' EXIT

cd "$project_dir"
swift build -c "$configuration"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$build_dir/SpaceLens" "$contents_dir/MacOS/SpaceLens"
cp "$project_dir/Support/PrivacyInfo.xcprivacy" "$contents_dir/Resources/PrivacyInfo.xcprivacy"

mkdir -p "$iconset_dir"
for icon_size in 16 32 128 256 512; do
    sips --resampleHeightWidth "$icon_size" "$icon_size" "$icon_source" \
        --out "$iconset_dir/icon_${icon_size}x${icon_size}.png" >/dev/null

    double_size=$((icon_size * 2))
    sips --resampleHeightWidth "$double_size" "$double_size" "$icon_source" \
        --out "$iconset_dir/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$contents_dir/Resources/SpaceLens.icns" "$iconset_dir"

sed "s/@VERSION@/1.2.0/g" "$project_dir/Support/Info.plist.in" > "$contents_dir/Info.plist"
codesign --force --deep --sign "$signing_identity" "$app_dir"

if [[ "$signing_identity" == "-" ]]; then
    echo "warning: SpaceLens was ad-hoc signed." >&2
    echo "warning: macOS privacy choices can be requested again after the executable changes." >&2
    echo "warning: Create the 'SpaceLens Local Development' code-signing identity or set SPACELENS_CODESIGN_IDENTITY." >&2
else
    echo "Signed with stable identity: $signing_identity" >&2
fi

echo "$app_dir"
