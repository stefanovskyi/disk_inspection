# SpaceLens

![macOS 14+ compatibility](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Apple Silicon arm64 architecture](https://img.shields.io/badge/architecture-Apple%20Silicon%20%28arm64%29-555555?logo=apple&logoColor=white)

SpaceLens is a native macOS disk inspector with an interactive sunburst chart. It discovers mounted internal and external volumes, scans folders without following symbolic links, and lets you drill into storage usage one directory at a time.

## Features

- Automatic mounted-volume and external-disk discovery
- Immediate startup-disk capacity overview before any folder scan begins
- Up-front Full Disk Access guidance before scanning the startup disk
- Asynchronous, cancellable folder and volume scanning
- A live sunburst preview that grows during scanning, with mapped bytes, item count, elapsed time, and estimated disk coverage
- Bounded parallel subtree scanning with pooled `getattrlistbulk(2)` metadata buffers and live elapsed time
- In-memory scan results for inspected disks and selected folders, with explicit view-or-rescan choices
- A small, bounded previous-disk snapshot that restores the last known chart on the next launch
- Mount-aware main-disk scans that avoid APFS aliases and external disks
- Bounded scan results that group smaller items instead of retaining millions of leaf nodes
- A no-progress watchdog that skips unresponsive provider-backed folders instead of freezing a whole scan
- Capacity-aware sunburst geometry with a transparent, labeled free-space sector
- Angular width mapped to bytes and radial reach mapped to folder depth
- Interactive sunburst with hover details, click-to-drill navigation, and a 200-sector rendering budget
- Chart-only **Smaller items** sectors that combine sub-1% or visually tiny entries while preserving exact byte totals
- Clickable breadcrumbs and keyboard back navigation
- Ranked item list with proportional size bars
- Finder and Terminal context-menu actions
- Clear reporting of protected or unreadable folders
- Native macOS dark/light appearance and accessibility labels

## Build

SpaceLens requires macOS 14 or newer and Swift 6 (included with current Xcode Command Line Tools).

```bash
make test
make app
open dist/SpaceLens.app
```

`make test` uses a framework-free verification harness so it also works on Macs that have only the Command Line Tools installed. The package additionally includes XCTest targets for Xcode.

You can also open `Package.swift` in Xcode and run the `SpaceLens` executable target.

## Performance benchmarks

Run the scanner and chart-layout fixtures as an optimized release executable:

```bash
make benchmark
```

Every run writes timestamped JSON and CSV reports to the ignored `BenchmarkResults/` directory. Reports include the Git revision and dirty state, SDK and compiler, macOS and hardware details, fixture configuration, scanner parallelism, peak resident memory, per-iteration results, medians, standard deviation, and variability. Iteration records also preserve scanner work counters, directory and retained-arena node counts, provider timeouts and abandoned workers, arena-construction time, resident memory immediately before and after arena construction, chart-scene construction time, and the cost of 120 cached hover lookups.

The default run measures flat, deep, mixed, and stalled-provider trees. Run three read-only startup-disk scans with:

```bash
make benchmark-full
```

The external-disk fixture is also opt-in and read-only; point it at a dedicated directory on the disk rather than the volume root:

```bash
SPACELENS_BENCHMARK_FIXTURES=external \
SPACELENS_BENCHMARK_EXTERNAL_PATH="/Volumes/TestDisk/SpaceLensFixture" \
make benchmark
```

Fixture sizes, iteration count, scanner concurrency, directory-buffer size, output location, and selected cases can be controlled with `SPACELENS_BENCHMARK_ITERATIONS`, `SPACELENS_BENCHMARK_PARALLELISM`, `SPACELENS_BENCHMARK_DIRECTORY_BUFFER_KB`, `SPACELENS_BENCHMARK_OUTPUT_DIR`, `SPACELENS_BENCHMARK_FIXTURES`, `SPACELENS_BENCHMARK_FLAT_FILES`, `SPACELENS_BENCHMARK_DEEP_DIRECTORIES`, `SPACELENS_BENCHMARK_MIXED_DEPTH`, `SPACELENS_BENCHMARK_MIXED_FANOUT`, `SPACELENS_BENCHMARK_MIXED_FILES_PER_DIRECTORY`, and `SPACELENS_BENCHMARK_PROVIDER_TIMEOUT_MS`.

Revisit the traversal scheduler with the standard parallelism sweep before changing its design:

```bash
make benchmark-parallelism
```

This runs identical benchmark fixtures at scanner parallelism 1, 2, 4, 8, and 16 and writes one report pair per value. Override the matrix with a comma-separated `SPACELENS_BENCHMARK_PARALLELISMS` value. Keep fixture settings and iteration counts identical when using these reports to decide whether a higher-risk work-queue scheduler is justified.

Compare two JSON reports collected with the same fixtures and configuration:

```bash
make benchmark-compare \
  BASELINE=BenchmarkResults/spacelens-benchmark-baseline.json \
  CANDIDATE=BenchmarkResults/spacelens-benchmark-candidate.json
```

The comparison prints percentage deltas for median scan time, throughput, median layout time, and peak resident memory, plus median scanner, data-set, provider, arena, and progress diagnostics when both reports contain them. It then writes a JSON comparison beside the candidate report. Older reports remain comparable, with unavailable diagnostics called out explicitly. The tool exits with status 1 when a regression exceeds a threshold and status 2 when configurations differ, so measurements with different iteration counts, scanner parallelism, directory buffers, fixtures, SDKs, hardware, or trace settings are not silently compared. The default scan, layout, and memory limits are 10%; configure them independently with `SPACELENS_BENCHMARK_SCAN_REGRESSION_THRESHOLD_PERCENT`, `SPACELENS_BENCHMARK_LAYOUT_REGRESSION_THRESHOLD_PERCENT`, and `SPACELENS_BENCHMARK_MEMORY_REGRESSION_THRESHOLD_PERCENT`.

SpaceLens also emits Instruments signposts under the `local.spacelens.app` subsystem in the `Scan`, `DirectoryRead`, `ChartLayout`, `ProviderSubtree`, and `Benchmark` categories. Capture the Logging instrument while running either the packaged app or the benchmark to correlate benchmark iterations and whole scans with sampled large or slow filesystem reads, provider timeouts, and sunburst layout work. Directory-read events include entry counts and duration; small reads under one millisecond are omitted to keep full-disk traces manageable. Signpost metadata contains fixture names, counts, and configuration, not filesystem paths.

With a full Xcode installation selected, capture a timestamped `.trace` alongside the reports:

```bash
make benchmark-trace
```

The default trace template is `Logging`, which captures the benchmark signposts. Set `SPACELENS_BENCHMARK_TRACE_TEMPLATE="Time Profiler"` for CPU stack sampling or `SPACELENS_BENCHMARK_TRACE_TEMPLATE="Allocations"` to distinguish transient from retained memory; the harness adds the Logging instrument to either profiler template so the same trace also contains SpaceLens phase signposts. The scan signpost emits final counters for successful syscall batches, fallback `lstat` calls, directory-buffer allocations, spawned directory tasks, locally retained and discarded node candidates, and progress emissions. Trace captures exclude their own active `.trace` bundle from a full-disk benchmark so the profiler cannot perturb the scan by recursively measuring its growing output. The trace harness ad-hoc signs only its temporary benchmark executable with `get-task-allow`, which Allocations requires for injection; the packaged SpaceLens app is not given that entitlement. For example, combine `SPACELENS_BENCHMARK_FIXTURES=full-disk`, `SPACELENS_BENCHMARK_ITERATIONS=1`, and `make benchmark-trace` for one startup-disk trace. Xcode or Instruments must have Full Disk Access for a complete startup-disk capture, and Allocations also requires Developer Mode plus Developer Tools permission for the terminal host. Command Line Tools alone do not include `xctrace`; trace mode exits with setup guidance before running the benchmark when it is unavailable.

## Permissions

macOS protects some folders. Before scanning the startup disk, SpaceLens checks whether it can read protected storage and, when needed, explains Full Disk Access before any analysis begins. Choose **Open Full Disk Access Settings**, enable SpaceLens, then return and scan again. Apple requires this permission to be granted manually in System Settings; apps cannot grant it themselves. Folder scans selected through the native picker can still be used without granting broad access.

macOS associates privacy choices with the app's code-signing identity. An ad-hoc signed development build is identified by its exact executable, so rebuilding it can cause macOS to ask again. For durable permission choices during local development, create a self-signed code-signing certificate in Keychain Access:

1. Choose **Keychain Access > Certificate Assistant > Create a Certificate**.
2. Name it `SpaceLens Local Development`, choose **Self Signed Root**, choose **Code Signing**, and enable **Let me override defaults**.
3. Accept the remaining defaults, then run `make app` again. The packaging script detects this identity automatically.

You can instead select an existing Apple Development or Developer ID identity explicitly:

```bash
SPACELENS_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make app
```

Run `security find-identity -v -p codesigning` to see available identities. The first stable-signed build is a new app identity, so grant Full Disk Access once more to that build. Future builds signed by the same identity and using the same `local.spacelens.app` bundle identifier retain the user's privacy choice. Developer ID signing and notarization are required before distributing the app to other Macs.

Some iCloud, Apple Books, and sandbox-container folders are serviced by macOS providers whose directory reads can stop responding. SpaceLens isolates these subtrees and, after five seconds without scan activity, skips the affected folder as unreadable so the rest of the disk scan can finish. The progress indicator and elapsed timer continue independently while the filesystem is waiting.

The storage map appears as soon as a scan starts and updates as SpaceLens measures files. For mounted disks, the progress percentage is an estimate based on mapped allocated bytes compared with the disk's reported used capacity; protected data, filesystem metadata, snapshots, and files changing during a scan mean it is not an exact item-completion percentage. First-time folder scans use an indeterminate progress bar because their total size is not known until traversal finishes. Rescans may use the previous session result as an estimate.

Before a scan starts, SpaceLens reads total and available capacity directly from macOS and can display that overview immediately. After a completed disk scan, it also stores a bounded summary of the largest folders in the user's Application Support directory. On a later launch that summary is shown as a clearly labeled **Previous scan** until a new live scan replaces it. SpaceLens does not guess folder sizes from the macOS version or processor because installations and user data vary too widely for such estimates to be reliable.

SpaceLens never deletes or modifies scanned files.

Complete disk and folder scan results remain available until SpaceLens quits. Returning home or inspecting another location does not discard them. Only the bounded disk summary described above persists between launches. A folder selected with **Scan a Folder** appears in the sidebar for the session, and its small × button removes the entry and cached result without touching the folder on disk. A checkmark beside a location indicates that a session result is available; selecting it offers to view the existing result immediately or rescan it.

For very large folders, SpaceLens retains the 96 largest direct items and combines the remainder into an accurate **Smaller items** entry. The combined entry preserves total byte and item counts while keeping memory usage bounded.
