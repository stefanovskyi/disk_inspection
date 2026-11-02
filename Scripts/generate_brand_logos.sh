#!/bin/zsh

# Regenerates the bundled brand-logo PNGs from the pinned sources listed in
# Support/BrandLogos/sources.tsv. Only needed when adding or updating a logo.
# Requires network access, npm, gh, rsvg-convert, and ImageMagick.

set -euo pipefail

project_dir="${0:A:h:h}"
manifest="$project_dir/Support/BrandLogos/sources.tsv"
output_dir="${1:-$project_dir/Sources/SpaceLens/Resources/BrandLogos}"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/spacelens-logos.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

# Lifecycle scripts stay disabled: packages are only unpacked for their SVGs.
fetch() {
    local spec="$1" kind="${1%%:*}" rest="${1#*:}"
    local reference="${rest%%:*}" asset="${rest#*:}"
    local cache="$temporary_dir/$(print -r -- "$reference" | tr '/@' '__')"
    if [[ ! -d "$cache" ]]; then
        mkdir -p "$cache"
        if [[ "$kind" == npm ]]; then
            (cd "$cache" && npm pack "$reference" --silent --ignore-scripts >/dev/null && tar xzf ./*.tgz)
        fi
    fi
    if [[ "$kind" == npm ]]; then
        print -r -- "$cache/package/$asset"
    else
        local target="$cache/$(print -r -- "$asset" | tr '/' '_')"
        [[ -f "$target" ]] || curl -sSfL -o "$target" \
            "https://raw.githubusercontent.com/${reference%%@*}/${reference##*@}/$asset"
        print -r -- "$target"
    fi
}

mkdir -p "$output_dir"
while IFS=$'\t' read -r slug source fill; do
    [[ -z "$slug" || "$slug" == \#* ]] && continue
    svg="$(fetch "$source")"
    if [[ -n "$fill" ]]; then
        sed "s/<svg /<svg fill=\"$fill\" /" "$svg" > "$temporary_dir/filled.svg"
        svg="$temporary_dir/filled.svg"
    fi
    rsvg-convert --width 256 --height 256 --keep-aspect-ratio "$svg" \
        --output "$temporary_dir/rendered.png"
    magick "$temporary_dir/rendered.png" -background none -gravity center -extent 256x256 \
        -strip -define png:exclude-chunks=date,time "PNG32:$output_dir/$slug.png"
done < "$manifest"
