# Developer Storage analysis — proposed implementation plan

Status: implemented
Prepared: 2026-09-11

## Naming decision

Use **Developer Storage** for the sidebar and feature name.

“Development tools” is too narrow: `node_modules`, Python virtual environments, Maven artifacts,
and build outputs are not tools. “Programming languages” is also misleading because the requested
data includes package-manager stores, framework caches, and JDK installations. **Developer Storage**
is broad enough for all of these while remaining understandable beside **AI Coding Tools** and
**AI Models**.

Use these domain terms consistently:

- **Developer storage** — disk allocation created or installed by software-development workflows.
- **Ecosystem** — one supported family: **Node.js & Web**, **Python**, or **Java & JVM**.
- **Project container** — a folder explicitly added by the user; it may be one project or contain
  many projects.
- **Project root** — a directory recognized from ecosystem-specific marker files.
- **Project artifact** — a recognized generated directory inside a project root.
- **Shared location** — a per-user or system-wide store, cache, environment collection, or toolchain
  outside a project. Use “Shared,” not “Global,” in user-facing copy because most of these locations
  are per-user rather than system-global.
- **Artifact kind** — the mutually exclusive storage role assigned to measured bytes.

The proposed artifact kinds are:

| Kind | Examples |
| --- | --- |
| Project dependencies | `node_modules` |
| Environments | Python virtual environments, Conda environments |
| Build outputs | Next.js `.next` output, Maven `target`, Gradle `build` |
| Project caches | `.next/cache`, `.turbo/cache`, Vite, pytest, Gradle `.gradle` |
| Shared caches & stores | npm, Yarn, pnpm, Bun, pip, Poetry, uv, Maven, Gradle |
| Toolchains & runtimes | Node versions, Python versions, JDKs |
| Tool state & diagnostics | Gradle daemon state and logs |
| Other | Unclassified bytes inside a narrowly owned recognized root |

Scope (`project` or `shared`) and artifact kind are separate dimensions. This avoids calling a
Poetry environment a cache merely because its default location is below Poetry's cache directory.

## Probe findings

### Existing SpaceLens architecture

- The sidebar already has an **Analysis** section with independent **AI Coding Tools** and
  **AI Models** screens.
- Each analysis feature is a vertical slice below `Sources/SpaceLens/Features`, with domain,
  analysis, state, and views kept together.
- `AppSection`, `AppViewModel`, `AppRootView`, `VolumeSidebar`, and `ScanCoordinator.Activity` are
  the five integration points for another analysis screen.
- `DiskScanner` already supplies the important safety and accounting behavior: allocated file size,
  device/inode identity, no symlink traversal, same-filesystem traversal, bounded concurrency,
  cancellation, unreadable-item reporting, provider timeouts, and compact retained trees.
- `DiskScanner` already has a per-item observation seam through `ScannedFileItem`, including URL,
  file kind, allocated size, identity, readability, and modification time. The analyzer can therefore
  produce exact category totals before `Smaller items` compaction.
- `ScanCoordinator` permits only one intensive scan or analysis at a time. Developer Storage should
  join this coordination rather than run concurrently with a disk, AI-tool, or AI-model scan.
- The two existing analysis stores implement the same useful state semantics: idle, running with a
  previous report, completed, failed with a previous report, cancellation, stale-result IDs, and
  session-only added roots.
- The repository itself is a Swift package and contains none of the proposed Node, Python, Maven,
  or Gradle project-artifact directories. Tests therefore need synthetic mixed-ecosystem fixtures.

### Local read-only storage probe

A metadata-only `du` probe of documented roots on the development Mac found approximately:

| Existing root | Allocated size |
| --- | ---: |
| npm cache (`~/.npm`) | 10.0 GiB |
| pnpm store (`~/Library/pnpm`) | 2.9 GiB |
| pip cache (`~/Library/Caches/pip`) | 1.7 GiB |
| Bun install data (`~/.bun/install`) | 1.3 GiB |
| SDKMAN JDKs (`~/.sdkman/candidates/java`) | 1.3 GiB |
| Gradle user home (`~/.gradle`) | 1.1 GiB |
| NVM Node versions (`~/.nvm/versions`) | 849 MiB |
| Yarn data (`~/.yarn`) | 611 MiB |
| Maven user data (`~/.m2`) | 498 MiB |
| uv persistent data (`~/.local/share/uv`) | 393 MiB |

The active commands resolve into NVM, Bun, a framework Python install, SDKMAN Maven, and Homebrew
OpenJDK locations. This validates the three-ecosystem rollout and shows why the report must separate
shared package data from installed runtimes.

The current baseline is clean. `make build` completes and `make test` passes all 33 self-tests plus
signing-identity and benchmark-comparison checks.

## Goal

Add an on-demand, read-only **Developer Storage** section that answers:

1. How much storage is associated with each supported ecosystem?
2. How much belongs to projects, tool-managed installations, shared machine locations, or artifacts
   whose owner cannot be verified?
3. Which recognized artifact kinds and physical folders account for that storage?
4. Was any expected location unreadable, linked, timed out, or omitted by a discovery safety limit?

The first release is strictly limited to Node.js & Web, Python, and Java & JVM.

## Product behavior

Add **Developer Storage** as the third row under **Analysis**, using an SF Symbol such as
`hammer.fill`. Selecting it must not start filesystem work. The empty screen explains:

- standard shared locations and project artifacts below the user's home directory are discovered
  automatically when the user presses **Analyze**;
- **Add Projects Folder** extends discovery to external or explicitly chosen custom locations;
- analysis reads filesystem metadata and a very small set of bounded marker files;
- SpaceLens does not delete files or claim that measured bytes are reclaimable.

The user may add either a single repository or a parent folder containing many repositories.
Project containers remain in memory for the app session and can be removed from the toolbar's
context menu. Existing folders in the storage sidebar are not silently included: they may be
unrelated or privacy-sensitive and were selected for a different purpose.

During analysis, show the current ecosystem/location, discovered artifact count, scanned item count,
mapped bytes, elapsed time, and cancel action. A rerun keeps the prior report visible until the new
report completes, matching the other Analysis screens.

The completed screen should use the established two-pane Analysis layout:

- **Left pane:** the three ecosystems ranked by unique measured size, with Project, Tool-managed,
  Shared, and Unattributed subtotals, item count, and coverage state.
- **Right pane:** selected ecosystem summary; an ownership filter; storage-composition pills; project
  groups; tool-managed, shared, and unattributed groups; and expandable physical locations.
- **Location actions:** Show in Finder, Open in Terminal, and Inspect Storage Map. The last action
  hands a directory to the existing normal scan flow and retains the Developer Storage report.

Use path-based IDs and preserve selection across reruns when the ecosystem still exists. The ranked
text representation remains authoritative; color only reinforces the hierarchy.

## Initial recognition catalog

The catalog is built into the app and versioned with SpaceLens. Environment overrides are accepted
only when they are absolute paths. Documented defaults remain additive so stale storage is not hidden
when a user has moved a current store.

### Node.js & Web

Project roots are indicated by `package.json` or a supported lock/workspace file. Exact generated
directory names are still validated against a nearby project marker so an unrelated directory named
`build` or `env` is not attributed accidentally.

| Scope | Recognized location | Primary kind | Notes |
| --- | --- | --- | --- |
| Project | `node_modules` | Project dependencies | Collapse nested copies below an already recognized dependency root. |
| Project | `.yarn/cache` | Project caches | Supports zero-install/project-local Yarn cache layouts. |
| Project | `.next` | Build outputs | Classify `.next/cache` more specifically as Project caches. |
| Project | `.turbo` | Project caches | Prefer `.turbo/cache`; retain other narrowly owned Turbo data as Other. |
| Project | `node_modules/.vite` | Project caches | Count through the containing `node_modules` scan when both exist. |
| Project | `node_modules/.cache/turbo` | Project caches | Legacy/default Turbo layout; classify without a second scan. |
| Project | `.pnpm-store` or `node_modules/.pnpm-store` | Shared caches & stores | Covers a per-project fallback store. |
| Shared | `NPM_CONFIG_CACHE` and `~/.npm` | Shared caches & stores | Split `_cacache`, `_npx`, logs, and Other by path only. |
| Shared | Yarn Berry and Classic roots | Shared caches & stores | Include `~/.yarn/berry/cache`, `~/Library/Caches/Yarn`, and existing legacy candidates. |
| Shared | pnpm store | Shared caches & stores | Resolve `PNPM_HOME`, `XDG_DATA_HOME`, then `~/Library/pnpm/store`; account for one store per filesystem. |
| Shared | `BUN_INSTALL_CACHE_DIR` and `~/.bun/install/cache` | Shared caches & stores | Keep global installed packages separate from the download cache. |
| Shared | NVM, fnm, Volta, asdf, and mise install roots | Toolchains & runtimes | Measure installed Node version directories, not shell shims. |

Configuration files such as `.npmrc` and `.yarnrc.yml` may contain registry credentials. The first
release must not parse them to discover custom paths. A missing non-default path is a disclosed
coverage limitation, not zero usage.

### Python

| Scope | Recognized location | Primary kind | Notes |
| --- | --- | --- | --- |
| Project | `.venv`, `venv`, or `env` | Environments | Require `pyvenv.cfg` plus a POSIX Python/bin layout; the folder name alone is insufficient. |
| Project | linked `.venv` | Environments | Report as linked and do not follow; account for the physical target only if a shared uv/manager root is independently recognized. |
| Project | `.tox` and `.nox` | Environments | Treat as containers of generated test environments. |
| Project | `__pycache__` | Project caches | Exact directory-name match; no Python source contents need to be read. |
| Project | `.pytest_cache` | Project caches | Require the conventional cache marker when present; tolerate older valid layouts. |
| Project | `.mypy_cache` and `.ruff_cache` | Project caches | Generated analysis-tool caches, still within the Python ecosystem. |
| Shared | pip cache | Shared caches & stores | Resolve `XDG_CACHE_HOME`; include current macOS default `~/Library/Caches/pip`. |
| Shared | Conda `pkgs` roots | Shared caches & stores | Discover conventional Miniconda, Anaconda, and Miniforge roots without parsing `.condarc`. |
| Shared | Conda `envs` roots and bounded `~/.conda/environments.txt` paths | Environments | Validate containment and environment markers before scanning. |
| Shared | `PYENV_ROOT/versions` and `~/.pyenv/versions` | Toolchains & runtimes | Directory names provide display versions; do not launch Python. |
| Shared | Poetry cache and `virtualenvs` roots | Shared caches & stores / Environments | Resolve environment overrides and classify `virtualenvs` separately. |
| Shared | uv cache | Shared caches & stores | Include `UV_CACHE_DIR`, XDG default, and existing legacy macOS cache candidates. |
| Shared | uv `python` and `tools` data roots | Toolchains & runtimes / Environments | Resolve `XDG_DATA_HOME`, `UV_PYTHON_INSTALL_DIR`, and `UV_TOOL_DIR`. |

`pyproject.toml`, `requirements.txt`, `setup.py`, and `setup.cfg` are presence markers only in this
release. Do not parse dependency declarations or execute an environment's Python/pip command.

### Java & JVM

| Scope | Recognized location | Primary kind | Notes |
| --- | --- | --- | --- |
| Project | Maven `target` | Build outputs | Require a sibling `pom.xml`; support multiple modules independently. |
| Project | Gradle `build` | Build outputs | Require a sibling Gradle build file or a recognized Gradle project relationship. |
| Project | Gradle `.gradle` | Project caches | This is project-specific cache/metadata, not daemon data. |
| Shared | `~/.m2/repository` | Shared caches & stores | Maven's local repository mixes downloaded and locally installed artifacts; do not claim all bytes are disposable. |
| Shared | `~/.m2/wrapper/dists` | Toolchains & runtimes | Maven Wrapper distributions. |
| Shared | `$GRADLE_USER_HOME/caches` | Shared caches & stores | Default user home is `~/.gradle`. |
| Shared | `$GRADLE_USER_HOME/wrapper/dists` | Toolchains & runtimes | Downloaded Gradle distributions. |
| Shared | `$GRADLE_USER_HOME/daemon` | Tool state & diagnostics | Gradle daemon registry and logs are global user-home state, not project-local data. |
| Shared | `$GRADLE_USER_HOME/jdks` | Toolchains & runtimes | JDKs downloaded by Gradle toolchain support. |
| Shared | macOS JDK bundle roots | Toolchains & runtimes | `~/Library/Java/JavaVirtualMachines` and `/Library/Java/JavaVirtualMachines`. |
| Shared | SDKMAN, Homebrew, asdf, and mise Java roots | Toolchains & runtimes | Collapse symlink aliases such as `current` onto their already measured physical version. |

Do not parse Maven `settings.xml`, Gradle properties, or shell startup files. Those files can contain
credentials and executable configuration. Custom repository paths that are visible only through
those sources are explicitly deferred.

## Architecture

### Deep analyzer module

Add `Sources/SpaceLens/Features/DeveloperStorage/` with `Domain`, `Catalogs`, `Analysis`, `State`, and
`Views` folders, matching the established feature-slice structure.

The external seam is one deep module:

```swift
protocol DeveloperStorageAnalyzing: Sendable {
    func analyze(
        request: DeveloperStorageRequest,
        onProgress: @escaping @Sendable (DeveloperStorageProgress) -> Void
    ) async throws -> DeveloperStorageReport
}
```

Callers know the request, progress, report, and cancellation behavior. The implementation owns all
path knowledge, project-marker validation, discovery budgets, overlap removal, scan ordering,
physical de-duplication, category attribution, and coverage reporting. `AppViewModel` and SwiftUI
must never contain ecosystem paths or matching rules.

Suggested domain types:

- `DeveloperEcosystemID`: Node.js & Web, Python, Java & JVM.
- `DeveloperStorageScope`: project, tool-managed, shared, or unattributed.
- `DeveloperStorageEvidence`: the marker, selection, managed path, or artifact evidence behind the
  ownership classification.
- `DeveloperArtifactKind`: the common kinds defined above.
- `DeveloperArtifactDescriptor`: ecosystem, scope, kind, standardized URL, display label, containing
  project when applicable, source/evidence, path-specific subcategory rules, and symlink boundary.
- `DeveloperStorageLocation`: unique and referenced allocated bytes, item count, latest modification,
  status, coverage notes, and optional retained `FileNode`.
- `DeveloperProjectReport`: recognized project root and its disjoint locations.
- `DeveloperEcosystemReport`: ownership totals, project reports, non-project locations, and categories.
- `DeveloperStorageReport`: ranked ecosystems, unique total, referenced total, dates, duration, items,
  and coverage issues.

Use declarative ecosystem definitions and pure validation functions. Do not introduce public
protocols for each ecosystem unless a second implementation actually varies; the analyzer interface
is the important seam.

### Project-artifact discovery

Do not recursively measure every source file in a broad projects folder and do not create a second
filesystem walker inside the feature.

Add a narrow internal discovery operation to `DiskScanner` that:

1. Traverses explicitly authorized project containers with the scanner's existing bounded
   concurrency, device/inode checks, cancellation, and provider isolation.
2. Looks only for a catalog-supplied set of candidate directory and project-marker names.
3. Prunes `.git`, `.hg`, `.svn`, symbolic links, and a recognized artifact directory as soon as it is
   recorded, so discovery never walks millions of dependency files.
4. Returns candidate directories plus enough sibling/ancestor marker evidence for pure catalog
   validation.
5. Enforces a directory/depth/time safety budget and reports truncated coverage rather than silently
   treating undiscovered space as empty.

After discovery, scan only validated artifact roots and known shared roots with the existing
`DiskScanner.scan` observation interface. Scan non-overlapping physical roots sequentially; each root
still uses bounded internal parallelism. This avoids multiplying concurrency by the number of roots.

### Path normalization and overlap

For every candidate:

1. Standardize the path without resolving symlinks.
2. Reject containment escapes and non-absolute environment paths.
3. Preflight missing, non-directory, unreadable, and linked roots into report statuses.
4. Collapse identical descriptors.
5. Scan an ancestor once when it contains another descriptor; apply the most-specific descriptor rule
   to nested bytes and retain nested roots as priority paths when a filesystem outline is needed.
6. Never follow symbolic links, including version-manager `current` aliases. Record the alias as a
   reference while measuring the real version through its canonical directory entry.

### Accounting semantics

Use allocated size. Never label a measured total as “reclaimable” or promise savings.

Maintain two values:

- **Referenced size** — allocation observed below a displayed location. This is useful for answering
  how large a project's `node_modules` appears.
- **Unique measured size** — files counted once across the complete Developer Storage report by
  device/inode, with standardized path fallback when identity is unavailable.

The header and ecosystem ranking use unique measured size. Location rows show referenced size and a
“shared elsewhere” annotation when identity de-duplication removes bytes from the unique total.
Process shared stores before project references so deterministic primary attribution favors the
manager-owned store over a hard-linked project copy. Category and unique-location totals must
reconcile exactly.

This handles hard links, including pnpm's same-filesystem store links. Bun may use APFS clone-on-write
copies on macOS; separate inodes can share physical extents and macOS does not expose a reliable
deletion-savings value through the current scanner. Disclose that limitation and do not infer savings
from equal content, file names, or apparent allocated size.

### Privacy and configuration boundary

The initial passive analyzer may read only:

- filesystem metadata and directory entry names;
- bounded `pyvenv.cfg` data needed to validate a virtual environment;
- bounded Conda environment-index paths;
- bounded, non-secret release metadata when needed to label a JDK or runtime.

It must not:

- source shell profiles or launch Node, Python, Java, package managers, or build tools;
- make a network request;
- parse project source files or dependency declarations;
- parse `.npmrc`, `.yarnrc.yml`, `.condarc`, Maven `settings.xml`, Gradle properties, or other
  potentially credential-bearing configuration;
- inspect package contents to build a dependency graph;
- delete, move, prune, clean, or mutate any file.

Environment variables visible to the SpaceLens process and documented defaults are the automatic
configuration seam. Finder-launched apps may not inherit interactive-shell variables, so the UI must
describe custom-root coverage as partial when it cannot be established.

### State and navigation integration

Add `.developerStorage` to `AppSection` and `ScanCoordinator.Activity`. Add
`DeveloperStorageStore` to `AppViewModel`, following the existing report-preserving, stale-ID-safe
analysis state machine. Add explicit intents for showing, starting, cancelling, adding/removing a
project container, and inspecting a reported directory.

Update `cancelAnalysesPreservingReports()` so switching to storage or starting any analysis cancels
the active intensive job while retaining completed reports. Extend `canRefreshCurrentSection` and
`refreshCurrentSection`; the existing Command-R menu behavior will then work without a new command.

The existing AI analysis stores are close duplicates. Do not make a large generic-store refactor a
prerequisite for this feature. After Developer Storage behavior is covered, evaluate extracting only
the repeated analysis-run lifecycle (task ID, prior-report retention, progress, cancellation, and
failure). Keep roots and selection in feature-specific stores so a generic interface does not expose
all feature differences to every caller.

## Implementation sequence

1. **Domain and catalog fixtures**
   - Add the domain types, canonical terms, three ecosystem definitions, known shared roots, project
     marker rules, and status model.
   - Unit-test path resolution, absolute environment overrides, legacy/additive roots, and artifact
     classification without filesystem traversal.
2. **Pruning project discovery**
   - Add the narrow `DiskScanner` discovery operation and safety budget.
   - Test pruning, cancellation, no symlink traversal, same-filesystem behavior, unreadable entries,
     provider timeout, and explicit coverage truncation.
3. **Analyzer and accounting**
   - Discover project artifacts, preflight/collapse roots, scan sequentially, aggregate observations,
     de-duplicate identities, and build the report.
   - Use temporary mixed Node/Python/JVM fixtures and hard links to prove totals and precedence.
4. **Store and application integration**
   - Add the store, section/activity cases, navigation intents, project-container picker, scan
     coordination, report preservation, and storage-map handoff.
5. **Views**
   - Add empty/running/completed/partial/failure states, ranked ecosystems, scope filter, categories,
     grouped projects/shared locations, expandable filesystem rows, context actions, and accessibility.
6. **Documentation and verification**
   - Update `README.md` with scope, privacy, custom-root limitations, and read-only behavior.
   - Add Developer Storage sources and essential discovery/accounting checks to the framework-free
     self-test build because `make test` is the required portable verification path.
   - Run all required commands and package validation.

## Test plan

Catalog and discovery tests:

- Every documented default and absolute environment override resolves to the expected ecosystem,
  scope, and kind; relative overrides are ignored.
- `node_modules` uses the nearest Node marker or version-control root; an explicitly selected folder
  is also accepted, while markerless automatic discoveries remain unattributed.
- Dependencies below known editor, extension, and AI-tool roots are tool-managed even when their
  installed package includes a manifest, including Antigravity's user and IDE extension roots.
- `N_PREFIX` runtime versions and global packages are shared locations and are not rediscovered as
  projects.
- Successfully measured zero-byte artifacts are omitted, while linked and incomplete locations stay
  visible as coverage issues.
- `.next/cache`, Turbo, and Vite override the parent artifact category without a second scan.
- `.venv`, `venv`, and especially generic `env` are rejected without a valid environment signature.
- A linked uv `.venv` is reported but not traversed.
- `__pycache__` and supported tool caches are found below nested Python packages.
- Maven `target` requires `pom.xml`; Gradle `build` and `.gradle` require Gradle evidence.
- An unrelated `target`, `build`, `env`, or `cache` directory is not counted.
- Mixed monorepos report all three ecosystems without entering one ecosystem's generated dependency
  tree to discover false nested projects.
- Multiple added containers and nested container selections do not duplicate candidates.
- Discovery budget, unreadable folders, symbolic links, cross-filesystem directories, and stalled
  provider folders produce coverage results and do not abort unrelated roots.

Analyzer and accounting tests:

- Per-kind totals reconcile to location, scope, ecosystem, and report unique totals.
- More than `DiskScanner.retainedChildLimit` entries still produce exact category totals.
- Parent/child and exact duplicate roots are physically scanned once.
- The same hard-linked file in pnpm store and `node_modules` appears in referenced size twice but in
  unique measured size once, with deterministic shared-store attribution.
- A missing identity falls back to standardized path de-duplication.
- Missing, unreadable, linked, and stalled locations remain visible as partial coverage.
- Cancellation stops discovery or measurement; a replaced run cannot publish stale progress/results.
- Project and shared filters change presentation only and never alter totals.

Store/UI tests and checks:

- The largest ecosystem becomes the initial selection; valid selection survives reruns.
- Adding/removing a project container reruns when appropriate and never modifies that folder.
- Starting disk, AI-tool, AI-model, or Developer Storage analysis cancels the prior intensive job and
  preserves its last complete report.
- Empty, running, previous-report refresh, partial, failure, and cancelled states render correctly.
- Finder, Terminal, and Inspect Storage Map target the displayed canonical directory.
- VoiceOver exposes ecosystem, scope, kind, size, sharing, and coverage without color.
- Keyboard navigation, reduced motion, light/dark appearance, and 1100 × 620 remain usable.

Required verification after implementation:

```bash
make build
make test
make app
codesign --verify --deep --strict --verbose=2 dist/SpaceLens.app
plutil -lint dist/SpaceLens.app/Contents/Info.plist
```

## Acceptance criteria

- **Developer Storage** appears under Analysis and never starts automatically.
- Only Node.js & Web, Python, and Java & JVM are present in the initial catalog.
- Known shared roots and home-folder discovery are automatic; additional project containers are
  explicitly selected.
- Every project artifact has strong ecosystem evidence; common folder names alone do not create
  false positives.
- Project, Tool-managed, Shared, and Unattributed storage are visibly separated and can be filtered.
- Successfully measured locations with no referenced allocated bytes do not create empty result rows.
- Unique totals use allocated bytes and device/inode de-duplication; referenced overlap is explained.
- Missing access, symlinks, discovery truncation, and provider stalls are coverage issues, not zero.
- No symlink is followed, no filesystem boundary is crossed, and no unbounded task-per-directory
  behavior is introduced.
- Analysis is cancellable, backgrounded, coordinated with every other intensive scan, and stale-safe.
- No package manager, runtime, shell profile, network call, deletion, cleanup, or mutation is used.
- A readable location can be revealed, opened in Terminal, or inspected in the standard storage map.
- Existing storage, AI Coding Tools, AI Models, packaging, and self-tests remain green.

## Explicitly deferred

- .NET/NuGet, Ruby/Bundler, Go modules, Rust/Cargo, Swift/Xcode, Android SDK/NDK, Docker/containers,
  IDE indexes, and databases.
- Guessing project roots from source contents when no recognized generated artifact or marker exists.
- Parsing auth-bearing manager configuration to discover custom paths.
- Package/dependency graphs, unused-dependency analysis, vulnerability checks, and latest-version
  checks.
- Cleanup buttons, vendor prune commands, deletion recommendations, and reclaimable-space estimates.
- Cross-machine, remote-development, container, and CI caches.
- Persisted reports, history, and growth trends.

## Primary references shaping the catalog

- [npm cache](https://docs.npmjs.com/cli/cache/)
- [Yarn settings](https://yarnpkg.com/configuration/yarnrc)
- [pnpm store settings](https://pnpm.io/settings/store)
- [Bun global cache](https://bun.sh/docs/pm/global-cache)
- [Next.js build cache](https://nextjs.org/docs/pages/guides/ci-build-caching)
- [Vite cache directory](https://vite.dev/config/shared-options)
- [Turborepo cache configuration](https://github.com/vercel/turborepo/blob/main/apps/docs/content/docs/reference/configuration.mdx)
- [Python virtual environments](https://docs.python.org/3/library/venv.html)
- [pip caching](https://pip.pypa.io/en/stable/topics/caching/)
- [Poetry configuration](https://python-poetry.org/docs/configuration/)
- [uv storage](https://docs.astral.sh/uv/reference/storage/)
- [pyenv](https://github.com/pyenv/pyenv)
- [Maven standard directory layout](https://maven.apache.org/guides/introduction/introduction-to-the-standard-directory-layout.html)
- [Maven local repositories](https://maven.apache.org/repositories/local.html)
- [Gradle directory layout](https://docs.gradle.org/current/userguide/gradle_directories.html)
- [Gradle managed directories and caches](https://docs.gradle.org/current/userguide/directory_layout.html)
- [Oracle JDK installation on macOS](https://docs.oracle.com/en/java/javase/21/install/installation-jdk-macos.html)
- [SDKMAN usage](https://sdkman.io/usage/)
