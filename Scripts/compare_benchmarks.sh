#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    echo "Usage: $0 BASELINE.json CANDIDATE.json [OUTPUT.json]" >&2
    exit 2
fi

baseline_path="${1:A}"
candidate_path="${2:A}"
if [[ ! -f "$baseline_path" ]]; then
    echo "error: Baseline report does not exist: $baseline_path" >&2
    exit 2
fi
if [[ ! -f "$candidate_path" ]]; then
    echo "error: Candidate report does not exist: $candidate_path" >&2
    exit 2
fi

if [[ "$#" == 3 ]]; then
    output_path="${3:A}"
else
    baseline_name="${baseline_path:t:r}"
    candidate_name="${candidate_path:t:r}"
    output_path="${candidate_path:h}/comparison-${baseline_name}-to-${candidate_name}.json"
fi

sdk_path="${SPACELENS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
swiftc \
    -O \
    -parse-as-library \
    -sdk "$sdk_path" \
    -module-cache-path "$temporary_dir/module-cache" \
    "$project_dir/Scripts/BenchmarkComparison.swift" \
    "$project_dir/Scripts/CompareBenchmarks.swift" \
    -o "$temporary_dir/CompareBenchmarks"

"$temporary_dir/CompareBenchmarks" "$baseline_path" "$candidate_path" "$output_path"
