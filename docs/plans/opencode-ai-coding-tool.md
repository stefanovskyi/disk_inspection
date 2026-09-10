# OpenCode AI coding tool — implementation plan

Status: implemented  
Prepared: 2026-09-10  
Research: [`../research/opencode-storage-footprints.md`](../research/opencode-storage-footprints.md)  
Architecture: [`../architecture/ai-coding-tools.md`](../architecture/ai-coding-tools.md)

## Objective

Add **OpenCode** as the fifth tool in the existing AI Coding Tools analysis. When OpenCode is selected, SpaceLens should show each known physical folder once, its allocated size and status, and an expandable filesystem tree with component descriptions. OpenCode must participate in the same on-demand, read-only, cancellable analysis lifecycle as Cursor, Claude Code, Codex, and Google Antigravity.

This addition should use the feature's existing extension seam. The analyzer, store, filesystem outline, scan coordinator, and app navigation do not need OpenCode-specific branches.

## Supported locations

Register these roots in `OpenCodeCatalog`, preserving conventional defaults when an environment override is also visible:

| Root | Source | Default category | Purpose |
| --- | --- | --- | --- |
| `~/.local/share/opencode` | default, or `${XDG_DATA_HOME}/opencode` | Other tool data | Sessions, credentials, logs, recovery snapshots, plans, worktrees, and legacy data |
| `~/.config/opencode` | default, or `${XDG_CONFIG_HOME}/opencode` | Configuration and memory | Global configuration, rules, agents, plugins, skills, commands, and themes |
| `~/.cache/opencode` | default, or `${XDG_CACHE_HOME}/opencode` | Caches and indexes | Rebuildable indexes and downloads, package dependencies, skills, and helper binaries |
| `~/.local/state/opencode` | default, or `${XDG_STATE_HOME}/opencode` | Other tool data | CLI state and prompt history |
| `OPENCODE_CONFIG_DIR` | environment, when absolute | Configuration and memory | User-selected configuration tree |
| `~/.opencode` | curl installer | Extensions and runtimes | User-local OpenCode executable installation |
| `~/Library/Application Support/ai.opencode.desktop` | stable desktop app | Other tool data | Electron state, caches, logs, and bundled CLI files |
| `~/Library/Application Support/ai.opencode.desktop.beta` | beta desktop app | Other tool data | Separate beta-channel desktop state |
| `/Library/Application Support/opencode` | managed macOS config | Configuration and memory | Administrator-managed OpenCode JSON/JSONC settings |
| `<selected-project>/.opencode` | user-selected project roots | Configuration and memory | Project agents, commands, plugins, skills, tools, themes, and plans |

For each XDG variable, register the default root and append the environment-derived root only when it is absolute and differs after standardization. This follows SpaceLens's additive-root policy: OpenCode may leave meaningful stale data at the old default after a path change.

Do not register the whole home directory, project directory, `/Applications`, Homebrew prefixes, or global Node package directories. Those locations mix unrelated storage and belong to the future general developer-tools analyzer.

## Component rules

Use path-only rules so analysis never opens a transcript, SQLite database, credential file, or configuration file.

### Persistent data

| Relative path | Category | Description shown at the component root |
| --- | --- | --- |
| `opencode.db*`, `opencode-*` | Conversations and sessions | OpenCode session database and SQLite sidecars |
| `project`, `storage` | Conversations and sessions | Legacy project and session storage |
| `snapshot` | Recovery and history | Git snapshots used to recover changes made during tasks |
| `plans` | Generated artifacts | Plans saved outside a Git worktree |
| `worktree` | Worktrees and checkouts | Isolated Git checkouts created for OpenCode tasks |
| `repos` | Worktrees and checkouts | Local checkouts of remote repository references |
| `log` | Logs and diagnostics | OpenCode diagnostic logs |
| `auth.json` | Configuration and memory | Provider credentials; metadata is measured without reading contents |

The current matcher already supports the required prefix patterns: `opencode.db*` covers the release database and sidecars, while `opencode-*` covers channel-specific database names and sidecars. No path-matcher change is required.

### Configuration and selected-project `.opencode`

Recognize `opencode.json`, `opencode.jsonc`, `config.json`, `tui.json`, and `AGENTS.md` as configuration. Classify plural and legacy singular agent, command, mode, skill, tool, and theme directories as configuration. Classify `plugins`, `plugin`, `node_modules`, package manifests, and lock files as extensions and runtimes. Within selected-project `.opencode`, classify `plans` as generated artifacts.

Do not add `~/.claude`, project `CLAUDE.md`, or `.claude/skills` to OpenCode. OpenCode reads those paths only for Claude compatibility, and SpaceLens should not attribute Claude-owned storage to a second selected tool.

### Cache, state, installation, and desktop

- The cache root inherits **Caches and indexes**. Override `bin`, `node_modules`, and `skills` to **Extensions and runtimes**.
- The state root inherits **Other tool data**. Mark `prompt-history.jsonl` as **Conversations and sessions**.
- The curl installation root inherits **Extensions and runtimes**.
- Desktop roots inherit **Other tool data**. Reuse the relevant Electron cache and diagnostic rules, classify `cli` as **Extensions and runtimes**, and classify `opencode.settings*`, `opencode.global*`, `opencode.workspace*`, and `opencode.window*` as **Configuration and memory**.

## Code changes

### 1. Add the tool identity and catalog

- Add `AICodingToolID.openCode` with raw value `opencode` in `AICodingToolsReport.swift`.
- Add `Catalogs/OpenCodeCatalog.swift` containing the display metadata, roots, descriptions, category rules, and project-local `.opencode` descriptors.
- Use an SF Symbol such as `terminal.fill`; product identity remains the text label **OpenCode**.

Keep all vendor paths and component descriptions in this catalog. The analyzer and views should continue to consume generic `AICodingToolDefinition` records.

### 2. Add reusable XDG root resolution

Extend `AICodingCatalogSupport` with a small helper that:

1. Builds a conventional base directory relative to `request.homeDirectory`.
2. Reads an XDG base environment variable when present.
3. Accepts only absolute environment values.
4. Appends the `opencode` component.
5. Returns the default and distinct override candidates in stable order.

Use the existing `configuredDirectory` helper for absolute `OPENCODE_CONFIG_DIR`, tightening or wrapping it if needed so this catalog does not guess the meaning of a relative path.

This helper is the only shared catalog change. It will also be useful when the broader developer-tools analysis adds XDG-aware tools.

### 3. Register OpenCode

Append `OpenCodeCatalog.definition(for:)` and `OpenCodeCatalog.metadata` to `AICodingToolsCatalog`. Keep the stable order:

1. Cursor
2. Claude Code
3. Codex
4. Google Antigravity
5. OpenCode

The tool sidebar, selected-tool detail, ranked report, progress display, empty-result handling, and session state already derive their contents from the registry. They require no OpenCode conditionals.

### 4. Update compile inputs and product copy

- Add `OpenCodeCatalog.swift` to `Scripts/run_self_tests.sh` because the framework-free build lists catalog sources explicitly.
- Update the supported-tool text in `AICodingToolsView.swift`, `VolumeSidebar.swift`, and `README.md` from four tools to five.
- Update `docs/architecture/ai-coding-tools.md` only to list OpenCode among the supported catalog definitions; its autonomy boundary does not change.

## Explicitly deferred coverage

- `OPENCODE_CONFIG` and an external absolute `OPENCODE_DB` value name individual files. The current analyzer preflight accepts directory roots. The default database is already covered by the data root, and configuration files are generally tiny, so file-root support should be a separate generic enhancement rather than expanding this tool addition.
- Direct project `AGENTS.md`, `opencode.json`, `opencode.jsonc`, and `tui.json` remain part of the selected source tree. They can be shared or committed files and should not be claimed as OpenCode-owned storage. Project `.opencode` directories are covered.
- `~/.claude` compatibility data remains owned by the Claude Code catalog.
- OpenCode temporary files, development-channel desktop data, package-manager installation directories, `/Applications/OpenCode.app`, remote servers, containers, and files emitted into arbitrary project locations remain out of scope.
- The catalog will describe measured size and purpose. It will not call `opencode uninstall`, suggest deletion, or label any bytes reclaimable.

## Tests

Extend `AICodingToolsAnalyzerTests` with catalog-focused tests that verify:

- The built-in metadata and definition order includes `.openCode` exactly once.
- Default data, config, cache, state, curl-install, stable desktop, beta desktop, managed-config, and selected-project roots resolve to their expected standardized paths.
- Each visible XDG override is additive and an override equal to the default does not create a duplicate location.
- Relative or empty XDG values are ignored rather than resolved against the home directory.
- An absolute `OPENCODE_CONFIG_DIR` is additive and categorized as configuration.
- Current database files, WAL/SHM sidecars, channel-specific databases, legacy session folders, snapshots, plans, worktrees, repository checkouts, logs, and credentials receive the intended categories.
- Configuration rules cover plural and singular component directories.
- Cache helper binaries/dependencies, prompt history, and desktop components receive the intended categories.
- `<selected-project>/.opencode/plans` is an artifact while plugins and configuration components retain their own categories.
- No OpenCode descriptor points into `.claude` or scans an entire selected project root.

Add matching catalog smoke assertions to `Scripts/SelfTests.swift` for installations where XCTest is unavailable. Existing analyzer tests already cover unique physical roots, nested descriptors, symlink handling, cancellation, partial results, compact-tree retention, and longest-prefix annotations; those behaviors should not be duplicated in OpenCode-specific tests.

## Verification

After implementation, run:

```bash
make test
make build
make app
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

Manually verify an empty OpenCode installation and a populated fixture with at least the data, config, cache, and desktop roots. Confirm that:

- OpenCode appears in the tool selector and analysis progress.
- Every standardized root appears once in the selected-tool outline.
- Expanding a root shows actual retained children and the expected component descriptions.
- Database sidecars appear under the session component rather than logs.
- Missing optional roots remain clear, non-expandable status rows.
- Finder, Terminal, and Inspect Storage Map actions continue to work for measured directories.
- The view remains usable at 1100 × 620 points, in light and dark appearances, and with VoiceOver.

## Acceptance criteria

- OpenCode is available as the fifth AI Coding Tool without adding tool-specific logic to the analyzer, store, or filesystem outline.
- Standard OpenCode CLI and desktop directories on macOS are measured using allocated-size semantics.
- Visible XDG and custom configuration-directory overrides are included without hiding stale conventional roots or duplicating identical paths.
- The selected OpenCode view lists each physical folder once and expands the compact filesystem tree without rescanning.
- Category totals equal the measured OpenCode locations, and shared/overlapping roots retain the analyzer's existing unique-total behavior.
- Session databases and their SQLite sidecars are classified together; legacy session storage remains visible.
- Credentials and other file contents are never opened for classification.
- Claude compatibility paths, broad project roots, and shared package-manager directories are not misattributed to OpenCode.
- Scanning remains read-only, cancellable, symlink-safe, bounded, and isolated from provider stalls.
- Existing four-tool behavior and regular disk/folder analysis continue to pass all required checks.
