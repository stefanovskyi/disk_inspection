#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
policy_matrix="${SPACELENS_BENCHMARK_VOLUME_POLICY_MATRIX:-sequential:1:8,conservative:2:8,higher-readers:2:12,higher-operations:3:8}"
sweep_id="${SPACELENS_BENCHMARK_SWEEP_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

if [[ "${SPACELENS_BENCHMARK_INCLUDE_UNRESTRICTED:-0}" == "1" ]]; then
    policy_matrix+=",unrestricted:3:24"
fi

for policy in ${(s:,:)policy_matrix}; do
    parts=(${(s/:/)policy})
    if (( ${#parts} != 3 )) \
        || [[ ! "${parts[2]}" =~ '^[1-9][0-9]*$' ]] \
        || [[ ! "${parts[3]}" =~ '^[1-9][0-9]*$' ]]; then
        echo "error: volume policies must use name:active-scans:directory-readers." >&2
        exit 2
    fi
    name="${parts[1]}"
    active_scans="${parts[2]}"
    directory_readers="${parts[3]}"

    echo "Running $name: $active_scans active volume scan(s), $directory_readers directory readers"
    SPACELENS_BENCHMARK_FIXTURES="multi-volume" \
    SPACELENS_BENCHMARK_PARALLELISM="$directory_readers" \
    SPACELENS_BENCHMARK_VOLUME_SCAN_LIMIT="$active_scans" \
    SPACELENS_BENCHMARK_RUN_ID="$sweep_id-$name" \
        "$project_dir/Scripts/run_benchmarks.sh"
done

echo "Volume policy sweep complete: $sweep_id"
