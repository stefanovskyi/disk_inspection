# AI coding tools filesystem view — implementation plan

Status: implemented  
Prepared: 2026-09-10  
Builds on: [`ai-coding-tools-analysis.md`](ai-coding-tools-analysis.md)

## Objective

Change the selected-tool results from a category-first report into a filesystem-first view:

```text
Tool
└── unique physical location
    └── folder or file
        └── child folder or file
```

When Cursor is selected, for example, `~/Library/Application Support/Cursor` must appear once. Its total size and description belong to that one location row. Expanding it reveals its immediate children, and expanding a child reveals the next filesystem level. Categories such as caches, logs, recovery, and extensions explain nodes and summarize composition; they must never cause the same location to be rendered again.

The same model applies to Claude Code, Codex, and Antigravity.

## Why the current model must change

The current report stores each physical location as a set of category contributions. The view starts with categories and then lists every contributing location below each category. A location containing caches, logs, extensions, and recovery data therefore appears four times even though it is one directory on disk.

This is accurate as an accounting breakdown but gives the wrong answer to the main navigation question: “Where is this tool using space?” It also obscures the actual parent-child relationship between components.

The pivot reverses ownership:

- A standardized filesystem path is the primary identity.
- Each physical location owns one compact filesystem tree.
- Categories, component names, and explanations annotate nodes in that tree.
- Category totals remain available as a compact composition summary, without rendering paths beneath them.

## Result experience

Keep the existing tool selector and analysis lifecycle. Replace the selected-tool detail area with a **Locations** outline.

For each selected tool:

1. Show every known physical root exactly once, ordered by allocated size.
2. Show the root's display name, standardized path, allocated size, item count, status, and short description.
3. Let the root disclose its immediate retained children.
4. Show each child with its file or folder icon, name, allocated size, percentage of the root, item count when it is a directory, and a short semantic description when known.
5. Let directory rows disclose their retained children recursively.
6. Keep synthetic **Smaller items** nodes visible and clearly explain that they combine smaller direct entries. They are not expandable and must not be presented as a real path.
7. Keep missing, unreadable, stalled, linked, and undiscoverable roots as single status rows with no fabricated children.

Roots and deeper folders start collapsed so the complete location list is visible when a tool is selected. Expansion is local presentation state and must not trigger another scan. Rows remain ordered by allocated size because finding the largest consumers is the primary task.

### Row descriptions

Descriptions should explain the filesystem component represented by the row rather than create a second navigation hierarchy. Examples include:

- `extensions` — “Installed editor extensions and their bundled files.”
- `worktrees` — “Isolated Git checkouts created for agent tasks.”
- `User/History` — “Editor recovery history for previously edited files.”
- `sessions` — “Saved coding-agent sessions and their metadata.”
- `logs` — “Diagnostic logs produced while the tool runs.”

Use the longest matching relative-path rule. The node matching the rule receives its specific component title and description. Descendants inherit the category but do not repeat the full component explanation on every row. Unrecognized nodes receive a neutral explanation such as “Other Cursor application data”; the product must not guess from file contents.

### Composition summary

Category totals may remain near the selected-tool header as compact labeled bars or chips. They answer “what kind of data is this?” and do not expand into location lists. Selecting a category may later filter or highlight the filesystem outline, but filtering is outside this implementation.

## Data model

Replace category-owned location contributions with physical-location-owned scan results.

### Physical location report

Each analyzed root should contain:

- A stable ID derived from its standardized path.
- The associated tool ID and any merged catalog aliases.
- Display name, root description, URL, and location status.
- The compact `FileNode` root returned by `DiskScanner` when measurement succeeds.
- Exact allocated byte and item totals.
- The existing category composition totals and latest known modification date.
- A compact set of relative-path annotations used to describe retained nodes.

Retain `FileNode` rather than copying the result into a second recursive tree. Its arena-backed storage already enforces the scanner's per-directory child limit, preserves exact aggregate totals through **Smaller items**, and gives every real node a stable standardized-path ID.

### Tool report

`AICodingToolReport` should expose a size-ranked collection of unique physical locations. Its category totals become a computed summary across those locations. The UI must consume `tool.locations` directly and must not rebuild locations by iterating categories.

### Node annotation

Extend each catalog path rule with presentation metadata:

- Component title.
- Concise user-facing description.
- Storage category.
- Relative path prefix used for longest-prefix matching.

Resolve annotations in the model or analyzer so the SwiftUI view does not contain vendor-specific path rules. Resolution uses filenames and relative paths only; it does not open transcripts, databases, credentials, or configuration contents.

## Physical identity and deduplication

Normalize candidate URLs before scanning and use the standardized path as the physical identity.

Apply these invariants:

1. Exact duplicate candidates for one tool merge into one location.
2. An ancestor and descendant candidate for one tool collapse into the ancestor location; the descendant becomes an annotated node inside the ancestor tree.
3. A physical root is scanned at most once in an analysis run.
4. Tool and overall byte totals count a physical item at most once.
5. Multiple catalog descriptors may contribute names, rules, or tool associations to the same physical root without creating another rendered row.
6. A shared root may be referenced from each relevant tool's separately selected view, while the report's overall total still counts it once.

Known nested catalog roots should be retained in the compact scan result even when a directory has more than `DiskScanner.retainedChildLimit` children. Add a small set of priority relative paths to the scanner's bounded child selection rather than increasing or bypassing the limit. Priority children consume slots; remaining slots continue to hold the largest entries, and all omitted entries remain represented by **Smaller items**.

## Analyzer changes

Reshape `AICodingToolsAnalyzer` around unique scan roots:

1. Resolve built-in roots, environment roots, and selected project roots.
2. Standardize paths and merge exact duplicates.
3. Collapse nested candidates into the nearest surviving ancestor while retaining their catalog metadata as node annotations.
4. Preflight each unique root for missing, unreadable, linked, or unsupported states.
5. Scan each readable root once through `DiskScanner`, preserving cancellation, bounded traversal, filesystem boundaries, permission reporting, and provider timeouts.
6. Retain the returned compact `FileNode` root on the physical-location report.
7. Continue collecting category totals and latest modification metadata from the scanner observation callback; these totals feed summaries only.
8. Associate the completed physical location with every applicable tool without adding its bytes again to the analysis-wide total.

Do not add a second recursive filesystem walk. Do not retain an observation record for every discovered path. The compact scanner tree is the source of truth for disclosure navigation.

## View changes

Rebuild the completed selected-tool detail in `AICodingToolsView.swift`:

- Remove category sections that enumerate locations.
- Add a location outline driven directly by the selected tool's unique locations.
- Use `DisclosureGroup`-style rows with an explicit set of expanded node IDs so children are constructed only when visible.
- Show folders and files in allocated-size order, using SF Symbols and textual type/status labels.
- Put Finder, Terminal, and storage-map actions in a compact row menu or context menu so recursive rows stay readable.
- Keep a root-level category composition summary without links that reproduce location rows.
- Preserve keyboard navigation, VoiceOver labels, light/dark appearance, reduced motion, and the 1100 × 620 minimum layout.

**Inspect Storage Map** should work for any readable directory node, not only catalog roots. It hands that directory to the existing folder scan flow and leaves the AI coding tools report cached for the session. File nodes offer Finder actions but cannot open a directory storage map.

## Implementation sequence

### 1. Reshape report ownership

Update `Sources/SpaceLens/Features/AICodingTools/Domain/AICodingToolsReport.swift` so physical locations retain their compact `FileNode` tree and annotation rules. Make locations the selected tool's primary ordered children. Keep categories as computed composition data.

Add model invariants or initializers that reject duplicate standardized location paths inside one tool report.

### 2. Normalize and retain unique roots

Update `Sources/SpaceLens/Features/AICodingTools/Analysis/AICodingToolsAnalyzer.swift` to merge exact roots, collapse nested roots, scan each physical root once, and attach the resulting `FileNode` to the report. Preserve the current preflight statuses and observer-based category totals.

Extend bounded child retention only as needed to keep explicitly known nested catalog paths addressable.

### 3. Add component descriptions

Enrich the declarative catalog rules for Cursor, Claude Code, Codex, and Antigravity with concise component titles and descriptions. Keep rules at useful folder boundaries rather than attempting to label every file. Ensure unknown paths have a tool-specific neutral fallback.

### 4. Replace the category-first detail UI

Update `Sources/SpaceLens/Views/AICodingToolsView.swift` to render one location outline per tool. Add reusable root and recursive node rows, local disclosure state, aggregate-node treatment, and concise accessible labels. Retain the existing tool selector, report header, rerun, cancel, and project-root flows.

### 5. Generalize node actions

Update `Sources/SpaceLens/ViewModels/AppViewModel.swift` so Finder and Terminal actions accept any real node URL, and storage-map inspection accepts any readable directory node. Reuse the existing selected-folder scan path and session cache.

### 6. Update verification and documentation

Update XCTest coverage, matching framework-free self-tests, and `README.md`. Replace category-first screenshots or wording if present. Run the required build, test, and app packaging commands after implementation.

## Verification

Add focused tests for:

- Exact duplicate catalog roots producing one location.
- Nested catalog roots producing one outer location and one annotated descendant.
- A shared physical root being scanned and counted once overall.
- A selected tool exposing unique standardized location IDs.
- Direct filesystem children, sizes, item counts, and ordering matching the retained `FileNode` tree.
- More than 96 direct children preserving exact totals through **Smaller items**.
- A priority known child surviving bounded retention.
- Longest-prefix annotation selection and unknown-path fallback.
- Category summaries matching the sum of physical location contributions without owning/rendering those locations.
- Missing, unreadable, stalled, and symbolic-link roots remaining single non-expandable rows.
- Cancellation and late provider callbacks retaining the existing behavior.

Manual UI verification should cover all four tool selectors, large and empty roots, deep disclosure, light and dark appearances, keyboard navigation, VoiceOver descriptions, Finder/Terminal actions, and opening a nested directory in the storage map.

Required commands after implementation:

```bash
make test
make build
make app
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

## Acceptance criteria

- A standardized physical path appears no more than once in a selected tool's location outline.
- Cursor, Claude Code, Codex, and Antigravity all use the same filesystem-first interaction.
- Expanding a measured root reveals its actual retained filesystem children and their allocated sizes.
- Expanding a directory reveals the next retained level without rescanning.
- Known components have concise explanations; unknown paths remain visible and are described conservatively.
- Category information is presented as node metadata or a summary and never duplicates a location row.
- Tool and analysis totals do not double-count overlapping roots.
- Synthetic aggregates are clearly labeled and preserve omitted sizes and item totals.
- Scanning remains read-only, cancellable, symlink-safe, bounded, and isolated from stalled provider directories.
- The existing regular disk/folder scan and session cache continue to work.

## Deferred scope

- Parsing conversations, SQLite databases, configuration contents, or credentials.
- Cleanup, deletion, moving, vendor cleanup commands, or reclaimable-space estimates.
- Searching the entire home directory for project-local footprints.
- Category filters, search, comparison over time, and export.
- Docker, Node.js, Python virtual environments, package managers, and other developer-tool analyzers.
- An unbounded full-fidelity tree; the scanner's compact hierarchy remains the product contract.
