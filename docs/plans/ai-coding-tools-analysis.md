# AI coding tools analysis view — implementation plan

Status: implemented; its category-first results presentation is superseded by [`ai-coding-tools-filesystem-view.md`](ai-coding-tools-filesystem-view.md)  
Prepared: 2026-09-09  
Research: `docs/research/ai-coding-tool-footprints.md`

## Goal

Add an on-demand, read-only **AI Coding Tools** view that measures local storage associated with Cursor, Claude Code, Codex, and Google Antigravity. It should answer four questions:

1. Which tools have storage on this Mac?
2. How much allocated space is associated with each tool?
3. What kind of data occupies that space?
4. Where is the data, and how complete is the measurement?

The first release will analyze metadata only. It will not parse conversations or SQLite rows, inspect credentials, delete data, run vendor cleanup commands, estimate reclaimable space, or scan the whole home directory looking for repositories.

## Product behavior

Add an **Analysis** section to the sidebar with an **AI Coding Tools** row. Selecting it opens a dedicated view and does not start filesystem work automatically.

Before the first run, the view explains that SpaceLens will inspect file metadata in known local folders for the four tools. The primary action is **Analyze Tool Storage**. This explicit action authorizes the targeted scan without treating it as a startup-disk scan or showing the startup-disk Full Disk Access gate.

During analysis, show overall item and byte progress, the tool currently being measured, elapsed time, and a cancel action. Keep the previous completed report visible during a rerun, marked as the previous result. Starting a regular disk/folder scan cancels an active tool analysis; starting tool analysis cancels an active regular scan so SpaceLens runs only one intensive filesystem job at a time.

The completed view has:

- A header with total allocated size, analysis duration, time completed, and coverage status.
- A ranked, labeled list of the four tools. Each row includes allocated size, percentage of the measured total, item count, and whether storage was found.
- A selected-tool detail area grouping storage into common categories.
- Expandable physical locations within each category, with allocated size, item count, most recent modification date when known, and status.
- An **Add Project Root…** action for repository-local storage such as Claude worktrees. Added roots remain in memory for the app session.
- **Inspect Storage Map**, **Show in Finder**, and **Open in Terminal** actions for real readable locations. Inspecting a location hands it to the existing folder scan and chart flow; the analysis report remains cached in memory for the session.
- An explicit **Other application data** category for bytes that cannot be classified safely.

Use SF Symbols for tool/category affordances and text names for product identity. The ranked text view is the authoritative representation; bars may reinforce relative size but color will not carry meaning alone. The layout must remain usable at 1100 × 620 points and in both appearances.

## Common storage model

Use one shared category enum across tools:

| Category | Meaning | Treatment in the view |
| --- | --- | --- |
| Conversations and sessions | Transcripts, tool output, session indexes and databases | User data |
| Recovery history | Checkpoints, pre-edit snapshots, backups, editor history | User data with recovery value |
| Artifacts and attachments | Plans, screenshots, recordings, generated images, uploads | User data |
| Worktrees and scratch projects | Extra checkouts and their generated contents | Working data |
| Extensions, plugins, and runtimes | Installed packages, agent workers, versioned binaries | Installed content |
| Caches and indexes | Paths documented or verified as reproducible caches | Generated data |
| Logs and diagnostics | Debug logs, traces, crash reports | Diagnostic data |
| Configuration and memory | Settings, rules, skills, memories, credential-bearing state | User configuration |
| Other application data | Mixed, unknown, or insufficiently documented storage | Unknown |

Every measured byte has one physical location and one primary category within this report. Tool ownership and storage category are separate fields so a later developer-tools feature can also tag, for example, `node_modules` inside a Cursor worktree without adding those bytes twice to the overall total.

Display **allocated size**, matching the existing scanner. Never label it “reclaimable.” Hard links, clones, shared APFS extents, and Git object sharing prevent a reliable deletion-savings estimate from simple metadata.

## Tool catalog

Create a built-in, declarative catalog for the four tools. A descriptor contains a stable tool ID, display name, candidate root templates, relative-path classification rules, a user-facing explanation for each recognized location, and source/verification metadata for maintainers. Longest matching relative path wins; unmatched descendants go to **Other application data**.

Initial roots:

| Tool | Standard roots and project-local candidates |
| --- | --- |
| Cursor | `~/.cursor`, `~/Library/Application Support/Cursor` |
| Claude Code | `CLAUDE_CONFIG_DIR` when visible to the process, `~/.claude`, `~/.local/share/claude/versions`, and `.claude/worktrees` below explicitly selected project roots |
| Codex | `CODEX_HOME` when visible to the process, `~/.codex`, `~/Library/Application Support/Codex` |
| Antigravity | `~/.gemini/antigravity`, `~/.gemini/antigravity-cli`, `~/.antigravity`, `~/Library/Application Support/Antigravity` |

Rules must distinguish product surfaces that share a brand, such as Antigravity desktop/CLI/IDE and Codex desktop/CLI/IDE, while rolling them up under one tool. Custom environment roots are additive so stale default data can still be reported. Because Finder-launched applications may not inherit shell environment variables, the view should disclose when a configurable root could not be discovered.

Use folder and file names only for the initial classification. Do not open transcript contents or query vendor databases. In particular:

- Treat Cursor `globalStorage` and `workspaceStorage` as mixed state unless a whole subdirectory has strong evidence for a narrower category.
- Treat Claude's plugin cache as installed content because it contains installed versions and dependencies.
- Group SQLite databases with their `-wal` and `-shm` sidecars; a WAL is database state, not a disposable log.
- Classify Antigravity's documented `brain/.../.system_generated/logs/transcript.jsonl` as conversation data despite the `logs` directory name.
- Detect a known root that is itself a symbolic link, report it as linked/unmeasured, and never traverse its target.

Project-local detection in the first release is limited to folders already selected in SpaceLens plus project roots the user explicitly adds from the analysis view. This covers Claude worktrees without a broad home-directory search. Additional locations remain session-only initially.

## Architecture

### Deep analyzer module

Add an `AICodingToolsAnalyzer` module with one external interface:

- Input: an analysis request containing home/Application Support locations and explicitly authorized project or custom roots.
- Output: a compact `AICodingToolsReport`.
- Callback: throttled `AICodingToolsProgress`.
- Errors: cancellation is distinct from partial coverage; missing and unreadable roots are represented in the report instead of failing the whole run.

The analyzer implementation owns root resolution, overlap removal, tool catalog matching, category aggregation, status reporting, and progress composition. SwiftUI and `AppViewModel` must not know vendor paths or classification rules. This creates locality for future tool additions: a new harness adds a catalog descriptor and focused tests instead of conditionals across views.

Suggested report types:

- `AICodingToolID`: Cursor, Claude Code, Codex, Antigravity.
- `AICodingStorageCategory`: the categories above.
- `AICodingToolsReport`: unique total, per-tool reports, started/completed dates, duration, scanned items, unreadable items, and coverage notes.
- `AICodingToolReport`: tool identity, total, category breakdowns, and detected locations.
- `AICodingStorageLocation`: standardized URL, source/surface label, category, bytes, item count, latest known modification, and status.
- `AICodingLocationStatus`: measured, missing, unreadable, stalled, linked, or not discoverable.

Only store the completed report in memory for the app session in the first release. Do not add another persistent archive until the path privacy, staleness, and migration behavior are designed.

### Scanner seam

Keep all filesystem traversal in `DiskScanner`. Add an internal per-item observation seam that the analyzer can use while a normal scan proceeds. Each observation supplies the standardized path, the bytes accounted by the scanner, file kind, readability, identity, and modification date. “Accounted bytes” must use the scanner's existing semantics: readable file allocation contributes to totals, while directory metadata and unreadable entries do not. Emit observations before `BoundedNodeAccumulator` reduces a directory to 96 retained children so category totals remain exact even when the chart tree is compacted.

Extend `LowLevelFileMetadata` with modification time from both `lstat` and `getattrlistbulk`. Requesting the bulk modification attribute keeps the common APFS path batched and avoids a new metadata syscall per entry.

The observer is an internal scanner seam, not part of the UI-facing model. Its implementation must be safe under the scanner's bounded parallel traversal. Abandoned provider workers must stop contributing observations after timeout, just as they stop contributing normal scan progress.

Scan resolved roots sequentially at the analyzer level. Each individual root still uses `DiskScanner`'s bounded subtree parallelism. This prevents multiplying the existing concurrency limit by the number of tool roots.

The analyzer does not retain the discovery scans' `FileNode` trees. They are temporary traversal results; the compact report is the retained output. A later optimization may add a totals-only scanner mode if profiling shows that constructing those transient bounded trees is material.

Normalize and deduplicate candidate roots before scanning:

1. Standardize paths without resolving symbolic links.
2. Record missing and linked roots without traversing them.
3. Collapse identical roots.
4. When one candidate root contains another, scan the ancestor once and apply the more-specific catalog rule to the descendant.
5. Keep every file in one category within a tool, with an unclassified remainder.

### Application state and navigation

Add an `AppSection` enum with `.storage` and `.aiCodingTools` rather than another presentation boolean. Existing volume/folder/chart state remains under `.storage`. `AppRootView` chooses the top-level detail from this enum before evaluating the current file node or volume overview.

Add analysis state to `AppViewModel` as a small state machine: idle, running with progress and optional previous report, completed, or failed with optional previous report. Expose intent methods such as selecting the section, starting/canceling analysis, rerunning, and inspecting a reported location. Keep task IDs so a cancelled or replaced analysis cannot publish stale progress or results.

Do not trigger analysis from volume mount notifications or application startup. Returning to SpaceLens home does not clear the completed analysis report. Starting a new analysis replaces it only after the new run completes successfully.

### Views

Add `AICodingToolsView.swift` as the dedicated screen. Keep its child views private unless a second caller appears. Use the existing `SpaceHorizontalSplitView`, `SpaceTheme`, `StorageFormatters`, and panel styling rather than introducing a new visual system.

Modify:

- `VolumeSidebar.swift` to add the Analysis section and selected state.
- `AppRootView.swift` to route the new section and present context-appropriate toolbar controls.
- `SpaceLensApp.swift` to make Command-R rerun the current operation: regular rescan in the storage section, tool reanalysis in the AI tools section.
- `AppViewModel.swift` for section, analysis state, cancellation, and the handoff to a regular location scan.
- `StorageFormatters.swift` only if a consistent relative/absolute date formatter is needed.

The analysis view should not reuse `SunburstChart` for cross-tool totals because those totals are an attribution model, not a filesystem hierarchy. **Inspect Storage Map** opens the selected physical root in the existing chart, where sunburst geometry is meaningful.

## Implementation sequence

1. **Introduce the domain model and catalog.** Add report/category/status types and path rules for all four tools. Validate normalization, longest-prefix classification, unknown remainder, and extension with a fifth fixture tool.
2. **Add scanner observations.** Extend low-level metadata with modification time and emit per-item observations before child retention. Preserve current scan behavior when no observer is supplied.
3. **Build the analyzer.** Resolve default and explicit roots, deduplicate overlaps, scan sequentially, aggregate concurrently delivered observations safely, and return partial results for inaccessible locations.
4. **Add state and navigation.** Introduce `AppSection`, the analysis state machine, stale-result guards, cancellation rules, and session-only additional project roots.
5. **Build the view.** Add the sidebar entry, empty/running/complete/partial/failure states, ranked tool list, category/location detail, accessibility labels, and Finder/Terminal/storage-map actions.
6. **Document and validate.** Update `README.md` with the feature, metadata-only privacy behavior, supported tools, and coverage limitations. Run all required builds, tests, package verification, and manual UI checks.

## Tests

Add focused XCTest coverage and matching framework-free self-tests when the active Command Line Tools environment cannot run XCTest.

Scanner tests:

- Bulk and fallback metadata paths return modification dates without following symlinks.
- The observer sees entries that are later folded into `Smaller items`.
- Cancellation and provider timeout stop late observations.
- A normal scan without an observer produces the same tree, totals, and bounded-retention behavior as before.

Catalog/analyzer tests using temporary directory fixtures:

- Each documented path maps to the expected tool and category.
- Unknown descendants remain visible in **Other application data**.
- Parent/child and duplicate candidate roots are counted once.
- More than 96 children still produce exact category totals.
- Missing, unreadable, linked, and stalled locations produce partial coverage rather than aborting the report.
- Cancellation stops the detached worker and a replaced analysis cannot publish stale results.
- Tool totals equal their category totals; the unique overall total equals the sum of disjoint physical roots.
- A synthetic fifth tool can be added through the catalog without changing aggregation or view logic.

Manual UI verification:

- Empty, running, completed, partial, cancelled, and rerun states.
- Finder, Terminal, and Inspect Storage Map actions target the displayed path.
- VoiceOver exposes tool, size, percentage, category, and coverage without relying on color.
- Keyboard navigation, reduced motion, light/dark appearance, and the 1100 × 620 minimum window.

Required commands after implementation:

```bash
make build
make test
make app
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

## Acceptance criteria

- The feature discovers and measures standard local roots for the four selected tools on macOS.
- Analysis begins only after a user action and remains fully read-only.
- No conversation, database, credential, or artifact contents are opened for classification.
- The report separates tools, common storage categories, and physical locations.
- Every measured byte appears once in the overall total and once in a tool category, including bytes under compacted scanner nodes.
- Missing or unreadable locations do not fail other tools and are explained in coverage status.
- Symlinks are never followed and provider-backed stalls cannot freeze the analysis.
- Analysis is cancellable, runs outside the main actor, and never races a replacement result into the UI.
- A physical location can be opened in Finder or Terminal and inspected with the existing storage map.
- The report survives view navigation for the app session and is not persisted to disk.
- Existing disk/folder scanning, saved scan summaries, and sunburst navigation continue to pass their tests.

## Deferred work

- Deletion, cleanup recommendations, vendor maintenance commands, and reclaimable-space estimates.
- Parsing proprietary databases or transcript content for per-conversation attribution.
- Automatic recursive discovery of every repository in the user's home directory.
- Historical growth charts or persisted analysis reports.
- Remote SSH/container/cloud-agent storage.
- Docker, Node, Python virtual environments, package-manager caches, and cross-category dependency analysis.
- Remote catalog updates. The built-in catalog is maintained and versioned with SpaceLens releases.
