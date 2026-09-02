#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
parallelism_values="${SPACELENS_BENCHMARK_PARALLELISMS:-1,2,4,8,16}"
sweep_id="${SPACELENS_BENCHMARK_SWEEP_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

for value in ${(s:,:)parallelism_values}; do
    if [[ ! "$value" =~ '^[1-9][0-9]*$' ]]; then
        echo "error: SPACELENS_BENCHMARK_PARALLELISMS must be a comma-separated list of positive integers." >&2
        exit 2
    fi

    echo "Running scanner parallelism $value"
    SPACELENS_BENCHMARK_PARALLELISM="$value" \
    SPACELENS_BENCHMARK_RUN_ID="$sweep_id-p$value" \
        "$project_dir/Scripts/run_benchmarks.sh"
done

echo "Parallelism sweep complete: $sweep_id"
