# SpaceLens Storage Analysis

SpaceLens describes disk allocation without implying that measured files are safe to remove. This language keeps storage scans and specialized analysis reports consistent.

## Language

**Developer storage**:
Disk allocation created or installed by software-development workflows.
_Avoid_: Development tools, programming-language files

**Ecosystem**:
One supported development family: Node.js & Web, Python, or Java & JVM.
_Avoid_: Language, tool

**Project container**:
A folder searched for project roots that may be one project or contain many projects. The user's home directory is automatic; additional containers are explicitly added.
_Avoid_: Workspace, project root

**Project root**:
A directory recognized as a software project from ecosystem-specific marker files.
_Avoid_: Project container

**Project artifact**:
A recognized generated directory associated with a project root, such as `node_modules`, `.venv`, `target`, or `build`.
_Avoid_: Source, dependency tree

**Shared location**:
A per-user or system-wide store, cache, environment collection, or toolchain outside a project.
_Avoid_: Global location

**Artifact kind**:
The mutually exclusive storage role assigned to measured developer-storage bytes.
_Avoid_: Type, ecosystem

**Referenced size**:
The allocated bytes observed below a displayed location, including bytes also referenced by another location.
_Avoid_: Disk usage, reclaimable size

**Unique measured size**:
The allocated bytes attributed once across a complete analysis report using filesystem identity when available.
_Avoid_: Savings, reclaimable size
