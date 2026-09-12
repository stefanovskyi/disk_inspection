# SpaceLens development

## Requirements

- macOS 14 or newer
- Swift 6 from Xcode or the Xcode Command Line Tools

Run commands from the repository root.

## Build and test

```bash
make build
make test
make app
```

`make test` is the minimum verification after changes to scanning, models, or chart layout. It uses a framework-free test harness that works with Command Line Tools; XCTest targets are also available in Xcode.

`make app` creates `dist/SpaceLens.app`. Run it with:

```bash
open dist/SpaceLens.app
```

You can also open `Package.swift` in Xcode and run the `SpaceLens` executable target.

Some Command Line Tools installations select an incompatible SDK by default. Choose a compatible SDK explicitly when needed:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk swift build
SPACELENS_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk make test
```

Do not hard-code this compatibility override in application source.

## Stable permissions for local builds

macOS associates privacy choices with an app's signing identity. The packaging script uses a `SpaceLens Local Development` identity when available and otherwise falls back to ad-hoc signing. Ad-hoc builds may need Full Disk Access granted again after each rebuild.

To create the expected local identity in Keychain Access:

1. Choose **Keychain Access > Certificate Assistant > Create a Certificate**.
2. Name it `SpaceLens Local Development`, select **Self Signed Root** and **Code Signing**, then enable **Let me override defaults**.
3. Accept the remaining defaults and run `make app` again.

Alternatively, select an existing identity:

```bash
SPACELENS_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make app
```

List available identities with `security find-identity -v -p codesigning`. A stable-signed build has a new app identity the first time, so grant it Full Disk Access once. Developer ID signing, hardened runtime, and notarization are required for distribution to other Macs.

Validate a packaged app with:

```bash
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

## Performance benchmarks

Run the optimized synthetic scanner and chart-layout fixtures:

```bash
make benchmark
```

Reports are written as timestamped JSON and CSV files in `BenchmarkResults/`. They record the Git state, toolchain, hardware, fixture configuration, timings, memory use, and scanner diagnostics. The default fixtures include sequential and bounded-parallel synthetic multi-volume runs; those entries also record global directory-reader concurrency and cancel-all latency.

Run three read-only startup-disk scans with:

```bash
make benchmark-full
```

The external-disk fixture is opt-in. Point it at a dedicated directory rather than a volume root:

```bash
SPACELENS_BENCHMARK_FIXTURES=external \
SPACELENS_BENCHMARK_EXTERNAL_PATH="/Volumes/TestDisk/SpaceLensFixture" \
make benchmark
```

Run the standard multi-volume policy matrix (sequential 1/8, conservative 2/8,
higher-reader 2/12, and higher-operation 3/8):

```bash
make benchmark-parallelism
```

Override the matrix with comma-separated `name:active-scans:directory-readers` entries in
`SPACELENS_BENCHMARK_VOLUME_POLICY_MATRIX`. Set
`SPACELENS_BENCHMARK_INCLUDE_UNRESTRICTED=1` to append the diagnostic-only unrestricted policy.
Keep fixtures and iteration counts identical when comparing scheduler changes.

Compare compatible reports with:

```bash
make benchmark-compare \
  BASELINE=BenchmarkResults/spacelens-benchmark-baseline.json \
  CANDIDATE=BenchmarkResults/spacelens-benchmark-candidate.json
```

The comparison reports percentage changes in scan time, throughput, layout time, and peak memory. It exits with status 1 when a regression exceeds its threshold and status 2 when configurations differ. The default scan, layout, and memory thresholds are 10%; set them independently with:

- `SPACELENS_BENCHMARK_SCAN_REGRESSION_THRESHOLD_PERCENT`
- `SPACELENS_BENCHMARK_LAYOUT_REGRESSION_THRESHOLD_PERCENT`
- `SPACELENS_BENCHMARK_MEMORY_REGRESSION_THRESHOLD_PERCENT`

Common benchmark controls include:

- `SPACELENS_BENCHMARK_ITERATIONS`
- `SPACELENS_BENCHMARK_PARALLELISM`
- `SPACELENS_BENCHMARK_VOLUME_SCAN_LIMIT`
- `SPACELENS_BENCHMARK_VOLUME_POLICY_MATRIX`
- `SPACELENS_BENCHMARK_DIRECTORY_BUFFER_KB`
- `SPACELENS_BENCHMARK_OUTPUT_DIR`
- `SPACELENS_BENCHMARK_FIXTURES`
- `SPACELENS_BENCHMARK_FLAT_FILES`
- `SPACELENS_BENCHMARK_DEEP_DIRECTORIES`
- `SPACELENS_BENCHMARK_MIXED_DEPTH`
- `SPACELENS_BENCHMARK_MIXED_FANOUT`
- `SPACELENS_BENCHMARK_MIXED_FILES_PER_DIRECTORY`
- `SPACELENS_BENCHMARK_PROVIDER_TIMEOUT_MS`

## Instruments traces

SpaceLens emits signposts under the `local.spacelens.app` subsystem in the `Scan`, `DirectoryRead`, `ChartLayout`, `ProviderSubtree`, and `Benchmark` categories. Signpost metadata includes fixture names, counts, and configuration—not filesystem paths.

With a full Xcode installation, capture a timestamped trace alongside benchmark reports:

```bash
make benchmark-trace
```

The default template is `Logging`. For CPU or memory profiling, set `SPACELENS_BENCHMARK_TRACE_TEMPLATE` to `Time Profiler` or `Allocations`. The harness includes SpaceLens signposts in either profile.

For one startup-disk trace:

```bash
SPACELENS_BENCHMARK_FIXTURES=full-disk \
SPACELENS_BENCHMARK_ITERATIONS=1 \
make benchmark-trace
```

Xcode or Instruments needs Full Disk Access for a complete startup-disk capture. Allocations also requires Developer Mode and Developer Tools permission for the terminal host. Command Line Tools alone do not include `xctrace`.

## Project guidance

Repository structure, architecture constraints, filesystem safety rules, and required verification are documented in [AGENTS.md](AGENTS.md).
