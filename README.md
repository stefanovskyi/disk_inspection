# SpaceLens

SpaceLens is a native macOS disk inspector with an interactive sunburst chart. It discovers mounted internal and external volumes, scans folders without following symbolic links, and lets you drill into storage usage one directory at a time.

## Features

- Automatic mounted-volume and external-disk discovery
- Up-front Full Disk Access guidance before scanning the startup disk
- Asynchronous, cancellable folder and volume scanning
- Bounded parallel subtree scanning with batched `getattrlistbulk(2)` metadata reads and live elapsed time
- In-memory scan results for inspected disks and selected folders, with explicit view-or-rescan choices
- Mount-aware main-disk scans that avoid APFS aliases and external disks
- Bounded scan results that group smaller items instead of retaining millions of leaf nodes
- A no-progress watchdog that skips unresponsive provider-backed folders instead of freezing a whole scan
- Capacity-aware sunburst geometry with a transparent, labeled free-space sector
- Angular width mapped to bytes and radial reach mapped to folder depth
- Interactive sunburst with hover details and click-to-drill navigation
- Clickable breadcrumbs and keyboard back navigation
- Ranked item list with proportional size bars
- Finder and Terminal context-menu actions
- Clear reporting of protected or unreadable folders
- Native macOS dark/light appearance and accessibility labels

## Build

SpaceLens requires macOS 14 or newer and Swift 6 (included with current Xcode Command Line Tools).

```bash
make test
make app
open dist/SpaceLens.app
```

`make test` uses a framework-free verification harness so it also works on Macs that have only the Command Line Tools installed. The package additionally includes XCTest targets for Xcode.

You can also open `Package.swift` in Xcode and run the `SpaceLens` executable target.

## Permissions

macOS protects some folders. Before scanning the startup disk, SpaceLens checks whether it can read protected storage and, when needed, explains Full Disk Access before any analysis begins. Choose **Open Full Disk Access Settings**, enable SpaceLens, then return and scan again. Apple requires this permission to be granted manually in System Settings; apps cannot grant it themselves. Folder scans selected through the native picker can still be used without granting broad access.

macOS associates privacy choices with the app's code-signing identity. An ad-hoc signed development build is identified by its exact executable, so rebuilding it can cause macOS to ask again. For durable permission choices during local development, create a self-signed code-signing certificate in Keychain Access:

1. Choose **Keychain Access > Certificate Assistant > Create a Certificate**.
2. Name it `SpaceLens Local Development`, choose **Self Signed Root**, choose **Code Signing**, and enable **Let me override defaults**.
3. Accept the remaining defaults, then run `make app` again. The packaging script detects this identity automatically.

You can instead select an existing Apple Development or Developer ID identity explicitly:

```bash
SPACELENS_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make app
```

Run `security find-identity -v -p codesigning` to see available identities. The first stable-signed build is a new app identity, so grant Full Disk Access once more to that build. Future builds signed by the same identity and using the same `local.spacelens.app` bundle identifier retain the user's privacy choice. Developer ID signing and notarization are required before distributing the app to other Macs.

Some iCloud, Apple Books, and sandbox-container folders are serviced by macOS providers whose directory reads can stop responding. SpaceLens isolates these subtrees and, after five seconds without scan activity, skips the affected folder as unreadable so the rest of the disk scan can finish. The progress spinner continues independently while the filesystem is waiting.

SpaceLens never deletes or modifies scanned files.

Completed disk and folder scans remain available until SpaceLens quits. Returning home or inspecting another location does not discard them. A folder selected with **Scan a Folder** appears in the sidebar for the session, and its small × button removes the entry and cached result without touching the folder on disk. A checkmark beside a location indicates that a session result is available; selecting it offers to view the existing result immediately or rescan it.

For very large folders, SpaceLens retains the 96 largest direct items and combines the remainder into an accurate **Smaller items** entry. The combined entry preserves total byte and item counts while keeping memory usage bounded.
