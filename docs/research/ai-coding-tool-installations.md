# AI coding tool installations on macOS

Verified: 2026-09-10
Scope: installation discovery for Cursor, Claude Code, Codex, Google Antigravity, and OpenCode

## Conclusion

SpaceLens can add useful installation information without launching any coding tool. The first version can reliably discover most conventional macOS application bundles, official standalone CLI layouts, Homebrew formula/cask installs, and global JavaScript-package installs. It can usually report a version and installation method, and it can preserve several coexisting installs of one tool.

The important limitation is time. A Homebrew receipt provides a real local install/upgrade event time, but a normal application bundle, native binary, or npm package has no universal “last updated” field. File creation and modification dates are evidence about the local files, not proof of when the product was installed or upgraded. SpaceLens should therefore attach a source and confidence to every date and display “Observed file date” rather than “Updated” when only filesystem timestamps are available.

Installation discovery also needs its own model. Storage locations, application bundles, CLI installations, command aliases, embedded CLIs, and retained old releases are different concepts:

- One installation can expose several command names.
- An application can contain a CLI entry point without that CLI being separately installed.
- A self-updating CLI can keep several release directories while only one is active.
- A tool can genuinely be installed several times by different managers or by different Node runtimes.

Counting every path as an installation would therefore produce misleading duplicates.

## Proposed vocabulary

| Concept | Meaning | Example |
| --- | --- | --- |
| Tool | Product family already represented by `AICodingToolID` | Codex |
| Installation | One independently installed and updated product surface | npm-managed Codex CLI under one NVM Node version |
| Surface | User-facing form of that installation | Native app, IDE app, or CLI |
| Entry point | A path or alias used to start an installation | `agent` and `cursor-agent` symlinks |
| Component | A separately versioned executable bundled by an installation | Codex CLI embedded in the ChatGPT desktop app |
| Retained release | An inactive version kept by one self-updating installation | An older file under `~/.local/share/claude/versions` |
| Install method | Manager or delivery channel supported by evidence | Homebrew cask, npm, native installer, disk image/manual |
| Evidence | The local artifact supporting a field | `Info.plist`, `package.json`, Homebrew receipt, symlink target |

An installation should be deduplicated by its owning root or bundle, not merely by tool ID, command name, or version. Entry points that resolve into the same owning root belong to the same installation. Different app bundle paths remain separate installations even when their bundle IDs and versions match.

## What can be discovered

### Native macOS applications

Search `/Applications`, `~/Applications`, and the immediate application bundles in those roots. A user can keep an app elsewhere, so a future **Add Installation…** action is the only complete answer for arbitrary paths. Launch Services and Spotlight may be used as supplementary discovery sources, but neither should be required for correctness.

For each `.app`, read only `Contents/Info.plist` and shallow filesystem/code-signing metadata:

| Field | Source | Reliability |
| --- | --- | --- |
| Product identity | `CFBundleIdentifier`, catalogued bundle IDs | High when bundle ID matches |
| Display name | `CFBundleDisplayName` or `CFBundleName` | High |
| App version | `CFBundleShortVersionString` | High when present |
| App build | `CFBundleVersion` | High when present |
| Publisher | static-code signing information / TeamIdentifier | High for a valid signed bundle; optional for unsigned builds |
| App path | enumerated bundle URL | High |
| Install method | matching Homebrew cask receipt or App Store receipt marker; otherwise manual/unknown | High with a receipt, otherwise intentionally unknown |
| Installed/updated time | Homebrew receipt time when present | High for the latest Homebrew install/upgrade event |
| Observed file date | bundle or `Info.plist` creation/modification time | Low; copies, archives, restores, and vendor packaging can preserve or replace it |

Apple defines `CFBundleShortVersionString` as the bundle's release/version number and `CFBundleVersion` as its build iteration. These are the correct app-version sources. [Apple bundle version documentation](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleShortVersionString), [Apple distribution identity documentation](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution).

Do not use a code-signing timestamp as a local installation date. It describes signing of the delivered artifact. Do not use the modification date of application data as an app-update date; it changes during ordinary use.

### Homebrew formulae and casks

Inspect the two conventional macOS prefixes, `/opt/homebrew` and `/usr/local`, plus any already-known prefix associated with an entry point. Do not invoke `brew`: even read-looking package-manager commands can initialize state, auto-update, or be unavailable to a Finder-launched app.

Homebrew stores an `INSTALL_RECEIPT.json` for installed formulae and casks. Current Homebrew source creates this receipt with `time: Time.now.to_i`, as well as manager version, architecture, source tap, and other provenance. Parsing that local receipt gives SpaceLens its strongest install/update date. [Homebrew receipt implementation](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/tab.rb#L624-L767).

Expected roots are:

- Formula: `<prefix>/Cellar/<formula>/<version>/INSTALL_RECEIPT.json`
- Cask: `<prefix>/Caskroom/<token>/.metadata/INSTALL_RECEIPT.json`

The receipt's `time` represents the Homebrew event that wrote the current receipt. The UI should say **Homebrew installed/updated** because the receipt alone does not distinguish a first install from a later upgrade. Formula version directories and cask receipt source data provide the installed version. A cask receipt can then be correlated with a matching application bundle; the bundle and receipt describe one installation, not two.

### Global JavaScript-package installations

OpenCode officially supports npm, Bun, pnpm, and Yarn. Claude Code and Codex have also shipped through npm, and multiple Node installations can retain several independent global copies. [OpenCode installation documentation](https://opencode.ai/docs/), [Claude Code installation troubleshooting](https://code.claude.com/docs/en/troubleshoot-install), [Codex repository installation documentation](https://github.com/openai/codex#installing-and-running-codex-cli).

For npm-compatible installations, a matching package manifest is the authoritative local version source:

- `@anthropic-ai/claude-code/package.json`
- `@openai/codex/package.json`
- `opencode-ai/package.json`

npm documents global packages under `{prefix}/lib/node_modules` on Unix and their executable links under `{prefix}/bin`. [npm folder layout](https://docs.npmjs.com/files/folders/). Bun defaults global packages to `~/.bun/install/global` and executable links to `~/.bun/bin`, with both locations configurable. [Bun global-install configuration](https://bun.sh/docs/pm/cli/add#global). Yarn Classic defaults its global package directory to `~/.config/yarn/global` and allows a configurable binary prefix. [Yarn global directory documentation](https://classic.yarnpkg.com/lang/en/docs/cli/global/).

Discovery should cover conventional roots and bounded, known runtime-manager layouts such as NVM Node versions. It must not recursively search the whole home directory for `node_modules`. A package path or manager record can establish npm/Bun/pnpm/Yarn as the install method; a bare command symlink cannot always do so.

Version managers complicate “active” status:

- NVM, `n`, asdf, and similar layouts may hold one global package installation per Node version.
- Volta uses smart shims that choose tools according to the working directory, so a shim is not a direct pointer to one executable. [Volta toolchain behavior](https://docs.volta.sh/guide/understanding).
- Mise supports both direct GitHub release assets and npm-backed tools, including global configuration. [Mise backends](https://mise.jdx.dev/dev-tools/backends/).

These copies should all remain visible. “On SpaceLens PATH” is only a weak hint from `ProcessInfo.processInfo.environment`: a Finder-launched app does not necessarily inherit the user's interactive shell PATH, and sourcing a login shell would execute user scripts. SpaceLens should not source shell profiles or run a login shell for discovery.

### Official standalone/native CLI installers

The five tools use several distinct layouts that can be recognized directly.

| Tool | Official/conventional layout | Version available without executing? | Notes |
| --- | --- | --- | --- |
| Cursor Agent | `~/.local/bin/agent` and `~/.local/bin/cursor-agent` point into `~/.local/share/cursor-agent/versions/<release>/` | Yes, from active symlink target/release directory | Two aliases are one install; inactive release directories are retained releases. The current official installer shows this exact versioned layout. [Cursor CLI installer](https://cursor.com/install) |
| Claude Code | `~/.local/bin/claude` and `~/.local/share/claude/versions/<semver>` | Yes, from active symlink target filename | `~/.claude/local` is a legacy local npm install; Homebrew and npm copies can coexist. [Claude setup](https://code.claude.com/docs/en/quickstart), [conflicting-install guidance](https://code.claude.com/docs/en/troubleshoot-install#check-for-conflicting-installations) |
| Codex | Default entry point `~/.local/bin/codex`; managed files below `$CODEX_HOME/packages/standalone/{current,releases}` | Usually, from the release-directory name or packaged manifest; otherwise unknown | `CODEX_HOME` and `CODEX_INSTALL_DIR` can move roots. The installer explicitly detects and warns about npm/Bun/Homebrew conflicts. [Codex installer source](https://github.com/openai/codex/blob/main/scripts/install/install.sh) |
| Antigravity CLI | `~/.local/bin/agy` | Not reliably from static metadata in the flat-binary layout | The CLI is `agy`, not merely `antigravity`. It self-updates and maintains updater state below `~/.gemini/antigravity-cli`, but a last-check marker is not an update time. [Antigravity CLI installation](https://antigravity.google/docs/cli-install?platform=mac), [Antigravity updater troubleshooting](https://antigravity.google/docs/cli-troubleshooting) |
| OpenCode | Installer chooses `OPENCODE_INSTALL_DIR`, `XDG_BIN_DIR`, `~/bin`, then `~/.opencode/bin` | No guaranteed adjacent manifest for a single copied binary; package-managed installs have manifests/receipts | Also supports npm/Bun/pnpm/Yarn, two Homebrew formula sources, Mise, release binaries, and a desktop cask. [OpenCode repository installation documentation](https://github.com/anomalyco/opencode#installation) |

Resolving a symlink chain for identification is not a recursive filesystem scan. It should still be bounded, detect loops, and stop at a small hop limit. SpaceLens must not traverse a symlinked storage root; this installation-specific operation only reads the link and shallow target metadata.

### CLI version execution is not suitable for the default path

`tool --version` appears attractive because every vendor can format its own version. The local probe found that it is not reliably side-effect-free:

- Cursor's app-bundled command initialized Electron far enough to emit a process/code-signing error.
- Codex printed a warning that it had attempted to create PATH aliases.

Other CLIs can check for updates, initialize caches, read configuration, touch the keychain, or interpret environment-specific wrappers before printing a version. SpaceLens is explicitly read-only, so the first implementation should never launch discovered programs. If an opt-in execution probe is ever added, it needs a clear user action, a short timeout, a restricted environment, captured output limits, and the same cancellation guarantees as scanning. It still should not run an unsigned or unidentified executable.

## Tool surfaces and install channels

The following table describes what the catalog should recognize. “Manual” means a downloaded/copied application or binary without manager evidence, not a claim about precisely how the user obtained it.

| Tool | Native application surfaces | CLI surfaces | Known installation channels relevant to macOS |
| --- | --- | --- | --- |
| Cursor | Cursor editor app | App-bundled `cursor` editor command; independent Cursor Agent (`agent`/`cursor-agent`) | App disk image/manual; possible Homebrew cask evidence; official Cursor Agent curl installer |
| Claude Code | Claude desktop app's Code feature | `claude` | Claude desktop download; native CLI installer; Homebrew `claude-code` or `claude-code@latest`; npm/legacy local npm |
| Codex | ChatGPT desktop app with Codex | App-bundled Codex component; standalone `codex` | Desktop app download; standalone installer; npm `@openai/codex`; Homebrew cask `codex`; Bun-compatible global install evidence |
| Google Antigravity | Antigravity 2.0 app; legacy/separate Antigravity IDE app | `agy` | Native app downloads; native CLI installer/self-updater |
| OpenCode | OpenCode desktop app | `opencode` | Desktop download or `opencode-desktop` cask; curl installer; npm/Bun/pnpm/Yarn; `anomalyco/tap/opencode` or Homebrew core formula; Mise; direct release binary |

Cursor documents a native `.dmg` app and a separately installed Cursor Agent CLI. [Cursor app quickstart](https://docs.cursor.com/en/get-started/quickstart), [Cursor CLI installation](https://docs.cursor.com/en/cli/installation). Claude explicitly states that the desktop app includes Code but the terminal CLI is a separate install. [Claude desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart). Codex officially documents standalone, npm, and Homebrew CLI installation, while the desktop app is a separate surface. [Codex CLI](https://learn.chatgpt.com/docs/codex/cli), [Codex repository](https://github.com/openai/codex). Antigravity's download page separately lists Antigravity 2.0, Antigravity CLI, and Antigravity IDE. [Antigravity downloads](https://antigravity.google/download). OpenCode separately distributes terminal and desktop clients. [OpenCode downloads](https://opencode.ai/download).

Do not treat helper applications as full product installations solely because their names contain a tool name. For example, a Claude Code URL-handler bundle can be an auxiliary component of the CLI installation.

## Version and date evidence model

A plain `version: String?` and `updatedAt: Date?` are insufficient because the UI must explain why it believes each value.

Recommended evidence ordering:

| Priority | Value | Source | Suggested UI wording |
| ---: | --- | --- | --- |
| 1 | App release/build | App `Info.plist` | `Version 3.19.19` |
| 1 | Package version | `package.json` matched by exact package name | `Version 1.18.29` |
| 1 | Managed release version | Active versioned native-install target | `Version 2.1.223` |
| 1 | Formula/cask version | Homebrew receipt/version root | `Version …` |
| 1 | Local manager event time | Homebrew receipt `time` | `Homebrew installed/updated …` |
| 2 | Current-target selection time | Creation/change time of an atomically replaced symlink | `Current version selected around …` |
| 3 | Package/release file time | Creation/modification time of manifest or active release root | `Version files dated …` |
| 4 | App/binary file time | Creation/modification time only | Hide by default or label `Observed file date …` |

The model should preserve both the value and evidence:

```swift
struct InstallationFact<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let source: InstallationEvidenceSource
    let confidence: InstallationEvidenceConfidence
}
```

Suggested confidence values are `authoritative`, `strong`, and `heuristic`. “Unknown” is absence of a fact, not a fake confidence level. Never substitute any of these for the latest modification date of the tool's user data.

## Local read-only probe

The probe examined application manifests, link targets, package manifests, Homebrew/pkg receipts, file timestamps, and static code signatures on one development Mac. It did not open conversations, databases, source projects, or credentials. It is validation of the detection strategy, not a user population sample.

| Tool | Installations/components observed | Version evidence | Method/date evidence |
| --- | --- | --- | --- |
| Cursor | `/Applications/Cursor.app`; `/usr/local/bin/cursor` points into that app; independent Cursor Agent with both `agent` and `cursor-agent` aliases | App `3.19.19`; active Agent target `2026.02.13-41ac335` | Three Agent release directories existed, but one pair of aliases selected one active install. No Homebrew receipt matched. |
| Claude Code | `/Applications/Claude.app`; native `~/.local/bin/claude`; Claude Code URL-handler helper | App `1.49585.0`; native active target `2.1.223` | Three native release binaries existed; the symlink selected one. Native CLI and desktop app are distinct installations. |
| Codex | `/Applications/ChatGPT.app` with bundle ID `com.openai.codex` and embedded `codex` | App `26.901.51231` build `8109`; executing the bundled component reported CLI `0.153.4`, demonstrating independent component versioning | No separate Homebrew, npm, or standalone receipt was found. The host process PATH exposed the embedded CLI, which another GUI app cannot assume. |
| Antigravity | `/Applications/Antigravity.app`; `/Applications/Antigravity IDE.app`; native `~/.local/bin/agy` | Apps `2.12.2` and `2.5.5`; static metadata did not expose a trustworthy CLI product version | App and CLI signatures shared the same observed Google TeamIdentifier. The flat CLI binary's dates were only heuristic update evidence. |
| OpenCode | No desktop app; global npm package in one NVM Node version with an `opencode` symlink | `opencode-ai/package.json` reported `1.18.29` | Package layout strongly identified a Node-global install; package-file dates are heuristic. No Homebrew receipt matched. |

Additional probe results:

- Direct enumeration found application bundles while both Launch Services lookup and Spotlight lookup returned no matching locations in the probe's execution context. Those services are useful supplements, not reliable primary discovery.
- There were no relevant macOS Installer (`pkgutil`) receipts. Receipt lookup remains a cheap optional detector for future vendor packages.
- Homebrew receipts from unrelated installed packages confirmed the current on-disk schema and `time` field used by the upstream Homebrew implementation.
- One Cursor app bundle directory carried a preserved 1979 timestamp while its `Info.plist` had a 2026 timestamp. This is direct evidence that bundle filesystem dates cannot be called installation or update dates.
- The app-bundled Codex CLI version differed from the desktop app version. A single installation may therefore need component-level versions.

The code-signing TeamIdentifiers observed locally are useful fixtures, not permanent API contracts. Publisher identity can strengthen a match, but a vendor can rotate signing credentials and open-source/manual builds may be unsigned. The built-in catalog should record when a signing identity was last verified and treat a mismatch as “unverified,” not automatically hide the installation.

## Recommended first implementation boundary

Include:

1. Standard application roots, bundle-ID matching, app release/build, and optional signature identity.
2. Homebrew formula/cask receipts under Apple Silicon and Intel prefixes.
3. The five tools' documented standalone/native layouts, including active link and retained-release relationships.
4. Exact known npm package names under conventional npm, NVM, Bun, pnpm, and Yarn global roots, with package-manifest versions.
5. Entry-point discovery from the current process PATH and conventional binary roots, used as evidence rather than as the complete inventory.
6. Deduplication into installations, components, aliases, and retained releases.
7. Evidence-labelled dates, with an absent date preferred over a misleading one.

Defer:

- Launching any discovered binary, including `--version`.
- Sourcing `.zshrc`, `.zprofile`, `.bashrc`, or other user scripts.
- Recursively searching the home directory for apps, packages, or project-local CLIs.
- Reading conversation/configuration databases or credentials.
- Remote “latest version” checks and outdated-version claims; those need networking, release-channel semantics, and separate freshness policy.
- Exact attribution for arbitrary custom installer directories that leave no manager record.
- Full asdf/Mise/Volta/Nix inventory parsing in the first iteration; expose coverage notes and add fixture-backed adapters later.
- Treating IDE extensions as native/CLI installations. They can become another surface in a later catalog expansion.

## Implementation implications for SpaceLens

Installation detection is shallow metadata inspection, not disk-size traversal. Add it beside `AICodingToolsAnalyzer` rather than to `DiskScanner`:

```text
AICodingToolsAnalyzer
├── DiskScanner                     storage locations and allocated bytes
└── AICodingInstallationsDetector   bundles, receipts, manifests, links, signatures
```

`AICodingToolReport` should receive an `installations` collection independent of `locations`. A tool may have installations but no data, or leftover data but no current installation. The view should preserve both states instead of using storage presence as the installation signal.

The detector should accept an injectable request and filesystem interface so tests can model `/Applications`, Homebrew prefixes, user homes, and PATH entries entirely inside temporary directories. It should run off the main actor, stay cancellable, bound every enumeration, avoid following directory symlinks, and impose small file-size limits before parsing plists or JSON.

The privacy text must be updated carefully. Reading app/package manifests and manager receipts is more than file-size metadata, even though it does not inspect user content. A truthful description is: **SpaceLens reads filesystem metadata plus app and package manifests needed to identify installations and versions. It does not open conversations, project files, databases, or credentials.**

## Questions to settle in planning

1. Should the first UI show heuristic dates, or only authoritative manager dates?
2. Should retained inactive CLI releases be listed inline under the active installation or summarized as “2 older releases”?
3. Should app-bundled CLI component versions remain unknown when no static manifest exists, or should SpaceLens later offer an explicit **Probe Version** action?
4. Is **Add Installation…** needed in the first release for apps/binaries outside conventional roots?
5. Should signature identity be visible to users or retained only as matching/debug evidence?
6. Should installation information refresh as part of **Analyze Tool Storage**, or through a separate cheap refresh that can run without a storage scan?
