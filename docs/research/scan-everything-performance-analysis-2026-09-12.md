# SpaceLens Scan Everything performance analysis — 2026-09-12

## Purpose

This note records the evidence gathered for the current SpaceLens **Scan Everything** workflow so future performance sessions can start from a stable baseline instead of repeating the investigation.

The 2026-09-12 investigation was diagnostic only. A 2026-09-13 follow-up implemented and validated the first P0 scanner fixes; the original measurements remain the pre-fix baseline.

The target being evaluated is one of:

1. Complete Scan Everything in under 60 seconds.
2. Split it into two operations, with all local-disk scanning under 60 seconds and all sequential analysis under 60 seconds.

## Executive summary

- The observed complete workflow took **4 min 28 sec** for five successful steps.
- The two eligible local disks ran concurrently. Their phase took approximately **145.3 seconds**, controlled by the slower startup-disk scan.
- The three analyses then ran sequentially and took approximately **123 seconds** in total.
- The present implementation does **not** reuse disk traversal facts in the analysis phase. The analysis reports account for at least **2,065,329 additional item-visits**, plus Developer Storage discovery work not represented in that count.
- A sub-minute startup-disk scan is demonstrably possible: commit `0765207` scanned approximately 5.09 million items in a three-run warm median of **53.145 seconds** on the same Mac and OS.
- A controlled synthetic comparison localized a major scanner regression to commit `fbea874`. The dominant flat-directory cost is eager per-file URL, observation, and empty-priority work even when a normal disk scan has no item observer.
- The 2026-09-13 P0 implementation removed that work from the normal no-observer path. Its comparable 12,000-file median fell from **0.2805 seconds to 0.0201 seconds**, a **92.9% reduction**.
- Packaged-app validation with Full Disk Access measured a **76.927-second warm median** for Macintosh HD and **17.620 seconds** for T7 Touch. The disk phase is **1.89x faster** than the pre-fix live run, but still misses the 60-second target by 16.927 seconds.
- The complete warm median fell from **4 min 28 sec to 3 min 16 sec**, an approximate **26.8% elapsed reduction**. Sequential analysis remains the dominant cost.
- A no-op observer still raises the same fixture to **0.1715 seconds**, so a future inspection snapshot must not naively attach the existing synchronous per-item callback to every volume scan.
- Reusing disk traversal should be based on a compact, selective `InspectionSnapshot`, not the lossy chart result and not a retained array of every `ScannedFileItem`.
- The existing asynchronous previous-scan finalizer rewrote a 19.45 MB archive for about 21 seconds while analysis was beginning, introducing unaccounted contention.

## Implementation follow-up — 2026-09-13

The P0 scanner and benchmark fixes are implemented in the worktree that contains this note:

- The benchmark compile list now includes the models required by `FullDiskAccessChecker`.
- Ordinary scans with no item observer no longer construct or standardize a `ScannedFileItem` URL.
- Empty priority-path scans return before constructing or standardizing an entry URL.
- Ordinary scans no longer request or parse bulk modification-time metadata; observer-enabled analysis scans still do.
- The benchmark suite has a `flat-observer` fixture so the analysis-streaming tax can be measured separately.

Five-run optimized flat-fixture measurements on the same 12,000-file workload:

| Variant | Warm median | Throughput | Bulk batches |
|---|---:|---:|---:|
| Before P0 fast path | 0.2805 sec | 42,780 items/sec | 20 |
| After P0 fast path | 0.0201 sec | 598,536 items/sec | 17 |
| After P0 with no-op observer | 0.1715 sec | 69,995 items/sec | 20 |

The comparable before/after reports show a **92.9% elapsed reduction** and **1,299.1% throughput increase** for the normal no-observer path, with the same 12,001 item count, 96 retained nodes, 11,904 discarded nodes, zero unreadable items, and zero fallback `lstat` calls. The benchmark comparison passed its configured scan, layout, and memory regression gates.

The full synthetic suite also preserved provider timeout/abandonment behavior. Its three-run medians were 0.0239 seconds for the deep fixture and 0.0156 seconds for the mixed fixture. The packaged-app measurements below confirm a material whole-disk improvement, although a controlled idle-host run is still required for a release-quality gate.

Verification completed after the implementation:

- `make test`: 38 of 38 framework-free checks passed, including scanner safety and the new optional-modification-time check.
- `swift test`: 93 of 93 XCTest checks passed, including 19 `DiskScannerTests`.
- `make build` and `make app` completed successfully.
- `codesign --verify --deep --strict` and `plutil -lint` passed for `dist/SpaceLens.app`.
- The packaged app used ad-hoc signing because no stable local development identity was available.

### Packaged Scan Everything validation — 2026-09-13

After re-authorizing the rebuilt ad-hoc app in Full Disk Access and reopening it, one least-warm and three consecutive warm Scan Everything runs completed successfully against the same two mounted volumes. Disk durations are exact values from `PreviousScans.json`. Complete durations are the app's displayed whole-second values, so each represents the half-open interval from that second to the next. The post-disk remainder is inferred from those display bounds and includes analysis plus small runner/UI overhead.

| Run | Complete | Macintosh HD | Startup items | Protected | T7 Touch | T7 items | Inferred post-disk remainder |
|---|---:|---:|---:|---:|---:|---:|---:|
| Least-warm | 3 min 4 sec | 73.514 sec | 5,295,303 | 447 | 17.548 sec | 297,916 | 110.486–111.486 sec |
| Warm 1 | 3 min 11 sec | 75.866 sec | 5,295,312 | 447 | 18.133 sec | 297,916 | 115.134–116.134 sec |
| Warm 2 | 3 min 20 sec | 76.927 sec | 5,295,115 | 447 | 17.568 sec | 297,916 | 123.073–124.073 sec |
| Warm 3 | 3 min 16 sec | 84.120 sec | 5,295,142 | 448 | 17.620 sec | 297,916 | 111.880–112.880 sec |
| **Warm median** | **3 min 16 sec** | **76.927 sec** | **5,295,142** | **447** | **17.620 sec** | **297,916** | **115.134–116.134 sec** |

Comparison with the pre-fix live Scan Everything run:

| Metric | Pre-fix live | Post-fix warm median | Improvement |
|---|---:|---:|---:|
| Parallel disk phase | about 145.3 sec | 76.927 sec | **47.1% less time; 1.89x faster** |
| Macintosh HD | 145.233 sec | 76.927 sec | **47.0% less time; 1.89x faster** |
| T7 Touch | 70.578 sec | 17.620 sec | **75.0% less time; 4.01x faster** |
| Complete workflow | 4 min 28 sec | 3 min 16 sec | **about 26.8% less time; 1.37x faster** |
| Post-disk remainder | about 123 sec | about 115–116 sec | Small change; no analysis-reuse fix yet |

The warm-median startup throughput is approximately 68,833 items/sec, up from 36,464 items/sec in the pre-fix live run. T7 throughput is approximately 16,907 items/sec.

Important caveats:

- The final host sample showed load averages of 15.02, 19.67, and 21.71, so this is a realistic busy-host result rather than a controlled idle-host result.
- The first run was least-warm after reopening the app, not a true cold-cache run; it was faster than the later warm repeats.
- Startup item counts varied by less than 0.004% across the warm runs, while T7's item count was identical.
- The 447–448 protected items show that Full Disk Access does not make every filesystem path readable; expected system restrictions still remained isolated and non-fatal.
- Per-analysis durations are not exposed in the UI, so the post-disk values cannot yet be split precisely among AI Coding Tools, AI Models, Developer Storage, and runner overhead.

## Test context

### Host

- Hardware: MacBookPro18,1, Apple M1 Pro, 10 cores, 32 GB RAM.
- OS: macOS 26.6.2, build 25G83.
- Power: AC power; Low Power Mode off.
- Spotlight indexing: disabled.
- Time Machine: idle during inspection.
- Repository HEAD during the investigation: `05d6af6` (`Gate Scan Everything on Full Disk Access`).
- The packaged app used for the live run contained the current Scan Everything feature code. Its exact Git revision was not embedded in the binary, so the live run should be treated as a current-feature build rather than a commit-exact benchmark.

### Eligible volumes

SpaceLens discovered exactly two eligible local volumes:

| Volume | Storage | Filesystem/context | Approximate used/mapped data |
|---|---|---|---:|
| Macintosh HD (`/`) | Internal Apple SSD | APFS startup volume | 447.59 GB mapped by SpaceLens; system reported roughly 479.48 GB used |
| T7 Touch (`/Volumes/T7 Touch`) | External Samsung SSD over 5 Gbps USB | exFAT | 473.12 GB mapped by SpaceLens |

They are on distinct physical devices. There were no eligible network mounts.

### Important run caveats

- This was one live end-to-end observation, not a statistically clean release benchmark.
- The host was busy: load averages were roughly 12–17, CPU activity was significant, and memory compression was high.
- The app passed its Full Disk Access preflight, but the startup scan still reported 449 unreadable/protected items.
- A fully readable scan may take longer.
- A requested warm repeat could not be run because the Mac remained locked.
- Filesystem contents can change during a multi-minute scan; item counts are therefore workload fingerprints, not immutable constants.

## Live Scan Everything result

| Operation | Observed time | Work/result | Gap to 60 seconds |
|---|---:|---|---:|
| Complete Scan Everything | 4 min 28 sec | 5 of 5 steps completed | about 208 seconds |
| All disks, parallel wall time | about 2 min 25.3 sec | 5,593,745 items | about 85.3 seconds |
| Macintosh HD | 145.233021 sec | 5,295,829 items; 449 unreadable | 85.233 seconds |
| T7 Touch | 70.577769 sec | 297,916 items; 0 unreadable | 10.578 seconds |
| All analyses, sequential | about 2 min 03 sec | at least 2,065,329 reported item-visits | about 63 seconds |
| AI Coding Tools | about 47 sec | 24.89 GB; 179,357 items; 9 installations; 0 coverage issues | meets 60 seconds individually |
| AI Models | about 4 sec | 57.28 GB; 96,042 items; 13 models | meets 60 seconds individually |
| Developer Storage | 1 min 12 sec | 61.51 GB; 1,789,930 items; 1,327 locations; 1 coverage issue | about 12 seconds |

Do not sum the three analysis byte totals: their scopes and references may overlap.

### Timing precision

Disk durations are exact `ScanResult.duration` values persisted in the app's previous-scan archive.

The complete and analysis values were displayed through `StorageFormatters.duration`:

- Values below 60 seconds are rounded to the nearest second.
- Values at or above 60 seconds are truncated to whole minutes and seconds.

Consequently:

- `47 sec` represents approximately `[46.5, 47.5)` seconds.
- `4 sec` represents approximately `[3.5, 4.5)` seconds.
- `1 min 12 sec` represents `[72, 73)` seconds.
- `4 min 28 sec` represents `[268, 269)` seconds.
- The individual analysis displays sum to a broad `[122, 125)` second bound. The complete-run and disk-phase evidence place the actual analysis phase near 123 seconds, plus or minus small runner/UI event overhead.

Reference: [`StorageFormatters.duration`](../../Sources/SpaceLens/Support/Formatters.swift#L18-L23).

## Disk concurrency result

The two volume scans visibly ran together and their persisted completion/finalization timestamps are consistent with near-simultaneous starts. Those timestamps are created by the background finalizer, not directly by the scanner, so the inferred approximately 50 ms start skew is strong supporting evidence rather than an exact scheduler measurement.

- Sum if run sequentially: `145.233021 + 70.577769 = 215.810790` seconds.
- Observed parallel wall time: approximately 145.28 seconds.
- Approximate time saved by overlap: 70.53 seconds.
- Approximate elapsed reduction: 32.68%.
- Approximate parallel speedup: 1.485x.

The external disk completed first and the startup disk determined the phase wall time.

### Current scheduling limit

The adaptive policy is:

- At most two concurrent volume scans.
- Eight directory readers shared by all active volume scans.
- At most one scan per physical device.
- At most ten progress updates per second.

Therefore, "all disks in parallel" happened on this two-disk host, but is not true for three or more independent disks. Volumes sharing a physical device are intentionally serialized.

References:

- [`ScanEverythingExecutionPolicy.adaptive`](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L27-L54)
- [Volume scheduler](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L175-L233)
- [Shared traversal budget creation](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L119-L145)

## Sequential analysis behavior

The workflow waits for the whole volume phase and then executes the selected analyses in a literal `for` loop. The order is:

1. AI Coding Tools.
2. AI Models.
3. Developer Storage.

References:

- [Phase boundary](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L129-L151)
- [Sequential analysis loop](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L295-L358)
- [Declared analysis order](../../Sources/SpaceLens/Models/ScanEverything.swift#L3-L13)

AI Coding Tools internally overlaps installation detection with its own filesystem scanning via `async let`; this does not change the top-level sequential analysis ordering.

### Repeated traversal lower bound

The analysis report item counts sum to:

```text
179,357 + 96,042 + 1,789,930 = 2,065,329 item-visits
```

That is 36.92% of the disk phase's 5,593,745 item-visits. It is a lower bound on repeated filesystem work because Developer Storage performs a separate project-discovery traversal whose items are not included in its final report count. It is not a count of unique files: analysis roots can overlap and different reports have different deduplication semantics.

### Why the analyses rescan

Each analyzer owns a separate `DiskScanner` and scans its own roots:

- [AI Coding Tools scanner and sequential roots](../../Sources/SpaceLens/Features/AICodingTools/Analysis/AICodingToolsAnalyzer.swift#L59-L180)
- [AI Models scanner and sequential roots](../../Sources/SpaceLens/Features/AIModelsAndRuntimes/Analysis/AIModelsAndRuntimesAnalyzer.swift#L10-L128)
- [Developer discovery pass and descriptor scans](../../Sources/SpaceLens/Features/DeveloperStorage/Analysis/DeveloperStorageAnalyzer.swift#L18-L184)
- [Developer automatic discovery starts at the entire home directory](../../Sources/SpaceLens/Features/DeveloperStorage/Analysis/DeveloperStorageDescriptor.swift#L27-L42)
- [Developer discovery limits: depth 18, 100,000 directories, 60 seconds](../../Sources/SpaceLens/Services/DiskScanner.swift#L47-L63)

`ScanEverythingRunner`'s `VolumeScanning` interface provides progress plus a final `ScanResult`; it does not provide the per-item observation stream or an analysis inventory. The completed in-memory scan cache is also not passed to any analyzer.

References:

- [`VolumeScanning`](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L5-L24)
- [Requests built independently of cached results](../../Sources/SpaceLens/ViewModels/AppViewModel.swift#L213-L245)
- [Completed volume results stored only for presentation/session reuse](../../Sources/SpaceLens/ViewModels/AppViewModel.swift#L292-L315)

## Disk-scanner regression evidence

### Full-disk history

| Observation | Scanner state | Duration | Items | Throughput | Coverage diagnostics |
|---|---|---:|---:|---:|---|
| `0765207`, three warm runs | Pre-analysis-streaming scanner | 53.144772 sec median | about 5.085 million | 95,687 items/sec | up to 630 unreadable |
| Current-feature raw full-disk run | Analysis-support scanner | 103.204775 sec | 5,206,254 | 50,446 items/sec | 663 unreadable; 13 provider timeouts/workers abandoned |
| Live Scan Everything startup scan | Current-feature app, competing with T7 and host load | 145.233021 sec | 5,295,829 | 36,464 items/sec | 449 unreadable |
| Post-P0 Scan Everything, three warm runs | Fast-path app, competing with T7 and busy host | 76.927260 sec median | 5,295,142 median | 68,833 items/sec | 447 median; 448 maximum unreadable |

Existing local benchmark artifacts (the directory is gitignored; durable values are copied into this note):

- [`spacelens-benchmark-0765207-full-disk-3x.json`](../../BenchmarkResults/spacelens-benchmark-0765207-full-disk-3x.json)
- [`spacelens-benchmark-scan-everything-full-disk-20260912.json`](../../BenchmarkResults/spacelens-benchmark-scan-everything-full-disk-20260912.json)
- [Existing historical/current comparison](../../BenchmarkResults/comparison-spacelens-benchmark-c30bd83-full-disk-3x-to-spacelens-benchmark-0765207-full-disk-3x.json)

The live workload contains only about 4.1% more items than the `0765207` median, while its throughput is about 62% lower. The current-feature raw workload contains about 2.4% more items and about 47% lower throughput. Dataset growth alone does not explain the change.

The 53.145-second historical result proves that a sub-minute startup-volume scan was recently achievable on this exact hardware and OS. It does not prove that the current two-volume parallel workload will be under a minute after one change.

### Controlled synthetic A/B

Five warm iterations of the same fixtures, compiler optimization, scanner parallelism, directory buffer, Mac, and OS were run minutes apart. At the time of this baseline comparison, HEAD required a temporary compile-list workaround because the checked-in benchmark script was broken; no scanner source was changed for that comparison. The 2026-09-13 follow-up repaired the checked-in script.

| Fixture | `0765207` median | Current `05d6af6` median | Slowdown | Historical throughput | Current throughput |
|---|---:|---:|---:|---:|---:|
| Flat, 12,000 files | 0.014943 sec | 0.274456 sec | 18.37x | 803,123 items/sec | 43,726 items/sec |
| Deep, 96 nested directories | 0.014325 sec | 0.024383 sec | 1.70x | 13,543 items/sec | 7,957 items/sec |
| Mixed tree | 0.006351 sec | 0.030938 sec | 4.87x | 530,128 items/sec | 108,829 items/sec |

Related local reports show the same regression shape:

- [`spacelens-benchmark-0765207-synthetic-9x.json`](../../BenchmarkResults/spacelens-benchmark-0765207-synthetic-9x.json)
- [`spacelens-benchmark-scan-everything-candidate-20260912.json`](../../BenchmarkResults/spacelens-benchmark-scan-everything-candidate-20260912.json)

### Commit localization

A three-iteration sweep across the immediate scanner-changing boundary produced:

| Fixture | `646c179` | `fbea874` | Immediate slowdown |
|---|---:|---:|---:|
| Flat | 0.016502 sec | 0.270010 sec | 16.36x |
| Deep | 0.016324 sec | 0.025772 sec | 1.58x |
| Mixed | 0.013273 sec | 0.030031 sec | 2.26x |

The large flat-directory regression enters at `fbea874` (`Add autonomous AI coding tools feature architecture`), which added per-item observation metadata and priority retention support to `DiskScanner`.

### Causal diagnostic variants

The following variants were made only in throwaway `/private/tmp` copies of `fbea874`. They deliberately removed functionality to isolate costs and are not production fixes.

| Flat-fixture variant | Median | Change from 270.010 ms baseline | Interpretation |
|---|---:|---:|---|
| Unmodified `fbea874` | 270.010 ms | baseline | Regression present |
| Do not request bulk modification time | 261.612 ms | -3.1% | Wider metadata records are secondary on this fixture |
| Skip priority classification | 158.492 ms | -41.3% | Empty-priority URL normalization is material |
| Skip observation and priority work, retain eager URL | 37.366 ms | -86.2% | Most cost is per-item analysis-support work |
| Also make the entry URL lazy | 20.194 ms | -92.5% | Returns close to the pre-feature 16.502 ms result |

An observation-only-off run was highly variable and should not be used for a precise percentage. The combined variants and commit boundary are the stronger evidence.

### Hot-path explanation at the pre-fix baseline

At `05d6af6`, every readable non-directory entry in a normal disk scan:

1. Materializes an `entryURL`.
2. Constructs `ScannedFileItem`.
3. Standardizes the URL inside `ScannedFileItem.init`.
4. Calls `recordObservation`; only then does it discover that the normal volume scan has no item handler.
5. Calls `shouldPrioritize`, which standardizes the URL again before iterating a priority set that is empty for normal volume scans.

The historical implementation can be inspected with `git show 05d6af6:Sources/SpaceLens/Services/DiskScanner.swift` and the equivalent `BulkDirectoryReader.swift` path. The current source links below show the corrected implementation:

- [Lazy per-entry work](../../Sources/SpaceLens/Services/DiskScanner.swift#L478-L509)
- [`ScannedFileItem` URL standardization](../../Sources/SpaceLens/Services/DiskScanner.swift#L827-L872)
- [Priority and observer early exits](../../Sources/SpaceLens/Services/DiskScanner.swift#L972-L998)
- [Modification-time parsing](../../Sources/SpaceLens/Services/BulkDirectoryReader.swift#L263-L271)
- [Conditional modification-time attribute request](../../Sources/SpaceLens/Services/BulkDirectoryReader.swift#L516-L540)

The added modification-time field also increased bulk syscall batches from 17 to 20 on the 12,000-file flat fixture, but the targeted A/B indicates that it was not the main flat-fixture regression.

The 2026-09-13 implementation now makes observation construction and priority URL evaluation lazy, with early exits when their consumers are absent. It also configures the bulk reader to request modification time only for observer-enabled scans. The comparable post-fix fixture returned to 17 bulk batches and approximately the diagnostic variant's predicted 20 ms median.

This diagnosis and fix are causal for the synthetic flat workload. The packaged Scan Everything run confirms a 1.89x warm-median startup-disk improvement on the real workload. A controlled idle-host measurement is still needed to separate the remaining scanner cost from host contention.

## Previous-scan finalization contention

When a volume finishes, `AppViewModel` installs the in-memory result and starts an unawaited `ScanResultFinalizer` task. The runner does not wait for this work before beginning analysis.

The finalizer:

1. Recursively constructs a persisted summary up to six retained levels.
2. Loads and decodes the existing archive.
3. Replaces one entry.
4. Encodes all retained summaries.
5. Atomically rewrites the archive.

References:

- [Background finalizer launch](../../Sources/SpaceLens/ViewModels/AppViewModel.swift#L594-L620)
- [`ScanResultFinalizer`](../../Sources/SpaceLens/Services/ScanResultFinalizer.swift#L3-L16)
- [Whole-archive load/encode/write](../../Sources/SpaceLens/Services/PreviousScanStore.swift#L19-L57)
- [Persisted tree construction](../../Sources/SpaceLens/Models/PreviousScanSummary.swift#L3-L100)

Observed evidence:

- The archive size after the run was 19,445,170 bytes.
- The startup summary's `scannedAt` is created near the beginning of finalization.
- The archive's atomic replacement timestamp was approximately 21.094 seconds later.
- AI Coding analysis began immediately after the disk phase, so the startup-volume finalization likely overlapped a substantial part of its approximately 47 seconds.

The timestamp evidence approximates finalization-plus-store elapsed time; it is not a CPU profile and does not prove that all 21 seconds were active CPU usage. This work needs its own signpost/timer before its effect is attributed precisely.

## Memory evidence

Observed process samples during the live workflow:

- Idle resident memory before scanning: roughly 81 MiB.
- Disk phase samples: roughly 269–526 MiB RSS.
- Analysis samples: up to roughly 1.11 GiB RSS.
- `/usr/bin/sample` later reported a current physical footprint of 803.2 MiB and a process physical-footprint peak of approximately 1.6 GiB.

`ScannedFileItem` has a 72-byte stride on this architecture. Retaining one value for each of the 5,593,745 disk-scan item-visits would require:

```text
5,593,745 × 72 = 402,749,640 bytes = 384.1 MiB
```

That excludes URL/path heap allocations, array capacity, indices, dictionaries, and analyzer-specific state. A full `[ScannedFileItem]` cache would therefore materially worsen an already high peak.

## Why the existing `ScanResult` is not a reusable analysis cache

The chart-oriented result is intentionally lossy:

- Each directory retains at most 96 direct children.
- Omitted children are collapsed into a synthetic `Smaller items` node.
- Totals and item counts survive, but individual omitted paths do not.
- `FileNode` records do not contain device/inode identity or modification time.

That is sufficient for presentation but not for exact model discovery, category classification, newest-file dates, coverage, or hard-link-aware Developer Storage accounting.

References:

- [`retainedChildLimit`](../../Sources/SpaceLens/Services/DiskScanner.swift#L71-L76)
- [`Smaller items` aggregation](../../Sources/SpaceLens/Services/DiskScanner.swift#L633-L650)
- [`FileNode.Record` fields](../../Sources/SpaceLens/Models/FileNode.swift#L5-L17)
- [`ScannedFileItem` contains the reusable identity and modification facts](../../Sources/SpaceLens/Services/DiskScanner.swift#L827-L872)

## Recommended reuse architecture

### Deep module seam

Prefer one inventory module with two user-facing operations rather than exposing three analyzer-specific caches:

```swift
scanAllLocalVolumes(plan, analysisPlan, onEvent) async throws -> InspectionSnapshot
runAllAnalyses(from: snapshot, requests, onEvent) async throws -> AnalysisSummary
```

`InspectionSnapshot` should be immutable. Its public surface should expose provenance and coverage while keeping the internal fact store opaque.

### Prepare analysis routing honestly

Freeze the analysis requests and descriptors before disk traversal so the inventory router knows which facts matter. Descriptor/config discovery has a cost—for example, some tool settings are read while roots are assembled. If this happens before disk scanning, report it explicitly as **inventory preparation**; do not make the analysis number appear faster merely by moving work across a timing boundary.

### Store selective facts, not every file

Common snapshot metadata:

- Request/descriptor fingerprint.
- Volume identity, filesystem identity, root, and observation interval.
- Covered and uncovered prefixes.
- Unreadable paths and provider-timeout/truncation markers.
- Scanner version/schema needed for invalidation.

AI Coding Tools facts:

- Per descriptor/category bytes and item counts.
- Latest relevant modification time.
- Priority roots and installation evidence candidates.

AI Models facts:

- Per root/runtime/category aggregates.
- Only candidate model files and relevant Ollama manifests/configuration references.
- Only the paths needed for bounded GGUF/SafeTensors/header parsing.

Developer Storage facts:

- Candidate project/artifact directories and marker names discovered during the disk walk.
- Per provisional location/category aggregates.
- Device/inode identity needed for unique-byte accounting.
- Enough information to reproduce deterministic ownership of hard-linked files.

### Preserve deterministic hard-link semantics

Developer Storage currently scans descriptors in deterministic priority order: shared locations first, followed by ecosystem and path. A global identity registry assigns unique bytes according to that order.

Parallel disk callbacks cannot use "first callback wins" because callback order is nondeterministic. Use one of:

1. An identity-to-canonical-owner map that can reassign bytes when a higher-priority descriptor becomes known.
2. Compact per-provisional-location identity/size/category records, finalized later in the existing descriptor order.

References:

- [Developer descriptor order](../../Sources/SpaceLens/Features/DeveloperStorage/Analysis/DeveloperStorageAnalyzer.swift#L218-L234)
- [Global identity classification](../../Sources/SpaceLens/Features/DeveloperStorage/Analysis/DeveloperStorageAnalyzer.swift#L321-L399)

### Avoid synchronous callback serialization

`DiskScanner` calls `onItem` synchronously in worker context. The existing analyzers lock on each item and perform URL/category work while holding or around those locks:

- [AI Coding accumulator](../../Sources/SpaceLens/Features/AICodingTools/Analysis/AICodingToolsAnalyzer.swift#L422-L443)
- [AI Models accumulator](../../Sources/SpaceLens/Features/AIModelsAndRuntimes/Analysis/AIModelsAndRuntimesAnalyzer.swift#L513-L548)
- [Developer accumulators](../../Sources/SpaceLens/Features/DeveloperStorage/Analysis/DeveloperStorageAnalyzer.swift#L321-L369)

Do not attach all three current accumulators directly to the volume scan. Prefer per-worker/per-directory or per-volume batches, lock-striped shards, and a merge after each volume. Where possible, determine applicable analysis routes once per directory and avoid constructing standardized URLs for irrelevant files.

### Validate staleness and coverage

The multi-volume scan is not an atomic filesystem snapshot. Before report assembly:

- Confirm the snapshot fingerprint matches current requests/descriptors.
- Re-stat retained content candidates before bounded reads.
- Treat unreadable/provider-timeout subtrees as explicit coverage gaps.
- Run targeted fallback scans for uncovered custom/network roots or stale subtrees.
- Report partial coverage rather than silently treating gaps as zero bytes.

Keep small content reads in the sequential analysis phase. Examples include installation plists/JSON, model manifests/configuration, GGUF/SafeTensors headers, and environment-list files. The large directory traversals are the primary reuse target.

## Prioritized recommendations and status

### P0 — Restore the normal disk-scan fast path — completed 2026-09-13

Implemented production forms of the diagnostic conditions:

- If there is no item observer, do not construct `ScannedFileItem` or standardize its URL.
- If no priority paths exist, return before creating/standardizing a URL for priority matching.
- Make readable-entry URLs lazy unless progress, unreadable handling, priority retention, or an observer actually needs them.
- Request/parse modification time only for scans or directories whose consumers require it.

The no-handler and no-op-handler variants are now independently benchmarkable. Analyzer and scanner suites cover real handlers, cancellation, protected/provider handling, symlink safety, filesystem boundaries, totals, hard-link accounting, and retained-node ordering. Packaged Scan Everything validation is complete; a controlled idle-host repeat remains pending.

### P0 — Repair and enforce the benchmark harness — completed 2026-09-13

At the pre-fix baseline, `Scripts/run_benchmarks.sh` failed to compile:

```text
FullDiskAccessChecker.swift:27:27: error: cannot find type 'ScanEverythingPlan' in scope
```

The script compiled `FullDiskAccessChecker.swift` but omitted its new `ScanEverythingPlan`/`VolumeInfo` dependencies from the source list.

Reference: [benchmark compile list](../../Scripts/run_benchmarks.sh#L64-L78).

The checked-in script now includes both model dependencies and runs successfully. The existing comparison command enforced its scan, layout, and memory regression thresholds against comparable pre-fix and post-fix reports. A `flat-observer` fixture was added for measuring callback overhead separately; it is opt-in rather than part of the default suite.

### P1 — Build a selective `InspectionSnapshot` during disk traversal

Implement the low-overhead router and snapshot described above. Benchmark its tax on the disk phase before connecting analyzers. The disk target has no room for an unmeasured lock or URL-allocation cost.

The new `flat-observer` result makes this constraint concrete: a no-op use of the existing item observer is about **8.5x slower** than the restored no-observer path. The snapshot seam should therefore accept low-level directory batches or lazy path components, route once per directory, accumulate into worker-local or sharded state, and merge outside the entry loop.

Suggested A/B sequence:

1. Disk scanner with no handler.
2. Disk scanner with a no-op handler.
3. Disk scanner with the selective router but no retained facts.
4. Router plus each collector independently.
5. Full snapshot with all collectors.

### P1 — Make analyses consume the snapshot sequentially

Keep the requested top-level ordering. Replace broad traversal with snapshot aggregation/report assembly, retaining bounded content reads and targeted coverage fallbacks.

The approximate 123-second analysis phase must save about 63 seconds, or 51%, to meet the separate one-minute target. AI Models already takes only about four seconds; most savings must come from AI Coding and Developer Storage traversal/discovery.

### P1 — Isolate and measure previous-scan persistence

Give summary construction, archive decoding, archive encoding, and atomic writing their own metrics. Then evaluate batching completed volume summaries or deferring persistence until analysis completes. Do not hide persistence time if it remains part of user-visible completion semantics.

### P2 — Expose the timings already captured

`ScanEverythingStepOutcome` already stores an exact duration for every disk and analysis, and `ScanEverythingSummary` stores the exact total. The UI currently renders only `completed/total` and aggregate duration.

References:

- [Exact outcome fields](../../Sources/SpaceLens/Models/ScanEverything.swift#L121-L130)
- [Per-step duration construction](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L240-L292)
- [Analysis duration construction](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L303-L355)
- [Current aggregate-only UI](../../Sources/SpaceLens/Views/VolumeSidebar.swift#L514-L558)
- [Completion signpost includes exact duration](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L425-L443)

Persist or export a machine-readable run summary so later sessions do not need UI transcription.

### P2 — Split buttons only after phase contracts are explicit

Splitting the current implementation changes presentation, not cost: it would expose approximately 2:25 for disks and 2:03 for analyses.

A meaningful split should define:

- What inventory preparation belongs to the disk operation.
- Snapshot freshness and invalidation rules.
- What happens when Analysis is pressed without a compatible disk snapshot.
- Whether background persistence is included in completion.
- How partial coverage and targeted fallbacks are communicated.

## Target assessment

### Two operations under one minute each

This is credible but unproven:

- The packaged disk-phase warm median is now 76.927 seconds, down from about 145.3 seconds. Reaching 60 seconds requires another 1.28x speedup or 22% reduction; reaching the suggested 55-second gate requires about 1.40x.
- The inferred post-disk warm median is approximately 115–116 seconds. Reaching 60 seconds requires roughly another 1.93x speedup; avoiding broad repeated traversal remains the plausible route.
- T7 now completes in a 17.620-second warm median and comfortably meets its individual target.

### One complete operation under one minute

This is substantially harder:

- The post-fix warm median is approximately 196.5 seconds, down from the pre-fix 268.5 seconds. Reaching 60 seconds still requires about a 3.28x end-to-end speedup or roughly a 69% reduction.
- Even the historical 53-second startup scan leaves only about seven seconds for all post-scan analysis if phases remain sequential.
- It may become possible only if most analysis classification is folded into the disk traversal at very low cost and final report assembly/content validation is extremely small.

Do not commit to this target until the low-overhead snapshot prototype has an end-to-end measurement.

## Required measurement protocol for the next session

### Runs

For the packaged app with Full Disk Access:

1. One cold or least-warm run after launch.
2. At least three warm repeats; five is preferable.
3. Record both a controlled idle-host result and a realistic busy-host result.
4. Keep the same two mounted volumes and record their filesystem/used-space state.

### Record for every run

- App build identifier and Git revision.
- OS, hardware, power mode, load average, memory pressure, and major background I/O.
- Eligible volumes, physical device keys, filesystem types, used space, and item counts.
- Inventory-preparation duration.
- Each volume duration and throughput.
- Disk-phase wall time and overlap.
- Each analysis duration, subdivided into discovery, traversal/fallback, content reads, and report assembly.
- Analysis-phase wall time.
- Previous-scan finalization and archive-write time.
- Complete user-visible time.
- Unreadable items, provider timeouts, abandoned workers, and coverage issues.
- CPU samples, resident memory, and physical-footprint peak.
- Snapshot size and router/collector counters if reuse is enabled.

### Suggested gates

For a reliable under-60-second claim, aim below the boundary rather than accepting a single 59.9-second run:

- Disk warm median no more than 55 seconds and all controlled warm repeats below 60 seconds.
- Sequential analysis warm median no more than 55 seconds and all controlled warm repeats below 60 seconds.
- No correctness regression in allocated bytes, item counts, unreadable/provider reporting, hard-link accounting, cancellation, symlink handling, or filesystem-boundary behavior.
- Explicitly document whether cold, busy-host, and coverage-gap runs are expected to meet the same target.

## Next-session checklist

1. [x] Confirm the worktree base revision (`05d6af6`) and package the current changed worktree.
2. [x] Repair the benchmark compile list and run the existing synthetic suite.
3. [ ] Add or expose exact phase/substage timing without changing scheduling.
4. [x] Capture one least-warm and three warm packaged-app runs with Full Disk Access; a controlled idle-host series remains pending.
5. [x] Implement and benchmark the no-observer/empty-priority fast path.
6. [x] Compare the post-fix startup and external-volume results with the recorded live baseline; both improved materially, and synthetic safety/performance checks are complete.
7. [ ] Prototype the selective snapshot router behind the two-call seam.
8. [ ] Measure the router and each collector independently; no-handler and no-op-handler measurements are complete.
9. [ ] Connect one analyzer at a time, verifying report equivalence and coverage.
10. [ ] Instrument and re-measure finalization overlap and peak memory.
11. [ ] Decide whether the measurements support the two-operation or one-operation target.

## Repository state at handoff

- The worktree is based on `05d6af6` and contains uncommitted P0 scanner, bulk-reader, benchmark, test, and documentation changes.
- Production changes are limited to `DiskScanner`'s lazy no-observer/empty-priority paths and optional bulk modification-time metadata.
- The benchmark script and fixtures were updated, and matching XCTest plus framework-free coverage was added.
- `make build`, `make test`, `swift test`, and `make app` completed successfully. The packaged app passed code-signature and plist validation and is ad-hoc signed.
- Comparable benchmark reports and throwaway outputs remain under `/private/tmp`; their durable results are recorded in this note.
- No `InspectionSnapshot`, analyzer reuse, persistence scheduling, UI timing, or split-operation changes have been implemented yet.
