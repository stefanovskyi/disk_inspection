# OpenCode storage footprints on macOS

Verified: 2026-09-10  
Scope: local OpenCode CLI and desktop storage relevant to SpaceLens

## Findings

OpenCode follows the XDG directory convention even on macOS. Its current source defines separate data, configuration, cache, and state roots, each with an `opencode` child. The CLI uninstall command treats those four directories as OpenCode-owned storage. The default paths are:

| Surface | Default path | Significant contents |
| --- | --- | --- |
| Persistent data | `~/.local/share/opencode` | Session database, credentials, logs, snapshots, plans, worktrees, repository checkouts, and legacy session storage |
| Configuration | `~/.config/opencode` | Global JSON/JSONC and TUI configuration, `AGENTS.md`, agents, commands, modes, plugins, skills, tools, themes, and installed configuration dependencies |
| Cache | `~/.cache/opencode` | Rebuildable metadata and downloads, downloaded tools, plugin dependencies, and discovered skills |
| State | `~/.local/state/opencode` | Durable CLI state such as prompt history |
| Script installation | `~/.opencode` | The `bin/opencode` executable installed by the current curl installer |
| Desktop UI data | `~/Library/Application Support/ai.opencode.desktop` | Electron UI state, web storage, caches, crash data, logs, and bundled CLI state |

`XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, and `XDG_STATE_HOME` replace the corresponding XDG base directories. OpenCode then appends `opencode`. SpaceLens should inspect a visible environment override in addition to its conventional default so stale data left at the default path remains visible.

OpenCode also supports `OPENCODE_CONFIG_DIR`, which names another configuration directory. It is safe to treat this as an additional root when the value is an absolute path. `OPENCODE_CONFIG` names an individual configuration file, and `OPENCODE_DB` can name an individual database file. Those file overrides do not fit the AI analyzer's current directory-root preflight contract and are not required for the first OpenCode catalog.

The stable desktop application ID is `ai.opencode.desktop`; source also defines `.beta` and `.dev` variants. The initial catalog should include stable and beta application-data roots. Development builds can be added later if there is evidence that users need them, avoiding an extra missing-location row for normal installations.

OpenCode documents a managed macOS configuration directory at `/Library/Application Support/opencode`. This is system-level configuration rather than per-user application data. It can be represented as an optional configuration root without scanning `/Library/Application Support` broadly. Managed preference plist files should remain out of scope.

## Data-root classification

The current release stores sessions in a SQLite database under the data root. Release channels generally use `opencode.db`; development channels can use `opencode-<channel>.db`. SQLite runs in WAL mode, so `-wal` and `-shm` files belong to the session database and must not be described as disposable logs.

| Relative path | SpaceLens category | Explanation |
| --- | --- | --- |
| `opencode.db*`, `opencode-*` | Conversations and sessions | Current session database and its SQLite sidecars or channel-specific variants |
| `project/`, `storage/` | Conversations and sessions | Legacy project/session JSON storage retained across upgrades |
| `snapshot/` | Recovery and history | Git snapshots used to record or revert file changes |
| `plans/` | Generated artifacts | Plan documents saved outside a Git worktree |
| `worktree/` | Worktrees and checkouts | Isolated Git worktrees created for OpenCode tasks |
| `repos/` | Worktrees and checkouts | Local checkouts of remote repository references |
| `log/` | Logs and diagnostics | OpenCode diagnostic logs |
| `auth.json` | Configuration and memory | Provider credentials; SpaceLens must measure metadata only and never open or preview the file |

The data root should default to **Other tool data** so unknown future files remain visible without guessing their purpose.

## Configuration-root classification

OpenCode supports plural directory names and legacy singular names. The catalog should recognize both.

| Relative path | SpaceLens category |
| --- | --- |
| `opencode.json`, `opencode.jsonc`, `config.json`, `tui.json`, `AGENTS.md` | Configuration and memory |
| `agents/`, `commands/`, `modes/`, `skills/`, `tools/`, `themes/` and singular equivalents | Configuration and memory |
| `plugins/`, `plugin/`, `node_modules/` | Extensions and runtimes |
| `package.json`, lock files | Extensions and runtimes |

Project-local `.opencode` directories follow the same rules, with `.opencode/plans` classified as generated artifacts. They should be discovered only beneath project roots the user has explicitly selected. Direct project files such as `AGENTS.md`, `opencode.json`, and `tui.json` are usually source-controlled, can be shared by several tools, and are small; the first catalog should not attribute those files to OpenCode.

OpenCode can read Claude Code's `~/.claude` and project `CLAUDE.md` conventions as fallbacks. These locations must not be registered as OpenCode roots because they are already owned by the Claude Code catalog and would make the selected-tool view claim shared or foreign data as OpenCode storage.

## Cache, state, installation, and desktop classification

- The cache root defaults to **Caches and indexes**. `bin/`, `node_modules/`, and downloaded `skills/` are better described as **Extensions and runtimes** because they are installed executable or reusable content.
- The state root defaults to **Other tool data**. `prompt-history.jsonl` is **Conversations and sessions**.
- `~/.opencode` defaults to **Extensions and runtimes** because it is the curl install location for the CLI executable.
- Desktop roots default to **Other tool data**. Electron `Cache`, `Code Cache`, `GPUCache`, and Dawn cache folders are caches; `Crashpad` and `logs` are diagnostics; `cli` is an installed runtime; and `opencode.settings*`, `opencode.global*`, `opencode.workspace*`, and `opencode.window*` are configuration/UI state.

OpenCode's temporary directory, package-manager installation locations, `/Applications/OpenCode.app`, and files emitted into arbitrary project working directories are outside the first catalog. Scanning a shared Homebrew, npm, or project root would over-attribute unrelated developer storage. Those locations belong in the later general developer-tools analysis.

## Primary sources

- [OpenCode global path definitions](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/global.ts)
- [OpenCode configuration locations](https://opencode.ai/docs/config)
- [OpenCode rules and Claude compatibility](https://opencode.ai/docs/rules)
- [OpenCode credential location](https://opencode.ai/docs/providers)
- [OpenCode storage and troubleshooting](https://opencode.ai/docs/troubleshooting/)
- [OpenCode SQLite database path and WAL configuration](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/database/database.ts)
- [OpenCode authentication storage](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/auth/index.ts)
- [OpenCode snapshot storage](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/snapshot/index.ts)
- [OpenCode worktree storage](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/worktree/index.ts)
- [OpenCode desktop application IDs and Electron user-data path](https://github.com/anomalyco/opencode/blob/dev/packages/desktop/src/main/index.ts)
- [OpenCode desktop state migration](https://github.com/anomalyco/opencode/blob/dev/packages/desktop/src/main/migrate.ts)
- [OpenCode installer and default CLI binary location](https://github.com/anomalyco/opencode/blob/dev/install)
- [OpenCode uninstall directory inventory](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/cli/cmd/uninstall.ts)

