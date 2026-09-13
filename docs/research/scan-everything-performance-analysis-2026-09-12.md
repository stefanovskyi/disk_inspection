# SpaceLens Scan Everything performance analysis — 2026-09-12

## Purpose

This note records the evidence gathered for the current SpaceLens **Scan Everything** workflow so future performance sessions can start from a stable baseline instead of repeating the investigation.

The 2026-09-12 investigation was diagnostic only. A 2026-09-13 follow-up implemented and validated the first P0 scanner fixes, which were committed as `20de801` (`Restore fast path for unobserved disk scans`). The original measurements remain the pre-fix baseline. Later 2026-09-13 work evaluated reader concurrency and bulk-buffer sizing, then implemented and measured preview/progress batching plus a counts-only Scan Everything policy.

The target being evaluated is one of:

1. Complete Scan Everything in under 60 seconds.
2. Split it into two operations, with all local-disk scanning under 60 seconds and all sequential analysis under 60 seconds.

## Executive summary

- The initial pre-fix complete workflow took **4 min 28 sec** for five successful steps.
- In that pre-fix run, the two eligible local disks ran concurrently. Their phase took approximately **145.3 seconds**, controlled by the slower startup-disk scan.
- The three analyses then ran sequentially and took approximately **123 seconds** in total.
- The present implementation does **not** reuse disk traversal facts in the analysis phase. The analysis reports account for at least **2,065,329 additional item-visits**, plus Developer Storage discovery work not represented in that count.
- A sub-minute startup-disk scan is demonstrably possible: commit `0765207` scanned approximately 5.09 million items in a three-run warm median of **53.145 seconds** on the same Mac and OS.
- A controlled synthetic comparison localized a major scanner regression to commit `fbea874`. The dominant flat-directory cost is eager per-file URL, observation, and empty-priority work even when a normal disk scan has no item observer.
- The 2026-09-13 P0 implementation removed that work from the normal no-observer path. Its comparable 12,000-file median fell from **0.2805 seconds to 0.0201 seconds**, a **92.9% reduction**.
- Before the preview/progress follow-up, packaged-app validation with Full Disk Access measured a **76.927-second warm median** for Macintosh HD and **17.620 seconds** for T7 Touch. That disk phase was **1.89x faster** than the pre-fix live run but still missed the 60-second target by 16.927 seconds.
- The complete warm median fell from **4 min 28 sec to 3 min 16 sec**, an approximate **26.8% elapsed reduction**. Sequential analysis remains the dominant cost.
- A new directory-heavy sweep measured **0.8761 seconds with one reader**, **0.2249 seconds with eight**, and **0.2227 seconds with sixteen**. Eight readers are already the useful ceiling on this Mac; sixteen add task churn for approximately 1% improvement.
- A 256 KiB directory buffer reduced a 12,000-file flat scan from 17 bulk batches to 5 and improved the median from **0.0201 to 0.0183 seconds**. This approximately 9% dense-directory gain is real but is unlikely to translate directly to a startup disk dominated by small directories.
- Preview/progress batching reduced the large directory-heavy fixture's historical live median from **0.2249 to 0.1236 seconds** and reduced shared progress merges from **9,362 to 2** per run. Counts-only reached **0.1207 seconds** and performed no preview work.
- On the startup disk, batched live preview produced a **64.183-second** three-run median and a standalone counts-only run reached **63.536 seconds**, respectively 16.6% and 17.4% below the earlier 76.927-second warm median. A busy-host counts-only series was highly variable, so its incremental whole-disk benefit remains unproven.
- A final handoff refinement returned each short-lived child worker's pending delta to its parent's local accumulator instead of forcing a shared merge. The final-source optimized benchmark then scanned **5,294,771 items in 57.170 seconds**, with 1,925 progress merges instead of 84,160 in the intermediate counts-only build. This single pass crossed 60 seconds but is not yet a repeatable release gate.
- A no-op observer still raises the same fixture to **0.1715 seconds**, so a future inspection snapshot must not naively attach the existing synchronous per-item callback to every volume scan.
- Reusing disk traversal should be based on a compact, selective `InspectionSnapshot`, not the lossy chart result and not a retained array of every `ScannedFileItem`.
- The existing asynchronous previous-scan finalizer rewrote a 19.45 MB archive for about 21 seconds while analysis was beginning, introducing unaccounted contention.

## Implementation follow-up — 2026-09-13

The P0 scanner and benchmark fixes were committed as `20de801`:

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

Verification completed on the final follow-up source:

- `make test`: 39 of 39 framework-free checks passed, including scanner safety, counts-only semantics, and parallel child-delta handoff.
- `swift test`: 95 of 95 XCTest checks passed, including 20 `DiskScannerTests` and 11 `ScanEverythingTests`.
- `make build` and `make app` completed successfully.
- `codesign --verify --deep --strict` and `plutil -lint` passed for `dist/SpaceLens.app`.
- The packaged app used ad-hoc signing because no stable local development identity was available.

### Post-commit concurrency and buffer sweep — 2026-09-13

A five-run warm-cache sweep used the existing mixed-tree generator with depth 4, fanout 8, and 16 files per directory. The fixture contained 79,577 items across 4,681 directories and deliberately emphasized many small directories containing tiny files.

| Reader limit | Warm median | Throughput | Directory tasks | Interpretation |
|---:|---:|---:|---:|---|
| 1 | 0.8761 sec | 90,828 items/sec | 0 | Serial traversal is substantially slower |
| 8 | 0.2249 sec | 353,814 items/sec | 35–55 | Current limit captures nearly all useful concurrency |
| 16 | 0.2227 sec | 357,364 items/sec | 501–638 | Approximately 1% faster with much more task churn |

The one-to-eight-reader change was approximately **3.9x faster**. The eight-to-sixteen-reader change was below 1%, so increasing the production ceiling above eight is not a useful next optimization on this hardware.

A separate nine-run flat-fixture check used the same 12,000 files with a 256 KiB buffer:

| Buffer | Warm median | Throughput | Bulk batches |
|---:|---:|---:|---:|
| 64 KiB post-P0 baseline | 0.0201 sec | 598,536 items/sec | 17 |
| 256 KiB follow-up | 0.0183 sec | 656,478 items/sec | 5 |

The larger buffer reduced elapsed time by approximately **9%** on this dense single directory. It should be treated as a candidate rather than a proven whole-disk improvement: each directory in the mixed fixture already fit in one batch, which is representative of why larger buffers cannot solve a small-directory workload alone.

The mixed fixture retained 79,576 of 79,577 items because every directory remained below the per-directory 96-child cap. That counter demonstrates that a per-directory cap is not a global result-tree bound. The benchmark's RSS samples include fixture-construction and allocator effects, so they do not isolate the exact memory cost; a separate scan-only peak-memory measurement is required before assigning a percentage.

### Preview hot-path follow-up — 2026-09-13

The preview-policy and progress-batching change is now implemented. `DiskScanner`
accepts `.live` or `.countsOnly`; interactive scans keep `.live`, while the
default Scan Everything volume factory selects `.countsOnly`. The traversal
computes each direct root child's preview branch once, passes that identity down
recursion, accumulates byte/item/branch deltas in worker-local state, and returns
a short-lived child's pending delta to its parent's local accumulator. Shared
state is merged only at a progress deadline, provider safety event, or final
snapshot. A live preview is projected only when a progress value is emitted.
Counts-only scans never maintain or construct preview state.

References:

- [Preview policy and scanner configuration](../../Sources/SpaceLens/Services/DiskScanner.swift#L71-L110)
- [Root branch and worker-delta types](../../Sources/SpaceLens/Services/DiskScanner.swift#L1002-L1042)
- [Shared merge and preview-emission boundary](../../Sources/SpaceLens/Services/DiskScanner.swift#L1145-L1257)
- [Worker accumulation and child-to-parent handoff](../../Sources/SpaceLens/Services/DiskScanner.swift#L1506-L1703)
- [Counts-only Scan Everything factory](../../Sources/SpaceLens/Services/ScanEverythingRunner.swift#L18-L25)
- [Published diagnostic fields](../../Sources/SpaceLens/Models/FileNode.swift#L272-L299)

The benchmark report schema now records progress-lock acquisitions and wait/hold
time, mapped-byte preview merges, root-branch resolutions, completed-preview
attempts/acceptance, preview constructions/emissions, and timed/forced worker
flushes. These are aggregate counters; no per-entry logging was added. Benchmark
reports use schema version 6, comparison reports use schema version 3, and the
new comparison fields are optional so older reports remain readable.

A five-run optimized A/B reused the same large mixed-tree parameters as the
reader sweep: depth 4, fanout 8, 16 files per directory, 79,577 total items, and
4,681 directories.

| Variant | Median | Throughput | Shared progress merges | Preview constructions |
|---|---:|---:|---:|---:|
| Historical live path, eight readers | 0.2249 sec | 353,814 items/sec | 9,362 | Not instrumented |
| Batched live preview | 0.1236 sec | 643,654 items/sec | 2 per run | 2 per run |
| Batched counts-only | 0.1207 sec | 659,041 items/sec | 2 per run | 0 |

The batched live-preview median is approximately **45.0% lower** than the earlier
historical live median on the same generated workload. This comparison spans
separate benchmark executions, so it establishes a strong direction rather than
a pristine one-binary A/B. Within the new same-process A/B, counts-only is about
**2.3% faster** than batched live preview. The result means that deferring shared
progress work is the primary synthetic improvement; deleting the remaining
throttled preview projection is a smaller additional saving on this sub-second
fixture.

Both policies produced the same semantic result tree, exact byte/item totals,
directory count, retained-node count, unreadable behavior, and provider-timeout
behavior. Counts-only produced zero mapped-preview merges, branch resolutions,
completed-preview attempts, preview constructions, and preview emissions. A
separate standard-suite run also passed the flat, deep, mixed, sequential and
parallel multi-volume, cancellation-latency, and stalled-provider checks.

The Full Disk Access harness then scanned the live startup volume. An adjacent
single-pass check measured `.countsOnly` at 63.536 seconds for 5,292,184 items
and `.live` at 68.619 seconds for 5,291,401 items. Counts-only was 7.4% faster in
that pair, and both policies landed inside the projected 58–69-second range.

A subsequent three-pass-per-policy series was intentionally retained even
though the host became busy:

| Policy | Median | Range | Variability | Maximum unreadable | Provider timeouts per run |
|---|---:|---:|---:|---:|---:|
| Batched live preview | 64.183 sec | 63.183–71.312 sec | 12.7% | 460 | 4 |
| Batched counts-only | 82.808 sec | 65.224–86.300 sec | 25.5% | 471 | 2–7 |

Immediately after the series, system load averages were 19.10, 24.52, and
23.23. The fixed-order series ran all live passes before all counts-only passes,
and the filesystem changed slightly between scans. It is therefore not a valid
causal result that counts-only is slower. The counts-only runs performed zero
preview merges/constructions/emissions and held the progress lock for
approximately 26–27 ms in the two comparable runs, versus approximately 48–61
ms for live preview. The standalone counts-only pass also completed in 63.536
seconds.

The three-pass batched-live median is **16.6% below** the earlier 76.927-second
packaged warm median. The standalone counts-only pass is **17.4% below** that
baseline. These cross-run comparisons support the original 10–25% hypothesis
and place the refactored scanner near the one-minute boundary, but they are not
a controlled release gate. A quiet-host, interleaved, multiple-pass packaged
series remains necessary before assigning an incremental whole-disk percentage
to counts-only.

The final implementation removed the remaining forced merge at ordinary child
task completion: a child now transfers its pending delta into its parent's local
accumulator. Only an elapsed progress deadline, provider-isolation safety event,
or the final snapshot merges shared progress. On the final source, one
additional counts-only startup scan completed in **57.170 seconds** for
5,294,771 items, 457 unreadable items, and five provider timeouts. It performed
1,925 progress merges and 2,383 progress-lock acquisitions, versus 84,160 and
84,621 respectively in the intermediate 63.536-second counts-only run—a
**97.7% reduction in shared merges**. Total progress-lock hold time was 2.825 ms,
and all preview counters remained zero. The load averages were still high at 27.23,
19.64, and 21.01, and this was one pass, so 57.170 seconds is proof of a
sub-minute observation rather than proof of a sub-minute median.

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
- Repository HEAD during the original investigation: `05d6af6` (`Gate Scan Everything on Full Disk Access`).
- The post-fix source was subsequently committed as `20de801`. The packaged app used for validation was built from the equivalent pre-commit worktree, but its exact Git revision was not embedded in the binary, so it remains a source-equivalent rather than commit-embedded benchmark.

### Eligible volumes

SpaceLens discovered exactly two eligible local volumes:

| Volume | Storage | Filesystem/context | Approximate used/mapped data |
|---|---|---|---:|
| Macintosh HD (`/`) | Internal Apple SSD | APFS startup volume | 447.59 GB mapped by SpaceLens; system reported roughly 479.48 GB used |
| T7 Touch (`/Volumes/T7 Touch`) | External Samsung SSD over 5 Gbps USB | exFAT | 473.12 GB mapped by SpaceLens |

They are on distinct physical devices. There were no eligible network mounts.

### Pre-fix run caveats

- This was one live end-to-end observation, not a statistically clean release benchmark.
- The host was busy: load averages were roughly 12–17, CPU activity was significant, and memory compression was high.
- The app passed its Full Disk Access preflight, but the startup scan still reported 449 unreadable/protected items.
- A fully readable scan may take longer.
- A requested pre-fix warm repeat could not be run because the Mac remained locked. The later post-fix validation did complete three warm repeats.
- Filesystem contents can change during a multi-minute scan; item counts are therefore workload fingerprints, not immutable constants.

## Pre-fix live Scan Everything result

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

- [Lazy per-entry work](../../Sources/SpaceLens/Services/DiskScanner.swift#L492-L528)
- [`ScannedFileItem` URL standardization](../../Sources/SpaceLens/Services/DiskScanner.swift#L919-L960)
- [Priority and observer early exits](../../Sources/SpaceLens/Services/DiskScanner.swift#L1116-L1142)
- [Modification-time parsing](../../Sources/SpaceLens/Services/BulkDirectoryReader.swift#L263-L271)
- [Conditional modification-time attribute request](../../Sources/SpaceLens/Services/BulkDirectoryReader.swift#L516-L540)

The added modification-time field also increased bulk syscall batches from 17 to 20 on the 12,000-file flat fixture, but the targeted A/B indicates that it was not the main flat-fixture regression.

The 2026-09-13 implementation now makes observation construction and priority URL evaluation lazy, with early exits when their consumers are absent. It also configures the bulk reader to request modification time only for observer-enabled scans. The comparable post-fix fixture returned to 17 bulk batches and approximately the diagnostic variant's predicted 20 ms median.

This diagnosis and fix are causal for the synthetic flat workload. The packaged Scan Everything run confirms a 1.89x warm-median startup-disk improvement on the real workload. A controlled idle-host measurement is still needed to separate the remaining scanner cost from host contention.

## Remaining Macintosh HD hot-path diagnosis

The refactored live-preview scanner produced a 64.183-second three-run median on
the busy-host series, leaving an observed 4.183-second or 6.5% gap to 60 seconds.
The adjacent counts-only pass reached 63.536 seconds, and the final child-delta
handoff implementation subsequently reached 57.170 seconds once. These are
encouraging diagnostic results rather than a new controlled baseline: the later
counts-only series had 25.5% variability and the host load averages exceeded 19. The earlier
76.927-second packaged warm median remains the stable comparison point until a
quiet-host, interleaved repeat is captured. The historical 53.145-second result
still shows that this hardware can cross the boundary.

### Ranked hypotheses

1. **Preview/progress maintenance was a material hot path and is now batched.** The large mixed fixture dropped from 9,362 shared progress merges to 2 per run, while its historical-live to batched-live median fell by 45.0%. The full-disk batched-live median was 16.6% below the earlier packaged baseline. Counts-only removes the remaining preview work, but its incremental full-disk effect needs a quiet-host interleaved repeat.
2. **Other per-directory shared-state contention remains material.** Visited identity, diagnostics, and buffer-pool state still use shared synchronization. Worker-local diagnostics and a lock-striped identity registry are the next coordination candidates; progress itself is no longer merged after nearly every directory.
3. **Per-entry cancellation and remaining path work are plausible candidates on millions of tiny files.** Normal traversal checks task cancellation for every parsed entry even though directory syscalls and progress batches already create natural bounded checkpoints. Cancellation checks can be sampled every fixed number of entries on the non-isolated path, with a regression gate for worst-case cancellation latency. Root-preview branch identity is now passed through recursion; remaining exclusion/scope path normalization still needs an audit and isolated A/B.
4. **The result tree is bounded locally but not globally.** Direct-child retention is capped at 96, yet directory-heavy trees with fewer than 96 entries per directory retain nearly every file. A global retained-node budget or earlier aggregation of tiny leaf files may reduce peak memory and cache pressure. It must preserve totals, item counts, priority paths, navigation semantics for retained nodes, and a visible `Smaller items` aggregate.
5. **Cross-volume competition may slow the startup-disk critical path.** Macintosh HD and T7 share one eight-reader traversal budget. Because T7 completes after about 18 seconds, it can consume CPU and reader slots during the beginning of the startup scan. A startup-only versus concurrent A/B must quantify this before changing scheduling; serializing both disks would otherwise increase disk-phase wall time.

### Evidence from the follow-up sweep

- One reader is conclusively too slow for the directory-heavy fixture; eight readers were 3.9x faster.
- Sixteen readers did not improve meaningful throughput over eight, so raising concurrency is not the answer.
- A 256 KiB buffer helps a large flat directory but cannot reduce the mandatory open/read/close work for thousands of small directories that already fit in one syscall batch.
- The mixed fixture's all-node retention confirms a memory-shape concern, but not yet a scan-time cause.
- Preview/progress batching is measured synthetically and on the startup disk, although the counts-only incremental whole-disk effect remains noisy. Cancellation sampling, global-node-budget, cross-volume, diagnostics-batching, and identity-registry hypotheses remain unmeasured on an isolated A/B.

### Required A/B sequence

Change one variable at a time and run both the large mixed fixture and packaged Macintosh HD protocol:

1. [x] Capture the historical scanner with live preview.
2. [x] Add counts/path progress with preview-state maintenance disabled.
3. [x] Pass the root-branch token through recursion, return child deltas to parent workers, and merge shared progress only at elapsed deadlines, provider safety events, or finalization.
4. [ ] Batch worker-local diagnostics and add a lock-striped visited-directory registry; worker-local progress batching is complete.
5. [ ] Try per-batch or sampled cancellation checks on the normal non-provider path, with a cancellation-latency regression test.
6. [ ] Compare 64 KiB versus 256 KiB bulk buffers on the packaged startup disk.
7. [ ] Compare Macintosh HD alone versus Macintosh HD concurrent with T7.
8. [ ] Compare current result retention with a global retained-node budget, measuring both scan time and peak physical footprint.

The implementation uses a configurable policy rather than deleting live preview.
`.countsOnly` remains appropriate for Scan Everything because that workflow does
not present the preview and the synthetic A/B shows a small benefit with semantic
parity. Interactive disk scans retain `.live`. The quiet-host repeat should
decide the size of the whole-disk counts-only benefit, not whether unused preview
state belongs in the Scan Everything hot path.

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

- [`retainedChildLimit`](../../Sources/SpaceLens/Services/DiskScanner.swift#L76-L82)
- [`Smaller items` aggregation](../../Sources/SpaceLens/Services/DiskScanner.swift#L704-L723)
- [`FileNode.Record` fields](../../Sources/SpaceLens/Models/FileNode.swift#L5-L17)
- [`ScannedFileItem` contains the reusable identity and modification facts](../../Sources/SpaceLens/Services/DiskScanner.swift#L919-L960)

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

### P0 — Instrument and optimize preview-state maintenance — implemented and measured 2026-09-13

Implemented aggregate counters without per-entry logging for:

- Progress-lock acquisitions plus aggregate wait and hold time.
- Preview byte merges, root-branch derivations, completed-preview attempts and acceptance, and preview construction/emission.
- Timed and forced worker-progress flushes.
- Existing progress merges/emissions, provider timeouts/abandoned workers, maximum active readers, and result-arena construction/RSS boundaries remain available alongside the new fields.

Still pending are exact bulk-syscall/batch-parse time, entry-aggregation and
directory-finalization time, traversal-permit wait time, previous-scan
finalization time, and archive I/O time.

The scanner now has an explicit preview policy. Scan Everything uses counts/path
progress without maintaining or constructing a preview tree; interactive scans
retain the live preview. Traversal propagates a root-branch token, each worker
accumulates scalar and branch deltas locally, and a completed child transfers its
pending delta into the parent's local accumulator. Shared progress is merged only
when the approximately 200 ms progress interval is due, a provider safety event
requires it, or the final snapshot is constructed. Provider heartbeat accounting
remains strict and separate from the user-visible progress cadence.

The original hypothesis was a **10–25%** startup-scan reduction, or roughly
8–19 seconds from the 76.927-second packaged baseline. The intermediate
live-preview benchmark was 16.6% lower, and the final-source counts-only pass was
25.7% lower. Those cross-run results support the estimated range, but only the
synthetic live/counts-only comparison is a controlled same-process A/B.

A same-process synthetic A/B and an optimized Full Disk Access benchmark series
are recorded in the preview follow-up above. Batching itself is the dominant
measured gain. The full-disk benchmark timings reached the estimated range, but
high host load and counts-only outliers prevent a release-quality claim about
the incremental counts-only effect.

### P1 — Batch remaining shared state and reduce repeated path work — partially completed

Completed in the preview/progress follow-up:

- Worker-local progress and preview deltas with child-to-parent handoff.
- Root-preview branch identity passed through recursion.
- Shared progress merging limited to elapsed deadlines, provider safety events, and finalization.

Still pending:

- Worker-local diagnostic deltas.
- A lock-striped visited-directory registry instead of one identity lock.
- Removal of any remaining repeated exclusion/scope path normalization.
- Sampled or per-batch cancellation checks on the normal path, while keeping provider-isolated activity checks strict and preserving prompt cancellation.

The earlier provisional **5–15%** range applied to the combined work. Progress
batching has now been measured separately; do not assign the same range to the
remaining diagnostic, identity, path, or cancellation changes without new A/Bs.

### P1 — Validate a 256 KiB directory buffer and volume allocation — next

The dense flat fixture improved by approximately 9% with a 256 KiB buffer, but the directory-heavy fixture already used one syscall batch per directory. Change the default only if the packaged startup scan improves without a memory or provider-timeout regression.

Separately measure Macintosh HD alone and alongside T7. Keep the shared eight-reader ceiling; test reader reservation or startup-volume weighting only if concurrency measurably harms the critical path. Do not serialize distinct disks merely to improve the reported Macintosh HD duration, because the user-visible disk phase is the wall time for all disks.

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

### P2 — Add a global retained-result budget

Define a total node budget in addition to the existing per-directory cap. Prefer retaining directories and materially large files, and aggregate omitted tiny leaves while preserving exact byte and item totals. Measure peak physical footprint in a scan-only harness so fixture creation and allocator high-water behavior do not contaminate the result.

This is primarily a memory-pressure and responsiveness improvement. Do not claim a disk-time percentage until a real A/B demonstrates one.

### P2 — Add FSEvents-backed incremental refresh

After a correct full scan, persist or retain a snapshot keyed by volume identity and FSEvents position, then rescan only changed subtrees. Fall back to a full scan on event drops, root changes, incompatible versions, coverage gaps, mount changes, or any `MustScanSubDirs` condition.

This does not accelerate the first scan. It has the largest potential effect on later scans: a mostly unchanged startup disk could refresh in seconds rather than revisiting 5.3 million entries. Keep a visible full-rescan action and never let incremental coverage gaps appear as zero usage.

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

Splitting the latest measured packaged workflow changes presentation, not cost:
it would expose a warm-median disk phase of approximately 76.9 seconds and a
post-disk phase of approximately 115–116 seconds. The final preview/progress
source has only optimized-harness disk timings, not a new packaged end-to-end
measurement, and no analysis-reuse change has been made.

A meaningful split should define:

- What inventory preparation belongs to the disk operation.
- Snapshot freshness and invalidation rules.
- What happens when Analysis is pressed without a compatible disk snapshot.
- Whether background persistence is included in completion.
- How partial coverage and targeted fallbacks are communicated.

## Target assessment

### Two operations under one minute each

This is credible but unproven:

- The stable pre-follow-up packaged disk-phase warm median is 76.927 seconds, down from about 145.3 seconds. The optimized Full Disk Access benchmark subsequently produced a 64.183-second live-preview median, an intermediate 63.536-second counts-only pass, and a final-source 57.170-second counts-only pass. The final source has crossed the raw 60-second target once, but the host was too busy for these runs to replace the controlled packaged baseline. Reaching the suggested 55-second gate from 57.170 seconds requires another 3.8% reduction plus repeatability.
- The inferred post-disk warm median is approximately 115–116 seconds. Reaching 60 seconds requires roughly another 1.93x speedup; avoiding broad repeated traversal remains the plausible route.
- T7 now completes in a 17.620-second warm median and comfortably meets its individual target.
- The concurrency sweep rules out simply raising the reader limit above eight. The buffer sweep is worth validating but is too small and too workload-specific to close the startup-disk gap alone.
- Preview/progress batching delivered a material disk-phase reduction. A quiet-host repeat plus the remaining diagnostics/identity shared-state work are the current route to a reliable sub-60-second disk phase; selective snapshot reuse is the route to the analysis-phase reduction.

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
- Preview merge, branch-derivation, preview-emission, and completed-preview-attempt counters.
- Time in bulk syscalls, batch parsing, entry aggregation, directory finalization, traversal-permit waits, and result construction.

### Suggested gates

For a reliable under-60-second claim, aim below the boundary rather than accepting a single 59.9-second run:

- Disk warm median no more than 55 seconds and all controlled warm repeats below 60 seconds.
- Sequential analysis warm median no more than 55 seconds and all controlled warm repeats below 60 seconds.
- No correctness regression in allocated bytes, item counts, unreadable/provider reporting, hard-link accounting, cancellation, symlink handling, or filesystem-boundary behavior.
- Explicitly document whether cold, busy-host, and coverage-gap runs are expected to meet the same target.

## Next-session checklist

1. [x] Establish and package the P0 source-equivalent build; commit the implementation as `20de801`.
2. [x] Repair the benchmark compile list and run the existing synthetic suite.
3. [x] Capture one least-warm and three warm packaged-app runs with Full Disk Access; a controlled idle-host series remains pending.
4. [x] Implement and benchmark the no-observer/empty-priority fast path.
5. [x] Compare the post-fix startup and external-volume results with the recorded live baseline.
6. [x] Sweep one, eight, and sixteen readers on a larger directory-heavy fixture; keep the production ceiling at eight.
7. [x] Measure a 256 KiB buffer on the flat fixture; retain it as a whole-disk A/B candidate.
8. [ ] Add exact scan substages plus permit, finalization, and persistence counters; preview/progress-lock counters are complete.
9. [x] Add a configurable counts-only preview policy and run synthetic plus optimized Full Disk Access preview-on/preview-off comparisons.
10. [ ] Repeat the live/counts-only comparison as an interleaved packaged-app series on a quiet host.
11. [ ] Batch worker-local diagnostics and add a lock-striped visited-directory registry; worker-local progress batching and recursive root-branch state are complete.
12. [ ] Test sampled cancellation checks with an explicit cancellation-latency gate.
13. [ ] Compare 64 KiB and 256 KiB buffers on packaged Macintosh HD.
14. [ ] Compare Macintosh HD alone with the concurrent Macintosh HD plus T7 workload.
15. [ ] Prototype and measure a global retained-node budget, including scan-only peak physical footprint.
16. [ ] Prototype the selective snapshot router behind the two-call seam.
17. [ ] Measure the router and each collector independently; connect one analyzer at a time and verify report equivalence and coverage.
18. [ ] Instrument and re-measure previous-scan finalization overlap.
19. [ ] Design FSEvents invalidation and full-rescan fallback before implementing incremental refresh.
20. [ ] Decide whether the measurements support the two-operation or one-operation target.

## Repository state at latest update

- The P0 scanner, bulk-reader, benchmark, test, and original documentation changes are committed as `20de801` (`Restore fast path for unobserved disk scans`).
- Production changes in that commit are limited to `DiskScanner`'s lazy no-observer/empty-priority paths and optional bulk modification-time metadata.
- The uncommitted follow-up adds the live/counts-only preview policy, selects counts-only for Scan Everything, propagates root-branch identity through recursion, and batches worker-local progress before shared-state merges.
- The benchmark script/report schema now supports live/counts-only mixed and full-disk A/B fixtures and exposes preview/progress coordination counters. Matching XCTest and framework-free coverage was added.
- `make build`, `make test`, `swift test`, and `make app` completed successfully for the follow-up. The packaged app passed code-signature and plist validation and is ad-hoc signed.
- Optimized Full Disk Access A/B scans completed. Batched live preview reached a 64.183-second three-run median, an intermediate counts-only pass reached 63.536 seconds, and the final child-delta handoff source reached 57.170 seconds once. A high-load counts-only series was too variable to establish a repeatable median; a quiet-host interleaved packaged-app repeat remains pending.
- The later concurrency and 256 KiB buffer reports are throwaway outputs under `/private/tmp/spacelens-next-perf`; their durable values are recorded in this note.
- The final synthetic report was written under `/private/tmp/spacelens-preview-final.OMtMYB`, the noisy three-pass full-disk A/B under `/private/tmp/spacelens-full-preview-ab.tds3gW`, and the 57.170-second final-source run under `/private/tmp/spacelens-full-final.zQinGH`. These are temporary artifacts; their durable values and caveats are recorded above.
- This latest source and documentation update is not yet committed.
- No 256 KiB production default, global result budget, `InspectionSnapshot`, analyzer reuse, incremental refresh, persistence scheduling, UI timing, or split-operation change has been implemented yet.
