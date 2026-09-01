# AGENTS.md

## Project

SpaceLens is a native SwiftUI disk-inspection utility for macOS 14 and newer. It discovers mounted volumes, measures filesystem usage, and presents the results as an interactive sunburst chart and an accessible ranked list.

Keep the product name **SpaceLens**. The DaisyDisk screenshots supplied during initial development are visual references only; do not copy DaisyDisk branding, proprietary assets, or exact layouts.

## Repository Map

- `Package.swift` — Swift Package Manager manifest.
- `Sources/SpaceLens/SpaceLensApp.swift` — application entry point and menu commands.
- `Sources/SpaceLens/Models/` — filesystem, volume, scan, and chart-layout data models.
- `Sources/SpaceLens/Services/DiskScanner.swift` — asynchronous recursive filesystem scanner.
- `Sources/SpaceLens/Services/VolumeDiscovery.swift` — mounted-volume discovery.
- `Sources/SpaceLens/ViewModels/AppViewModel.swift` — application state, navigation, scanning, and macOS actions.
- `Sources/SpaceLens/Views/` — SwiftUI interface and interactive sunburst chart.
- `Sources/SpaceLens/Support/` — formatting and design tokens.
- `Tests/SpaceLensTests/` — XCTest coverage for scanner and chart layout.
- `Scripts/run_self_tests.sh` — framework-free tests for Command Line Tools installations.
- `Scripts/package_app.sh` — release build, `.app` assembly, and local ad-hoc signing.
- `Support/Info.plist.in` — app-bundle metadata template.
- `dist/SpaceLens.app` — generated app bundle; do not edit by hand.

## Required Commands

Run these from the repository root:

```bash
make build
make test
make app
```

- `make test` is the required minimum verification after changes to scanning, models, or chart layout.
- Run `make build` after all source changes.
- Run `make app` when changing app code, bundle metadata, or packaging behavior.
- Full Xcode installations may additionally run `swift test` or the XCTest target in Xcode.

Some Command Line Tools installations have a mismatched default SDK. On such machines, select a compatible SDK explicitly:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk swift build
SPACELENS_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk make test
```

Do not hard-code this compatibility override into application source code.

## Filesystem Safety

- SpaceLens is read-only. Never add deletion, moving, cleanup, or automatic file-modification behavior unless the user explicitly requests it.
- Never follow symbolic links during scanning. This prevents cycles and avoids measuring data outside the selected root.
- Stay on the selected filesystem. Main-disk scans must skip `/System/Volumes` and `/Volumes`, and directory device/inode identities must prevent APFS firmlink duplication.
- Permission errors must be collected and shown as unreadable/protected items; one inaccessible path must not abort an otherwise valid scan.
- Scans must remain cancellable and must not block the main actor.
- Run independent filesystem subtrees through a bounded concurrency limiter. Never create an unbounded task per file or directory.
- Detached scan workers must be wrapped in a cancellation handler; cancelling or replacing a scan must terminate its worker.
- Provider-backed subtrees must be isolated behind a no-progress timeout. A filesystem call that stops responding must be reported as unreadable and must not freeze the remainder of the scan.
- Use allocated file size when available, falling back to logical file size.
- Treat mounted-volume notifications as refresh signals. Do not automatically begin an expensive scan when a disk is mounted.
- Preserve the Full Disk Access explanation. macOS privacy restrictions are expected and are not application failures.
- Gate startup-disk scans on the Full Disk Access preflight. The user must be able to open the macOS privacy pane, cancel, or explicitly continue with current access; folder scans must not be gated.

## Architecture and State

- Keep filesystem traversal in `DiskScanner`, mounted-disk enumeration in `VolumeDiscovery`, and UI state in `AppViewModel`.
- Perform filesystem work in a detached background task and publish UI changes on the main actor.
- `FileNode.id` is its standardized path. Avoid random identifiers that would destabilize hover, list, or navigation state.
- Keep sunburst geometry in `SunburstLayout` separate from Canvas rendering so it remains independently testable.
- A navigation path must always start with the current scan root. Breadcrumb navigation truncates this path; drilling into a directory appends to it.
- Starting a new scan must cancel or invalidate the previous scan so stale results cannot replace newer results.
- Retain at most `DiskScanner.retainedChildLimit` direct children per directory. Preserve byte and item totals through the synthetic `Smaller items` aggregate.
- Throttle progress delivery by elapsed time. The visual spinner must animate independently of filesystem progress events.
- Show elapsed time during a scan and preserve the completed scan duration in the results header.

## UI Conventions

- Use native SwiftUI and AppKit APIs; avoid third-party dependencies unless clearly justified.
- Use SF Symbols for interface icons. Do not use emoji as icons.
- Support both light and dark appearances through `SpaceTheme`.
- The chart must provide hover feedback, click-to-drill behavior, and context actions without layout shifts.
- Color cannot be the only way to understand storage data. Maintain the ranked textual item list and accessibility labels.
- Continuous loading animation must respect `accessibilityReduceMotion` and expose a textual accessibility value.
- Every clickable icon-only control needs an accessibility label or useful help text.
- Keep Finder and Terminal actions available from both the chart/list context menus and the current-folder inspector.
- Preserve a minimum usable window size of approximately 1100 × 620 points unless adding a genuinely adaptive compact layout.

## Tests

Add or update tests when changing:

- symbolic-link handling;
- size aggregation and child sorting;
- scan progress or cancellation;
- bounded parallel traversal;
- unreadable-item behavior;
- stalled provider-directory behavior;
- sunburst proportions, depth limits, or hierarchy;
- navigation-path semantics.

If XCTest is unavailable in the active Command Line Tools installation, update the matching checks in `Scripts/SelfTests.swift` and verify with `make test`.

## Packaging

- `Scripts/package_app.sh` must remain deterministic and may only replace `dist/SpaceLens.app`.
- Keep the executable name, bundle name, and `CFBundleExecutable` synchronized as `SpaceLens`.
- Validate packaged changes with:

```bash
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

- Local builds use ad-hoc signing. Distribution outside the local machine requires a Developer ID certificate, hardened runtime, and notarization; do not claim a local build is notarized.

## Change Discipline

- Preserve unrelated user changes.
- Prefer small, focused Swift types and testable pure functions.
- Do not edit generated files in `.build/` or `dist/` manually.
- Update `README.md` when supported macOS versions, permissions, commands, or user-facing features change.
