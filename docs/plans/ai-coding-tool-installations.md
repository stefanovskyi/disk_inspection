# AI coding tool installation inventory — implementation plan

Status: implemented (first release boundary)
Prepared: 2026-09-10
Implemented: 2026-09-10
Research: [`../research/ai-coding-tool-installations.md`](../research/ai-coding-tool-installations.md)
Architecture: [`../architecture/ai-coding-tools.md`](../architecture/ai-coding-tools.md)

## Objective

Extend AI Coding Tools from a storage-only report into a combined local inventory. For each supported tool, SpaceLens should show independently installed native applications and CLIs, the delivery method when it can be established, the installed version when static metadata provides it, and an evidence-labelled local install/update date when one exists.

Installation discovery must remain read-only and must not launch a discovered executable. It is shallow metadata inspection, not another recursive disk scan.

## Product decisions

Use these decisions for the first implementation:

1. **Installations and storage are independent.** A tool can have an installation with no known storage, leftover storage with no current installation, both, or neither.
2. **One owner is one installation.** Command aliases resolving to one package/bundle/release root are entry points of a single installation. Different owning roots remain separate installations even if their versions match.
3. **Components are not installations.** An app-bundled CLI is a component of that app unless there is separate manager or owning-root evidence. Its version may differ from the app version.
4. **Retained releases are not installations.** An active self-updating CLI is one installation with an active release and zero or more retained releases.
5. **Unknown is preferable to a guess.** Show a date as **Installed/updated** only when a manager receipt records that event. Keep filesystem dates explicitly labelled as observed evidence and hide them from the summary row.
6. **Static inspection only.** Do not execute `--version`, source shell profiles, invoke package managers, or perform remote latest-version checks.
7. **Conventional roots first.** Defer manually adding arbitrary app/binary locations until the automatic inventory has shipped and its misses are understood.
8. **Signature identity is supporting evidence.** Retain it for matching and diagnostics when available; do not make it a normal user-facing field or reject a recognized installation solely because a vendor changed signing identity.

## User experience

Add an **Installations** panel to `AICodingToolDetailView`, between the tool header and storage composition.

Each installation card should show:

- surface and display name, such as **Native app** or **CLI**;
- installed version and build when known;
- installation method when supported by a receipt or package layout;
- application/package root;
- the authoritative local manager event date, when available;
- a compact entry-point summary, such as `agent, cursor-agent`;
- separately versioned bundled components; and
- a disclosure such as **2 older releases retained** for inactive releases.

Use exact evidence-aware wording:

| Evidence | Summary wording |
| --- | --- |
| Homebrew receipt `time` | `Homebrew installed/updated Sep 10, 2026` |
| App `Info.plist` version | `Version 3.19.19 (build …)` |
| Exact package manifest version | `Version 1.18.29` |
| Active versioned symlink target | `Version 2.1.223` |
| Filesystem timestamp only | Omit from summary; show `Observed file date …` in evidence details |
| No usable source | `Version unknown` or no date row |

The existing **No storage found** panel must not imply that the tool is uninstalled. Change its supporting text to describe storage only. Conversely, a data-only tool should say that no recognized installation was found while still presenting its measured storage.

Keep installation paths copyable and add **Show in Finder** where the path represents a visible bundle or package/release root. Do not add uninstall, update, cleanup, or launch actions.

## Domain model

Add installation types in `Sources/SpaceLens/Features/AICodingTools/Domain/AICodingToolInstallations.swift`:

```swift
enum AICodingInstallationSurface: String, Sendable {
    case nativeApplication
    case commandLine
}

enum AICodingInstallMethod: String, Sendable {
    case appStore
    case homebrewFormula
    case homebrewCask
    case npm
    case pnpm
    case yarn
    case bun
    case mise
    case nativeInstaller
    case directDownload
    case unknown
}

enum AICodingInstallationConfidence: Int, Sendable {
    case heuristic
    case strong
    case authoritative
}

struct AICodingInstallationFact<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let source: AICodingInstallationEvidenceSource
    let confidence: AICodingInstallationConfidence
}
```

The evidence source should identify both the kind and local source URL: app manifest, package manifest, Homebrew receipt, versioned-release target, command link, static code signature, or filesystem metadata. This makes every displayed assertion explainable and lets tests verify precedence.

Model an installation with:

- stable ID derived from tool ID, surface, and standardized owning root;
- tool ID, surface, display name, and owning root URL;
- zero or more entry points;
- optional version, build, install method, and manager event date facts;
- zero or more bundled components with their own optional versions;
- zero or more retained releases;
- whether an entry point was visible on the current process PATH; and
- non-fatal discovery notes when metadata was unreadable, malformed, or ambiguous.

Extend `AICodingToolReport` with `installations: [AICodingToolInstallation]`. Preserve its current storage-derived totals and sorting. Add convenience properties such as `hasRecognizedInstallation` without using installation presence to change storage accounting.

Do not put a single `version` on `AICodingToolMetadata`; one tool can have several versions installed at once.

## Catalog changes

Extend each existing per-tool catalog with an installation definition. Keep identity and path knowledge out of the generic detector. A definition should describe:

- known application bundle identifiers and expected roles;
- expected application names only as fallback hints;
- exact JavaScript package names;
- known Homebrew formula/cask tokens where verified;
- official standalone roots and versioned-layout rules;
- CLI command names and aliases;
- known bundled component paths; and
- optional publisher TeamIdentifiers with a verification date.

Register these through `AICodingToolsCatalog`, preserving the current tool order. Bundle identifier or exact package name should outrank a filename match. A filename alone can produce a discovery note, but must not establish a high-confidence installation.

Initial surface coverage:

| Tool | Application candidates | Standalone CLI candidates | Package-manager candidates |
| --- | --- | --- | --- |
| Cursor | Cursor app | Cursor Agent versioned layout; `agent` and `cursor-agent` aliases | Correlate a matching cask receipt if present |
| Claude Code | Claude desktop app | Native versioned `claude`; legacy local install | Homebrew and exact `@anthropic-ai/claude-code` manifests |
| Codex | ChatGPT/Codex desktop app | Standalone `codex` release/current layout | Homebrew, exact `@openai/codex` manifests, compatible Bun layout |
| Google Antigravity | Antigravity and Antigravity IDE bundles | Flat `agy` native CLI | Native updater layout where static evidence is available |
| OpenCode | OpenCode desktop app | Official direct-install root and `opencode` | Homebrew formula/cask, `opencode-ai` under npm/Bun/pnpm/Yarn, Mise |

## Detector architecture

Add a shallow detector beside the storage analyzer:

```text
AICodingToolsAnalyzer
├── DiskScanner
└── AICodingInstallationsDetector
    ├── ApplicationBundleSource
    ├── HomebrewReceiptSource
    ├── StandaloneCLISource
    ├── JavaScriptGlobalPackageSource
    └── ProcessPathEntryPointSource
```

Define `AICodingInstallationsDetecting` and inject it into `AICodingToolsAnalyzer`, as is already done for `DiskScanner`. Detection should receive `AICodingToolsRequest` so fixtures can control the home directory, application-support directory, environment, and PATH without reading the test runner's machine.

Run installation detection and storage-root work concurrently inside the analyzer with structured concurrency. Both branches must propagate cancellation. Installation discovery must not be held behind recursive scan progress; its results join the report only after both branches complete. The store's operation-ID protection and refresh lifecycle should remain unchanged.

### Source behavior

**Application bundles**

- Enumerate only immediate `.app` children of `/Applications` and `~/Applications` in version one.
- Read a matched bundle's `Contents/Info.plist` for identity, release version, and build.
- Check for a Homebrew or App Store receipt before assigning an install method.
- Optionally validate static code-signing identity through Security APIs; do not use a signing timestamp as an install date.
- Treat Launch Services and Spotlight as optional future supplements, not required sources.

**Homebrew**

- Inspect `/opt/homebrew` and `/usr/local`, plus a known prefix derived from an already discovered entry point.
- Parse only matching formula/cask receipt paths; never invoke `brew`.
- Use receipt version/source fields for method and version evidence.
- Interpret receipt `time` as the latest Homebrew install/upgrade event, without claiming which of the two occurred.
- Correlate cask artifacts with an already discovered app bundle so they become one installation.

**Standalone CLIs**

- Inspect only catalogued roots such as `~/.local/bin`, `~/.local/share/<tool>`, `~/.opencode/bin`, and configured `CODEX_HOME`/install roots when visible in the supplied environment.
- Resolve a command symlink with `lstat`/`readlink`, a loop check, and a small hop limit. Do not follow directory symlinks during enumeration.
- Parse versions from documented release-directory names when the active target selects one.
- Group inactive sibling releases under the active installation.
- Record flat binaries such as `agy` even when their version remains unknown.

**Global JavaScript packages**

- Match exact package names and read only their `package.json`.
- Inspect conventional npm, NVM, Bun, pnpm, and Yarn global layouts at fixed depths. Do not recursively search the home directory for `node_modules`.
- Keep installations under distinct Node/runtime roots separate.
- Treat shims such as Volta as entry-point evidence until their owning package can be resolved statically.

**PATH entry points**

- Split only `request.environment["PATH"]`; never start a login shell.
- Inspect exact catalogued command names in each PATH directory.
- Use PATH visibility as a badge or evidence detail, not proof that no other installation exists.
- Correlate a link or executable with an owning app, package, or standalone root before deduplication.

## Matching and deduplication pipeline

Normalize source observations in this order:

1. Standardize paths without resolving arbitrary directory symlinks.
2. Identify owning roots from exact bundle IDs, package manifests, receipts, or documented release layouts.
3. Resolve bounded command-link chains and attach aliases to the owning root.
4. Correlate manager receipts with their installed artifact.
5. Attach app-bundled executables as components.
6. Group inactive version siblings as retained releases.
7. Merge facts for the same stable installation ID, choosing higher confidence first and deterministic source priority on a tie.
8. Keep different owning roots as separate installs, even when tool, surface, method, and version match.

Never deduplicate solely by version or command name. Preserve conflicting high-confidence facts as a discovery note instead of silently choosing one.

## Safety and privacy constraints

- Parse only catalogued manifest and receipt files; cap plist/JSON input size before decoding.
- Bound directory depth, entry counts, and symlink hops per source. Return partial discoveries plus a coverage note when a bound or permission prevents complete inspection.
- Do not open conversation records, SQLite databases, source files, project contents, settings, credentials, or shell startup files.
- Do not execute applications, package managers, shims, or CLIs.
- Do not contact vendor, registry, or release APIs.
- Do not infer an update from ordinary tool-data modification dates.
- Keep all work cancellable and off the main actor.

Update the in-app and README privacy copy to:

> SpaceLens reads filesystem metadata plus app and package manifests needed to identify installations and versions. It does not open conversations, project files, databases, or credentials.

## Implementation sequence

### 1. Domain and fixtures

- Add the installation domain types and evidence precedence rules.
- Add an empty `installations` collection to report construction sites and test doubles.
- Create synthetic fixture builders for app bundles, package manifests, receipts, symlinks, and native release directories.
- Add report-level tests before adding real-machine discovery.

### 2. Application and native-CLI discovery

- Add catalog installation definitions for all five tools.
- Implement application bundle manifest inspection.
- Implement bounded link resolution and the Cursor Agent, Claude Code, Codex standalone, Antigravity `agy`, and OpenCode direct-install layouts.
- Implement aliases, app-bundled components, and retained releases.

### 3. Package-manager evidence

- Implement Homebrew formula/cask receipt parsing and artifact correlation.
- Implement exact global JavaScript-package discovery across the selected fixed-depth layouts.
- Add current-process PATH discovery as supplementary evidence.
- Add optional static signature checks only after the path/manifests pipeline is stable.

### 4. Report integration and state

- Inject the detector into `AICodingToolsAnalyzer` and combine installation and storage results.
- Preserve cancellation, progress, duration, stale-result protection, and supported-tool ordering.
- Ensure a tool report is retained for installation-only and data-only states.

### 5. UI and copy

- Add `AICodingInstallationsSummary` and installation cards to `AICodingToolDetailView`.
- Add evidence details, entry points, components, and retained-release disclosure.
- Revise storage-empty messaging and privacy copy in `AICodingToolsView` and `README.md`.
- Keep native accessibility labels, keyboard focus, light/dark appearance, and the 1100 × 620 minimum layout usable.

### 6. Architecture documentation and verification

- Update `docs/architecture/ai-coding-tools.md` with the detector boundary and new report relationship.
- Document supported and intentionally unsupported install channels.
- Run the required project checks and manually validate representative real installations.

## Tests

Add focused tests for:

- two aliases resolving to one standalone installation;
- active and inactive native releases producing one install plus retained releases;
- two different owning roots with the same version remaining separate;
- an app-bundled CLI becoming a component rather than a second install;
- app version/build parsing from a matching bundle ID;
- misleading bundle timestamps never becoming an authoritative update date;
- Homebrew formula and cask receipts, including artifact correlation and receipt time wording;
- exact package-name matching and rejection of lookalike manifests;
- the same npm package under two NVM Node versions producing two installations;
- Bun, pnpm, and Yarn conventional layouts;
- broken links, link loops, excessive link depth, malformed/oversized manifests, unreadable roots, and bounded-enumeration notes;
- PATH visibility supplementing rather than filtering discoveries;
- conflicting evidence precedence and deterministic ordering;
- installation-only, storage-only, both, and neither report states;
- cancellation before, during, and after discovery; and
- a detector implementation with no process-execution dependency, making accidental `--version` probing structurally absent.

Add equivalent smoke coverage to `Scripts/SelfTests.swift` for the domain and core detector rules that must work on Command Line Tools-only machines. Avoid tests that depend on the developer Mac's installed applications.

## Verification

After implementation, run:

```bash
make test
make build
make app
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

Manually verify at least these cases:

- one tool with a native app and separate standalone CLI;
- aliases and several retained releases;
- an app with a separately versioned bundled CLI component;
- one package-manager installation with an authoritative receipt date;
- a flat binary whose version/date stay unknown;
- leftover data with no recognized installation; and
- an installation with none of the currently catalogued storage roots.

## Acceptance criteria

- Each supported tool can report zero or more independently installed app/CLI surfaces without changing storage totals.
- App manifests, package manifests, versioned native roots, and Homebrew receipts supply versions with their evidence.
- Only a manager-recorded event is labelled installed/updated; filesystem dates are never presented as proven update times.
- Aliases, bundled components, and retained releases do not inflate the installation count.
- Coexisting installations owned by different roots remain visible even when their versions match.
- Discovery never launches a binary, package manager, shell, or network request.
- Discovery is shallow, bounded, cancellable, testable against temporary fixtures, and tolerant of unreadable or malformed metadata.
- The UI distinguishes installation presence from stored-data presence and exposes evidence without requiring technical knowledge.
- Existing disk/folder scanning and AI tool storage behavior remain unchanged and all required checks pass.

## Explicitly deferred

- remote latest-version lookup, outdated/security status, and release-channel comparison;
- automatic background refresh or filesystem watching;
- opt-in executable version probing;
- sourcing shell profiles or modeling an interactive-shell PATH;
- arbitrary whole-home searches;
- manual **Add Installation…** paths;
- exhaustive Volta, asdf, Mise, Nix, MacPorts, and development-checkout inventory;
- IDE extensions as another surface; and
- install, update, uninstall, launch, or cleanup actions.
