# SpaceLens

![macOS 14+ compatibility](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Apple Silicon arm64 architecture](https://img.shields.io/badge/architecture-Apple%20Silicon%20%28arm64%29-555555?logo=apple&logoColor=white)

SpaceLens is a native macOS app that helps you understand what is using your disk space. Scan a disk or folder, explore it as an interactive sunburst chart, and see the largest items in a ranked list.

## Highlights

- Scans internal disks, external disks, and selected folders
- Identifies the current macOS startup disk among mounted devices
- Scans every mounted local disk from one **Disc Scan** action
- Runs every storage analysis from a separate **Analysis** action
- Visualizes storage with an interactive, drill-down sunburst chart
- Shows a ranked, accessible list alongside the chart
- Finds installed app/CLI versions and analyzes local storage for Cursor, Claude Code, Codex, Google Antigravity, and OpenCode
- Inventories local models and storage used by Ollama, LM Studio, llama.cpp, Hugging Face Hub, and standalone model files
- Separates project, tool-managed, shared, and unattributed storage for Node.js & Web, Python, and Java & JVM development
- Keeps completed scans available until the app quits
- Reports protected or unreadable folders without stopping the scan
- Opens items in Finder or Terminal from the app

SpaceLens is read-only: it never deletes, moves, or modifies scanned files.

## Run SpaceLens

Requirements: macOS 14 or newer, Apple silicon, and Swift 6 from Xcode or the Xcode Command Line Tools.

```bash
make app
open dist/SpaceLens.app
```

You can also open `Package.swift` in Xcode and run the `SpaceLens` target.

## Using the app

1. Choose a mounted disk or select a folder.
2. Start the scan. You can cancel it at any time.
3. Click a folder in the chart or ranked list to open its storage map. Select an item and press Return for keyboard navigation.
4. Use the breadcrumbs or Back button to move up the hierarchy.

Use **Disc Scan** in the sidebar to scan every mounted local disk. SpaceLens scans up to two
different physical disks at once under one bounded reader budget and keeps volumes on the same
device serial. It keeps each completed result immediately and continues past an unavailable disk.
Network volumes and folders added only to the regular folder list are not included.

Use **Analysis** to run AI Coding Tools, AI Models, and Developer Storage analysis as a separate
sequential batch. It keeps every completed report and continues past an individual analysis error.
You can browse completed results while either operation continues, or cancel the current operation
from the sidebar.

Choose **AI Coding Tools** in the sidebar to identify conventional native app and CLI installations
for Cursor, Claude Code, Codex, Google Antigravity, and OpenCode and measure their known storage
locations. SpaceLens reports statically discoverable versions and evidence-backed installation
methods without launching the tools. It ranks the tools by allocated size and lists each physical
storage location once. Click anywhere on a location or folder row to expand
or collapse its contents. Known components include short descriptions and storage-category labels.
The ellipsis menu opens retained items in Finder or Terminal or inspects a directory with the
regular storage map. Use **Add Project Root** in the toolbar to include worktrees stored inside a
repository; right-click that toolbar button to remove an added root from the analysis.

AI coding tool analysis reads filesystem metadata plus app and package manifests needed to identify
installations and versions. For Claude Code, it reads only the project-path keys in `~/.claude.json`
to give encoded storage folders readable names. It does not open conversations, project files,
databases, or credentials. Results and added project roots last for the current app session.

Choose **AI Models** under **Analysis** to inventory Ollama and LM Studio model
stores, llama.cpp installations, Hugging Face Hub model caches, and validated GGUF or
SafeTensors files in Downloads, Desktop, or folders you add. The middle column ranks runtimes
and stores by allocated size. The detail pane shows detected installations, storage composition,
and individual models; switch **Models / Raw Folders** to inspect the underlying locations.

Model analysis reads filesystem metadata, Ollama manifests, small configuration files, and bounded
GGUF or SafeTensors headers. It does not launch a runtime or load model weights. Model actions can
reveal files in Finder, open their folder in Terminal, or hand a folder to the regular SpaceLens
storage map. SpaceLens remains read-only and does not provide model deletion; shared content-addressed
blobs require runtime-aware reference checks that are outside this release. While **AI Models** is
selected, use the sidebar's **Scan a Folder** button to include another standalone-model search root
for the current app session.

Choose **Developer Storage** under **Analysis** to measure Node.js and web dependencies and caches,
Python environments and tool caches, and Java/JVM build outputs, artifact repositories, and JDKs.
Standard shared locations and project artifacts below the current user's home folder are discovered
automatically. Use **Add Projects Folder** to include an external disk or another custom location.
SpaceLens associates `node_modules` with the nearest manifest- or version-control-backed project root.
An explicitly selected folder is also accepted as a project root. Dependencies inside known editor,
extension, and AI-tool locations are labeled **Tool-managed**, while markerless dependencies remain
measured under **Unattributed** instead of being promoted to projects. Configured `N_PREFIX` runtimes
and global packages are reported as shared Node storage. Successfully measured artifacts that use no
allocated storage are omitted from the ranked results; zero-byte coverage issues remain visible.
Ambiguous names such as `env`, `target`, and `build` still require ecosystem-specific evidence.
Recognized artifact contents are skipped during the discovery pass and measured separately afterward.

Developer Storage reports unique allocated bytes separately from the size referenced by each
location, which avoids double-counting hard-linked package data. It reads filesystem metadata and a
small bounded set of marker files only: it does not run package managers, read credential-bearing
configuration, modify files, or claim that measured storage is safe to delete. Added project folders
and completed reports remain available for the current app session.

The navigation sidebar uses a fixed width when visible and can be toggled from the toolbar or with
Control-Command-S. The narrower inspector remains available at every supported window size and can
be resized or toggled with Option-Command-I. SpaceLens remembers panel visibility and inspector width
between launches.

For very large folders, less significant entries are combined under **Smaller items**. Their size and item totals remain accurate.

## Full Disk Access

macOS restricts access to some folders. SpaceLens checks access before **Disc Scan** because it includes the startup disk and requires you to enable Full Disk Access in System Settings before that broad scan begins. A standalone startup-disk scan still lets you open System Settings, cancel, or explicitly continue with the access currently available. **Analysis** and folder scans selected through the macOS picker do not require this preflight.

If a locally built app asks for permission again after rebuilding, see [Development](DEVELOPMENT.md#stable-permissions-for-local-builds).

## Development

Build, test, signing, and performance-benchmark instructions are in [DEVELOPMENT.md](DEVELOPMENT.md).

```bash
make build
make test
make app
```
