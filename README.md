# SpaceLens

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)

SpaceLens is a native, read-only macOS storage inspector. It maps disks and folders, then explains the space used by developer tooling and local AI software.

[![SpaceLens showing a completed startup-disk scan as a sunburst and ranked list](docs/images/spacelens-disk-overview.png)](docs/images/spacelens-disk-overview.png)

## What it does

- Scans one folder, one disk, or every mounted local disk with cancellable, bounded parallel traversal.
- Keeps scans and analyses running while you move between pages. Two run in parallel, further requests wait in a queue, and all progress appears at the bottom of the sidebar.
- Shows live progress and rotating facts while scans and analyses run, with 50 sourced facts each for AI coding tools, AI models, developer storage, and disks. During a refresh, fold the facts page to keep working with the current results.
- Turns completed scans into a drill-down sunburst and ranked list, including free disk capacity and protected-item reporting.
- Returns to the previous folder, disk, or analysis selection with your mouse’s Back button, the toolbar Back button, or **⌘[**. Supports native Back swipes sent by mouse drivers such as Logi Options+. Navigation history works across pages while scans and analyses keep running.
- Analyzes AI coding tools: Cursor, Claude Code, Codex, Google Antigravity, OpenCode, and T3 Code.
- Identifies items at a glance with real application, document, and system-folder icons, and the logos of AI tools, model publishers, programming languages, frameworks, databases, cloud services, and developer tools. See [logo attributions](Support/BrandLogos/NOTICE.md).
- Explains well-known system, application, and tool folders in the inspector: what they hold, why they grow, and whether they are safe to delete.
- Inventories Ollama, LM Studio, llama.cpp, Hugging Face Hub caches, and standalone GGUF or SafeTensors models.
- Breaks down Node.js/Web, Python, and Java/JVM storage into projects, tool-managed data, shared stores, and unattributed items.
- Keeps completed results for the app session and opens inspected locations in Finder or Terminal.

The chart supports hover details, click-to-drill navigation, breadcrumbs, context actions, keyboard navigation, and an accessible text alternative. Symbolic links are never followed, scans stay on the selected filesystem, and inaccessible locations do not abort the rest of a scan.

## Keyboard shortcuts

Press **⌘/** or choose **Help > Keyboard Shortcuts** to see all shortcuts in a two-column reference without scrolling.

| Shortcut | Action |
| --- | --- |
| ⌘B | Show or hide the left sidebar |
| ⇧⌘B | Show or hide the inspector on the Storage Map page |
| ⌘1 | AI Coding Tools |
| ⌘2 | AI Models |
| ⌘3 | Developer Storage |
| ⌘4 | Main Drive (startup disk) |
| ⌘5 | Second Drive |
| ⌘6 | Third Drive |
| ⌘[ | Back |
| ⌘O | Scan Folder |
| ⌘R | Rescan or analyze again |
| ⌘/ | Show keyboard shortcuts |

Second and third drives follow mounted-drive order in the sidebar, after the startup disk. Shortcuts for unavailable drives are disabled. Drive shortcuts use the same saved-scan and scan-confirmation flow as clicking a drive. The inspector toggle is available when a storage map is shown. The existing **⌃⌘S** sidebar and **⌥⌘I** inspector shortcuts also work. Use **Return** to open a selected folder or activate a dialog’s default action, and **Escape** to close a dialog.

## Download a release

Download the latest disk image from [GitHub Releases](https://github.com/stefanovskyi/disk_inspection/releases/latest). Current release builds require macOS 14 or newer on Apple silicon. Open the `.dmg`, then drag **SpaceLens** onto **Applications**.

SpaceLens releases are currently ad-hoc signed and are not notarized. Before opening a download, compare its SHA-256 checksum with the value in the release notes:

```bash
shasum -a 256 ~/Downloads/SpaceLens-*.dmg
```

After moving `SpaceLens.app` to Applications, try to open it once. If macOS blocks it and you trust the downloaded file and its checksum, open **System Settings > Privacy & Security**, scroll to **Security**, click **Open Anyway**, then confirm **Open**. Apple documents this exception process in [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac).

This exception does not make the app signed or notarized. Do not disable Gatekeeper globally. Developer ID signing and notarization are tracked in [issue #1](https://github.com/stefanovskyi/disk_inspection/issues/1).

## Analysis examples

<p>
  <a href="docs/images/spacelens-ai-coding-tools.png"><img src="docs/images/spacelens-ai-coding-tools.png" width="49%" alt="Completed AI Coding Tools analysis in SpaceLens"></a>
  <a href="docs/images/spacelens-ai-models.png"><img src="docs/images/spacelens-ai-models.png" width="49%" alt="Completed AI Models analysis in SpaceLens"></a>
</p>

These are unedited captures of completed results from the earlier app build, before Holo Pulse was added. Totals naturally depend on the Mac being inspected.

## Run locally

### Holo Pulse storage map

The app uses **Holo Pulse**: translucent colored bands, luminous curved edges,
a static starfield, and a short curved hover tracer. It is the only chart style;
there is no style switcher. Animation settles after 1.2 seconds and respects
macOS Reduce Motion. Folder proportions, hierarchy, navigation, context actions,
and the ranked list retain their existing behavior.

Light appearance uses **Slate**, a muted blue-gray palette throughout the app.
Chart surfaces, the center hub, labels, and hover cards never use solid white.

For a sample-data preview of the production chart, run `make chart-preview` or
open the [interactive sample](docs/prototypes/chart-styles/index.html).
See the [preview notes](docs/prototypes/chart-styles/README.md) for reproduction.

Requirements: macOS 14 or newer and Swift 6 from Xcode or the Xcode Command Line Tools.

```bash
make app
open dist/SpaceLens.app
```

To build and open the native drag-and-drop installer:

```bash
make dmg
open dist/SpaceLens.dmg
```

SpaceLens checks for Full Disk Access before starting a scan or analysis so protected data is not silently omitted. Locally rebuilt, ad-hoc-signed apps may need permission again; [use a stable development signing identity](DEVELOPMENT.md#stable-permissions-for-local-builds) to avoid repeated prompts.

## Privacy and safety

SpaceLens never deletes, moves, or modifies scanned files. Its analyses read filesystem metadata and only the bounded manifests, configuration fields, and model headers needed for classification. They do not launch detected tools or package managers, and do not inspect source code, conversations, credentials, or model weights.

Build, test, packaging, signing, and benchmark instructions are in [DEVELOPMENT.md](DEVELOPMENT.md). Repository architecture and safety constraints are in [AGENTS.md](AGENTS.md).
