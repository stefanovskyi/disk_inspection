#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
sdk_path="${SPACELENS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"

swiftc \
    -parse-as-library \
    -sdk "$sdk_path" \
    -module-cache-path "$temporary_dir/module-cache" \
    "$project_dir/Scripts/BenchmarkComparison.swift" \
    "$project_dir/Scripts/BenchmarkComparisonTests.swift" \
    -o "$temporary_dir/BenchmarkComparisonTests"

"$temporary_dir/BenchmarkComparisonTests"
