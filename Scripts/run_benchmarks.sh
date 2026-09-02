#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

sdk_path="${SPACELENS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
output_dir="${SPACELENS_BENCHMARK_OUTPUT_DIR:-$project_dir/BenchmarkResults}"
run_id="${SPACELENS_BENCHMARK_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
capture_trace="${SPACELENS_BENCHMARK_CAPTURE_TRACE:-0}"
trace_template="${SPACELENS_BENCHMARK_TRACE_TEMPLATE:-Logging}"

mkdir -p "$output_dir"

report_json_path="$output_dir/spacelens-benchmark-$run_id.json"
report_csv_path="$output_dir/spacelens-benchmark-$run_id.csv"
if [[ -e "$report_json_path" || -e "$report_csv_path" ]]; then
    echo "error: Benchmark report already exists for run ID $run_id." >&2
    exit 2
fi

if [[ "$capture_trace" != "0" && "$capture_trace" != "1" ]]; then
    echo "error: SPACELENS_BENCHMARK_CAPTURE_TRACE must be 0 or 1." >&2
    exit 2
fi

xctrace_path=""
trace_path=""
if [[ "$capture_trace" == "1" ]]; then
    xctrace_path="${SPACELENS_XCTRACE_PATH:-}"
    if [[ -z "$xctrace_path" ]]; then
        xctrace_path="$(xcrun --find xctrace 2>/dev/null || true)"
    fi
    if [[ -z "$xctrace_path" || ! -x "$xctrace_path" ]]; then
        echo "error: Instruments trace capture requires xctrace from a full Xcode installation." >&2
        echo "error: Install Xcode, select it with xcode-select, or set SPACELENS_XCTRACE_PATH." >&2
        exit 2
    fi

    trace_path="$output_dir/spacelens-benchmark-$run_id.trace"
    if [[ -e "$trace_path" ]]; then
        echo "error: Trace output already exists: $trace_path" >&2
        exit 2
    fi
    export SPACELENS_BENCHMARK_TRACE_PATH="$trace_path"
fi

git_revision="$(git -C "$project_dir" rev-parse HEAD 2>/dev/null || true)"
git_dirty="false"
if [[ -n "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ]]; then
    git_dirty="true"
fi

export SPACELENS_BENCHMARK_OUTPUT_DIR="$output_dir"
export SPACELENS_BENCHMARK_RUN_ID="$run_id"
export SPACELENS_BENCHMARK_GIT_REVISION="$git_revision"
export SPACELENS_BENCHMARK_GIT_DIRTY="$git_dirty"
export SPACELENS_BENCHMARK_SDK_PATH="$sdk_path"
export SPACELENS_BENCHMARK_SWIFT_VERSION="$(swiftc --version 2>/dev/null | head -n 1)"
export SPACELENS_BENCHMARK_TRACE_TEMPLATE="$trace_template"

swiftc \
    -O \
    -whole-module-optimization \
    -parse-as-library \
    -sdk "$sdk_path" \
    -module-cache-path "$temporary_dir/module-cache" \
    "$project_dir/Sources/SpaceLens/Models/FileNode.swift" \
    "$project_dir/Sources/SpaceLens/Models/SunburstLayout.swift" \
    "$project_dir/Sources/SpaceLens/Support/PerformanceSignposts.swift" \
    "$project_dir/Sources/SpaceLens/Services/BulkDirectoryReader.swift" \
    "$project_dir/Sources/SpaceLens/Services/DiskScanner.swift" \
    "$project_dir/Sources/SpaceLens/Services/FullDiskAccessChecker.swift" \
    "$project_dir/Scripts/BenchmarkReporting.swift" \
    "$project_dir/Scripts/Benchmarks.swift" \
    -o "$temporary_dir/SpaceLensBenchmarks"

if [[ "$capture_trace" == "1" ]]; then
    "$xctrace_path" record \
        --template "$trace_template" \
        --output "$trace_path" \
        --launch -- "$temporary_dir/SpaceLensBenchmarks"
    "$xctrace_path" export --input "$trace_path" --toc --quiet >/dev/null
    echo "JSON report: $report_json_path"
    echo "CSV report: $report_csv_path"
    echo "Instruments trace: $trace_path"
else
    "$temporary_dir/SpaceLensBenchmarks"
fi
