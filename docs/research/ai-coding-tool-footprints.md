# AI coding tool storage footprints for SpaceLens

Research date: 2026-09-09. Scope: macOS, Cursor, Claude Code, local Codex clients, and Google Antigravity. This is feature research; no application code or scanned data was modified. “Codex” here means its desktop, CLI, and IDE clients, rather than all ChatGPT data. Docker, language environments, and package-manager analysis remain future work.

The useful commonality is a storage vocabulary, with tool-specific evidence for each location. The categories below are a proposed SpaceLens model, not a claim that every client writes every category.

| Category | What it describes | Useful interpretation |
| --- | --- | --- |
| Conversations and session state | Transcripts, tool output, session databases, indexes of conversations | Supports resuming and understanding previous work |
| Recovery history | Pre-edit file copies, checkpoints, backups, editor local history | Can be the only remaining copy of an earlier edit |
| Artifacts and attachments | Plans, screenshots, recordings, generated images, uploaded files | May be a deliverable the user wants to keep |
| Workspaces and worktrees | Extra checkouts and scratch projects, including their generated files | Can grow with dependency installation and builds |
| Extensions, plugins, and runtimes | Installed packages, versioned plugin copies, agent workers, application binaries | Installed functionality and supporting dependencies |
| Caches and indexes | Verified regenerable render, download, search, or compiled-code caches | Regeneration cost depends on the actual component |
| Logs and diagnostics | Debug logs, crash reports, traces | Useful for investigation; not equivalent to conversations |
| Configuration and memory | Rules, skills, settings, persistent agent memory, credential-bearing state | Usually small; should not be treated as expendable storage |

Keep an “Other application data” remainder for mixed or unknown storage. Classify browser profiles separately from simple caches when they contain sign-ins, cookies, or persistent website state. A filename containing “cache,” “history,” or “log” is insufficient evidence by itself.

**Cursor.** These macOS locations were observed directly on this machine through directory names and allocated sizes:

| Location | Candidate classification |
| --- | --- |
| `~/Library/Application Support/Cursor/User/globalStorage/` | Mixed application and extension state; contains databases and agent-worker storage |
| `~/Library/Application Support/Cursor/User/workspaceStorage/` | Workspace-specific state |
| `~/Library/Application Support/Cursor/User/History/` | Editor history candidate |
| `~/Library/Application Support/Cursor/CachedData/`, `Cache/`, `GPUCache/`, `CachedExtensionVSIXs/` | Separate cache candidates; validate each component |
| `~/Library/Application Support/Cursor/logs/` | Diagnostic logs candidate |
| `~/.cursor/extensions/` | Installed editor extensions |
| `~/.cursor/worktrees/` | Tool-associated worktrees |
| `~/.cursor/projects/`, `plans/`, `snapshots/`, `plugins/`, `ai-tracking/` | Additional project/session/feature storage; precise subcategory requires validation |

Cursor support documents workspace `state.vscdb` files and their backup siblings, and distinguishes the sidebar session list from independent transcript files. Do not label every byte in a database or `globalStorage` as chat history. These are implementation locations rather than a stable storage API. [Cursor support: workspace session storage](https://forum.cursor.com/t/agents-panel-right-sidebar-lost-session-list-no-way-to-restore/153481/4).

Cursor documents isolated worktrees with their own dependencies and project setup through `.cursor/worktrees.json`. Its worktree retention behavior is version-dependent. Worktree storage can therefore include much more than source files. [Cursor worktrees](https://cursor.com/docs/configuration/worktrees).

The observed editor data also includes `WebStorage`, `Partitions`, and extension-specific directories. Keep these mixed unless evidence supports a finer classification. Do not assume a semantic-search index is a large local vector database: measure only verified local paths. Custom user-data roots, profiles, CLI installations, and remote hosts need separate detection coverage.

**Claude Code.** The documented default data root is `~/.claude`, replaceable with `CLAUDE_CONFIG_DIR`. Its `projects/` hierarchy includes session transcripts and large tool results; `file-history/` stores edit-recovery snapshots; `plans/`, `debug/`, `paste-cache/`, and attachment directories represent distinct kinds of data. Prompt recall history and persistent memory are separate from transcripts. Retention varies by category, settings, client, and version; do not infer that old files are unused. [Claude directory reference](https://code.claude.com/docs/en/claude-directory).

| Additional location | Classification and evidence |
| --- | --- |
| `~/.claude/plugins/cache/` | Installed plugin versions and potentially their Node dependencies, despite the “cache” name; [plugin reference](https://code.claude.com/docs/en/plugins-reference) |
| `<repository>/.claude/worktrees/` | Default isolated checkouts; hooks can customize creation and placement; [worktrees](https://code.claude.com/docs/en/worktrees) |
| `~/.local/share/claude/versions/` | Native installer binaries; the launcher in `~/.local/bin/claude` is a symlink; [installation reference](https://code.claude.com/docs/en/setup) |

Observe the actual installation method instead of assuming the native installer. A repository-only scan can find Claude worktrees while a scan of `~/.claude` alone misses them. Claude Desktop's overall application footprint is outside this initial Claude Code inventory unless a component can be attributed specifically to coding use.

**Codex.** Official documentation identifies `CODEX_HOME`, defaulting to `~/.codex`, as the local configuration/state root. It includes configuration, optional file credentials, history, logs, and caches. Project configuration can live at `.codex/config.toml`. The CLI history size setting should not be interpreted as a cap on all desktop storage. [Advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced).

| Location | Evidence and classification |
| --- | --- |
| `$CODEX_HOME/worktrees/` | Documented managed checkouts; the app also supports permanent worktrees and restoration snapshots; [worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees) |
| Configured `log_dir` and `sqlite_home` | Documented configurable log/state locations; [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) |
| `~/.codex/sessions/`, `archived_sessions/` | Observed here; session-storage candidates |
| `~/.codex/*sqlite`, accompanying `-wal` and `-shm` files | Observed here; state/history/log databases; version suffixes are not stable identifiers |
| `~/.codex/plugins/`, `skills/`, `cache/`, `.tmp/` | Observed here; installed capabilities, caches, and temporary storage requiring component-level classification |
| `~/.codex/generated_images/`, `computer-use/`, `visualizations/`, `shell_snapshots/` | Observed feature storage; names establish candidates, not complete retention or content semantics |
| `~/Library/Application Support/Codex/` | Observed desktop/browser storage, separate from the CLI home |

The observed SQLite names include `state_5`, `thread_history_1`, and `logs_2`; do not encode those exact versions as permanent rules. Desktop and CLI may share a home, so this must be a single measured root with multiple client associations. Conversely, one product can have several roots. No Codex-managed worktree directory was present in the inspected default home; that does not establish that no worktrees exist elsewhere.

**Google Antigravity.** Current official documentation distinguishes desktop, CLI, and IDE surfaces. [Product surfaces](https://antigravity.google/docs/home).

Google documents persistent transcripts at `<app_data_dir>/brain/<conversationId>/.system_generated/logs/transcript.jsonl`, with `~/.gemini/antigravity` for Antigravity 2.0 and `~/.gemini/antigravity-cli` for CLI. Conversation artifact directories contain artifacts and screenshots. A `logs` path here can contain conversation history, so generic log rules would be wrong. [Hook storage contract](https://antigravity.google/docs/hooks/).

| Location | Evidence and classification |
| --- | --- |
| `~/.gemini/antigravity/brain/` | Documented conversation artifacts and transcript hierarchy |
| `~/.gemini/antigravity/conversations/`, `browser_recordings/`, `implicit/`, `bin/` | Observed here; keep separate, validate exact semantics and version support |
| `~/Library/Application Support/Antigravity/` | Observed IDE user state, caches, and logs |
| `~/.antigravity/extensions/` | Observed installed IDE extensions |
| `~/.gemini/antigravity-cli/` | Documented CLI data root; not measured in this inventory |

Antigravity also documents a separate browser profile, which is persistent browser state rather than merely a screenshot cache. [Separate Chrome profile](https://antigravity.google/docs/ide/separate-chrome-profile/). The local layout can reflect an older installed client than current documentation. Do not attribute all of `~/.gemini` to Antigravity or assume Gemini CLI has identical ownership.

**Partial measurements from this Mac.** Read-only `du -P -k -d 1 -x` and `stat` checks inspected directory metadata and allocation, without following symlinks or reading conversations, artifacts, database rows, or credential contents. Values below convert KiB output to GiB. These are separate live measurements, not an atomic snapshot or an estimate of uniquely reclaimable space.

| Tool | Roots measured | Allocated size |
| --- | --- | ---: |
| Cursor | `~/.cursor` + `~/Library/Application Support/Cursor` | 14.30 GiB |
| Antigravity | `~/.gemini/antigravity` + `~/.antigravity` + `~/Library/Application Support/Antigravity` | 3.12 GiB |
| Codex | `~/.codex` + `~/Library/Application Support/Codex` | 0.90 GiB |
| Claude Code | `~/.claude` | 0.50 GiB |

This is not a fair product benchmark. Usage, features, client versions, retention, and coverage differ. Application bundles, external native installers, general Library caches/logs, customized roots, and repository-local storage were not comprehensively measured. Root sizes are observations, not proof that every byte is uniquely attributable to that product.

Selected observations:

- Cursor's `User/globalStorage` was approximately 6.11 GiB, `User/workspaceStorage` 1.53 GiB, extensions 2.30 GiB, and worktrees 0.61 GiB. The agent-worker directory inside `globalStorage` was itself about 1.76 GiB, illustrating why global storage cannot be labeled entirely as conversations.
- Antigravity's observed `conversations` directory was about 844 MiB, extensions 892 MiB, `brain` 247 MiB, and `browser_recordings` 155 MiB. Directory names alone do not establish whether any item is disposable.
- Codex's plugins were about 315 MiB and sessions about 135 MiB.
- Claude Code's projects were about 337 MiB and plugins about 166 MiB.

**Recommended first version.** Add an “AI coding tools” analysis view, with each tool expandable into the common categories, then real locations. Show measured bytes, item counts where meaningful, modification age, coverage, and a plain-language explanation. Keep Finder and Terminal actions. Preserve an accessible ranked list alongside any visualization.

Start with known local roots and project-local markers encountered inside the authorized scan. Let users add custom locations. Detect leftover data even if an application is no longer installed. Distinguish “not found,” “unreadable,” “not scanned,” and “unsupported layout.” Do not silently broaden a selected-folder scan to the user's entire home.

Useful insights include large session stores, retained plugin/runtime versions, large worktrees, and storage associated with projects whose original paths are unavailable. Missing projects and old modification times should produce review hints, not claims that data is abandoned. Avoid reading full conversations merely to measure size. Linking sessions to projects should use narrowly scoped, supported metadata where available; otherwise leave the project association unknown.

A future extension to Docker, Node, and Python should preserve separate concepts for the tool that manages a location and the kind of storage inside it. For example, dependencies under a Cursor worktree can appear in both filtered views while contributing bytes only once to the overall total. Shared npm/uv caches or an external MCP server should remain shared unless ownership is established. Running an agent in a user's existing repository does not make the entire repository agent-owned.

**Accounting and integration constraints.** These are design recommendations informed by the repository and the storage evidence:

- Keep traversal in `DiskScanner`; keep recognition/classification distinct from filesystem measurement. Tool rules should be versioned and carry their evidence and last verification date.
- Measure disjoint regions. Count a tool root once, then partition it; never add an ancestor total to its descendant totals. Preserve an unclassified remainder.
- Group SQLite databases with their sidecars for explanation. The WAL can contain committed data, so it is not a disposable diagnostic log. Merely measuring file metadata avoids changing live databases. [SQLite WAL documentation](https://sqlite.org/wal.html).
- Linked Git worktrees share repository data. Do not charge the shared Git object store once per worktree. [Git worktree documentation](https://git-scm.com/docs/git-worktree).
- Continue using allocated bytes and respecting filesystem boundaries. A reported size is not a promise of space recovered by deletion. Hardlinks, shared filesystem extents, and overlapping roots require separate consideration when designing a reclaim estimate; such an estimate is outside this first version.
- Keep symlink targets outside the traversal. Report that a known root is linked, and allow its real directory to be selected separately instead of silently following it.
- Preserve cancellation, bounded concurrency, stalled-provider timeouts, permission reporting, and the current Full Disk Access behavior.
- The current scanner retains at most 96 direct children per directory, combining others into `Smaller items`; persisted summaries also limit depth. Classification after this reduction cannot recover all tool entries. Collect category totals before compaction or perform targeted scans through the same safe traversal machinery. See `Sources/SpaceLens/Services/DiskScanner.swift`, `Models/FileNode.swift`, and `Models/PreviousScanSummary.swift`.
- Current `FileNode` values do not retain modification timestamps or tool/project attribution. Any proposed age or growth view needs additional analysis metadata; an existing chart snapshot alone is insufficient.

No deletion controls, database maintenance, automatic pruning, or implementation are part of this research. The first feature should answer: which tool is associated with this space, what kind of data is it, where is it, and how complete is the measurement?
