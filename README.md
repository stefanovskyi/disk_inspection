# SpaceLens

![macOS 14+ compatibility](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Apple Silicon arm64 architecture](https://img.shields.io/badge/architecture-Apple%20Silicon%20%28arm64%29-555555?logo=apple&logoColor=white)

SpaceLens is a native macOS app that helps you understand what is using your disk space. Scan a disk or folder, explore it as an interactive sunburst chart, and see the largest items in a ranked list.

## Highlights

- Scans internal disks, external disks, and selected folders
- Visualizes storage with an interactive, drill-down sunburst chart
- Shows a ranked, accessible list alongside the chart
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
3. Click a chart segment or list item to explore a folder.
4. Use the breadcrumbs or Back button to move up the hierarchy.

For very large folders, less significant entries are combined under **Smaller items**. Their size and item totals remain accurate.

## Full Disk Access

macOS restricts access to some folders. SpaceLens explains how to grant Full Disk Access before scanning the startup disk; you can open System Settings, cancel, or continue with the access currently available. Folder scans selected through the macOS picker do not require broad access.

If a locally built app asks for permission again after rebuilding, see [Development](DEVELOPMENT.md#stable-permissions-for-local-builds).

## Development

Build, test, signing, and performance-benchmark instructions are in [DEVELOPMENT.md](DEVELOPMENT.md).

```bash
make build
make test
make app
```
