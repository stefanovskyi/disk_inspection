# AI Models & Runtimes research for SpaceLens

Research date: 2026-09-11. Scope: macOS, Ollama, LM Studio, llama.cpp, the Hugging Face Hub cache, and unmanaged local inference models. This is implementation research; no application source, model file, or cache file was modified. One `lms ls --json` behavior probe attempted to wake LM Studio's service and stalled; it did not request a model load or filesystem mutation.

## Recommendation

Add **AI Models & Runtimes** as a sibling of **AI Coding Tools** under the existing **Analysis** sidebar section. Keep the current three-column interaction, but make the bottom detail card **Models** by default, with a `Models | Raw Folders` switch. A model name is the useful object for most people; raw paths remain an inspection escape hatch. A later `By Runtime | All Models` switch can expose the same data without changing the storage model.

The first release should be read-only. Offer **Reveal in Finder**, **Open in Terminal**, and **Inspect in Storage Map**. Do not offer the requested **Safe Delete** action yet. Ollama blobs may be referenced by several manifests, Hugging Face snapshots share blobs, LM Studio can import by hard link or symlink, and APFS clones may share physical blocks. A row's apparent size is therefore neither a reliable deletion target nor a promise of reclaimed space. Ollama and Hugging Face have graph-aware, vendor-supported removal operations; LM Studio currently has no equivalent documented deletion command. Directly removing manifests, blobs, indexes, or model shards would violate SpaceLens's read-only contract and can damage another model.

The implementation should also distinguish these quantities:

- **Physical storage:** allocated bytes of the union of unique observed filesystem objects. This is the runtime total displayed in the middle column.
- **Referenced bytes:** files needed by one logical model. These values may overlap between rows and therefore need not sum to the physical total. Where the reference graph is complete, show the split as **exclusive bytes** and **shared bytes**.
- **Potential duplicate bytes:** exact-content evidence across distinct physical files. This is a review hint, not automatically reclaimable space.
- **Reclaimable bytes:** only a manager-specific dry run can establish this safely. SpaceLens should not infer it from names, tags, or hashes alone.

## Fit with the current repository

The existing AI coding-tools feature already supplies the appropriate visual and concurrency pattern: a tool ranking column, a detail column, an observable feature store, catalog-driven discovery, shared scan coordination, and installation detection. See the current [feature boundary](../architecture/ai-coding-tools.md), [analysis service](../../Sources/SpaceLens/Features/AICodingTools/Analysis/AICodingToolsAnalyzer.swift), [store](../../Sources/SpaceLens/Features/AICodingTools/State/AICodingToolsStore.swift), and [three-column view](../../Sources/SpaceLens/Features/AICodingTools/Views/AICodingToolsView.swift).

Create a separate `Sources/SpaceLens/Features/AIModelsAndRuntimes/` feature, with its own `Domain/`, `Catalogs/`, `Analysis/`, `State/`, and `Views/` groups, rather than adding model-specific cases to `AICodingTools`. Runtime/model storage has relationships that the coding-tool report does not represent: many tags can share one blob, one model can be compatible with several runtimes, and one cache can be consumed by several clients. The existing `AICodingToolsReport.totalSize` protects against nested path overlap, but it does not represent content-addressed references, hard-link identity, or cross-runtime ownership.

Add `AppSection.aiModelsAndRuntimes` beside the current cases in [AppNavigation.swift](../../Sources/SpaceLens/Models/AppNavigation.swift), route it from [AppRootView.swift](../../Sources/SpaceLens/Views/AppRootView.swift), and add a sibling row under Analysis in the existing sidebar. Give the feature its own store so starting or cancelling a model analysis cannot invalidate an ordinary disk scan or coding-tools report. Add a distinct AI-models activity to [ScanCoordinator.swift](../../Sources/SpaceLens/Services/ScanCoordinator.swift) so it can share the coordinator without conflating progress or cancellation with the coding-tools activity. Reuse the existing Finder, Terminal, and storage-map actions and the visual card patterns.

[DiskScanner.swift](../../Sources/SpaceLens/Services/DiskScanner.swift) already supplies the important safety properties: detached cancellable work, bounded traversal, provider timeouts, no directory-symlink following, filesystem-boundary checks, and allocated-byte measurement. Its item observation currently exposes path, kind, allocated size, readability, and modification time, but not the internal device/inode identity or logical size. Exact hard-link accounting therefore requires extending the observation value to carry `FileIdentity`; do not infer hard links from matching paths or sizes. The scanner's retained-child compaction is suitable for display but not for model recognition, so classifiers should consume the per-item observation stream before `Smaller items` aggregation.

## Read-only validation on this Mac

These measurements are local observations, not stable vendor contracts. The sizing and discovery probe used metadata-only `stat`, `find`, and `du` operations, stayed on the selected filesystem, did not follow symlinks, and did not read conversations, logs, database rows, tokens, or weight payloads. A separate `lms ls --json` behavior check attempted to wake LM Studio's service and stalled, as noted below.

| Observed component | Result |
| --- | --- |
| Ollama app | `/Applications/Ollama.app`, version 0.33.3; 615,780 KiB allocated |
| Ollama CLI | `/usr/local/bin/ollama` is a symlink into the app's bundled resources |
| Ollama data | `~/.ollama` is 68 KiB; its `models` directory is empty |
| LM Studio app | `/Applications/LM Studio.app`, version 0.4.23+1; 771,004 KiB allocated |
| LM Studio home | `~/.lmstudio-home-pointer` resolves to the active `~/.cache/lm-studio` home |
| LM Studio CLI | `~/.cache/lm-studio/bin/lms`, a 65,085,664-byte arm64 executable; no `/usr/local/bin/lms` |
| LM Studio data | 18,935,704 KiB allocated: models 15,704,624 KiB, extensions 2,889,024 KiB, server logs 20,012 KiB, conversations 284 KiB |
| LM Studio model | One MLX Qwen3.8-27B-MLX-4bit directory with three SafeTensors shards, a shard index, configuration, and tokenizer files |
| LM Studio app support | `~/Library/Application Support/LM Studio` is 19,120 KiB |
| Hugging Face Hub | `~/.cache/huggingface/hub` is 19,856,448 KiB across 11 `models--*` repositories |
| llama.cpp | No Homebrew `llama-cli` or `~/llama.cpp` source checkout detected |
| Standalone search | No `.gguf`, `.ggml`, or `.safetensors` files found in the bounded Downloads, Desktop, or Documents search |

The active LM Studio layout is important evidence against hard-coding only the current documentation's `~/.lmstudio` examples. Invoking `lms ls --json` during the probe attempted to wake LM Studio's service and stalled. Passive SpaceLens analysis must not depend on launching a runtime or waiting on its local API.

The Hugging Face cache also contained 22 digest-named blobs repeated in two model-repository blob directories, accounting for 32,907,264 allocated bytes beyond one copy. The names provide exact-content evidence in this content-addressed layout, but they do not prove how many APFS blocks would become free after removing a reference.

## Discovery and enumeration contracts

### Ollama

Ollama's documented macOS installation is `/Applications/Ollama.app`; its bundled CLI is `Ollama.app/Contents/Resources/ollama`, and the app can create `/usr/local/bin/ollama` as a symlink. Its default data root is `~/.ollama`, with models below `~/.ollama/models` and logs including `~/.ollama/logs/app.log` and `server.log`. The `OLLAMA_MODELS` environment variable overrides the model directory. [Ollama macOS documentation](https://docs.ollama.com/macos), [environment configuration source](https://github.com/ollama/ollama/blob/main/envconfig/config.go).

Within the models directory, manifests are stored below `manifests/`, while blobs use content-addressed names below `blobs/`. The path implementation accepts a SHA-256 digest and normalizes `sha256:<hex>` to `sha256-<hex>`. [Ollama manifest path source](https://github.com/ollama/ollama/blob/main/manifest/paths.go). A manifest is schema-v2 JSON containing a config descriptor and layer descriptors; each descriptor records media type, digest, and declared size. [Ollama manifest source](https://github.com/ollama/ollama/blob/main/manifest/manifest.go), [layer source](https://github.com/ollama/ollama/blob/main/manifest/layer.go).

Offline enumeration can therefore safely:

1. Resolve `OLLAMA_MODELS` from SpaceLens's own process environment, then fall back to `~/.ollama/models`.
2. Walk manifest files as small, bounded JSON documents. Validate every digest before forming a blob path and require the standardized result to remain below the selected blob root.
3. Build `ModelRecord`s from manifest/tag paths, descriptors, and modification times. Resolve descriptors to `PhysicalObject`s and count each physical blob once in the runtime total.
4. Treat missing, malformed, or unreadable descriptors as partial coverage rather than aborting the runtime scan.

The supported live inventory endpoint, `GET /api/tags`, returns the model/tag name, modified time, declared size, manifest digest, format, family, parameter size, and quantization level. [List-models API](https://docs.ollama.com/api/tags). Ollama's server builds that result from manifests and GGUF metadata. [Ollama model-list cache source](https://github.com/ollama/ollama/blob/main/server/model_list_cache.go). This is useful optional enrichment only when an already-running service can be reached under a short timeout; the offline manifest graph must remain the passive default.

Ollama SHA-256-hashes new layers and reuses an existing blob when the digest already exists, so several tags or models can reference one physical object. [Ollama layer source](https://github.com/ollama/ollama/blob/main/manifest/layer.go). A model's declared size is the sum of its descriptors, so adding model row sizes can overstate physical storage. [Ollama manifest source](https://github.com/ollama/ollama/blob/main/manifest/manifest.go).

The installation card should look for the app bundle, its embedded CLI, the conventional symlink, and a resolved `PATH` entry, while deduplicating paths that identify the same file. App and CLI version detection should inspect the bundle metadata and known package-manager receipts; it should not execute an arbitrary discovered binary.

### LM Studio

LM Studio's active home is not a single hard-coded path. Official source resolves it from the path stored in `~/.lmstudio-home-pointer`, then an existing legacy `~/.cache/lm-studio`, then `~/.lmstudio`. [LM Studio home resolution source](https://github.com/lmstudio-ai/lmstudio-js/blob/main/packages/lms-common-server/src/findLMStudioHome.ts). Read the pointer as a narrowly bounded string, require an absolute standardized path, report symlinked or outside-scope targets without traversing them, and fall back to both defaults when the pointer is missing or invalid.

Current import documentation uses `<home>/models/<publisher>/<model>/<model-file.gguf>` and notes that the models directory is configurable. [LM Studio import documentation](https://lmstudio.ai/docs/app/advanced/import-model), [download-model documentation](https://lmstudio.ai/docs/app/basics/download-model). LM Studio supports both llama.cpp/GGUF and Apple MLX models. [LM Studio app documentation](https://lmstudio.ai/docs/app). An official MLX engine example still checks both `~/.lmstudio/models` and `~/.cache/lm-studio/models`, reinforcing the need for migration-aware discovery. [LM Studio MLX engine source](https://github.com/lmstudio-ai/mlx-engine/blob/main/batched_demo.py).

`lms` ships with the app and becomes available after LM Studio has run at least once. Its installer places the executable below `<active-home>/bin`; `/usr/local/bin/lms` is not the product's default contract. [LM Studio CLI documentation](https://lmstudio.ai/docs/cli), [CLI installer source](https://github.com/lmstudio-ai/lmstudio-js/blob/main/packages/lms-lmstudio/src/installCli/index.ts). The installation card should check `/Applications/LM Studio.app`, `<active-home>/bin/lms`, a resolved `PATH` entry, and official installation descriptors under the active home's `.internal` directory. [LM Studio paths source](https://github.com/lmstudio-ai/lms/blob/main/src/lmstudioPaths.ts), [service discovery source](https://github.com/lmstudio-ai/lmstudio-js/blob/main/packages/lms-common-server/src/findOrStartLlmster.ts).

Supported enumeration contracts include `lms ls --json --detailed`, `GET /api/v1/models`, and the SDK's `listDownloadedModels()`. They expose such fields as a model key, display name, format, relative path, size, architecture, parameters, quantization, variants, and loaded instances. [CLI model-list documentation](https://lmstudio.ai/docs/cli/local-models/ls), [REST model-list documentation](https://lmstudio.ai/docs/developer/rest/list), [TypeScript model-list documentation](https://lmstudio.ai/docs/typescript/manage-models/list-downloaded). They may start or depend on LM Studio services, so SpaceLens should not invoke them during an automatic scan. If a future opt-in live adapter is added, bound it with a short timeout and make service startup explicit.

For passive enumeration, treat each valid GGUF file as a model variant and each MLX directory as one model when it contains `config.json` plus `model*.safetensors`. Group shards through `model.safetensors.index.json` where present. Parse only bounded metadata files and headers. The local MLX model's `config.json`, for example, identified its architecture and 4-bit quantization without opening tensor payloads.

LM Studio presets live below `<active-home>/config-presets`, and conversations below `<active-home>/conversations`; chat JSON is explicitly not a stable interface consumers should edit or rely on. [Preset documentation](https://lmstudio.ai/docs/app/presets), [chat storage documentation](https://github.com/lmstudio-ai/docs/blob/main/0_app/1_basics/chat.md). Measure those trees by size and modification time only. Do not parse chat text. Managed inference backends are exposed through `lms runtime` commands and can be large enough to deserve an **Inference runtimes** composition category rather than being folded into logs or UI caches. [LM Studio runtime documentation](https://github.com/lmstudio-ai/docs/blob/main/3_cli/4_runtime/runtime.md).

Do not treat `.internal/model-index-cache.json` as a stable database contract. No public schema is documented, and the supported CLI/API already defines the model-level interface. If the passive filesystem scan and a user-invoked supported inventory disagree, show partial/uncertain coverage rather than mutating or rebuilding the internal cache.

LM Studio can import a model by move, copy, hard link, or symlink. [LM Studio import CLI documentation](https://lmstudio.ai/docs/cli/local-models/import). Scanner accounting must therefore preserve device/inode identity, never follow a symlink silently, and keep manager ownership separate from the referenced target. A linked model may occupy no new model-weight bytes in the LM Studio root.

### llama.cpp / CLI

The supported Homebrew installation is `brew install llama.cpp`; the formula includes `llama-cli`, `llama-server`, and other executables. [llama.cpp install documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/install.md), [Homebrew formula](https://formulae.brew.sh/formula/llama.cpp). Homebrew's supported default prefix is `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel, but SpaceLens should inspect Homebrew's configured prefix/receipt and resolved `PATH` rather than assume either path. [Homebrew installation documentation](https://docs.brew.sh/Installation).

A source build uses CMake and normally emits executables below the chosen build directory's `bin/`; the common command `cmake -B build` therefore produces `build/bin/llama-cli`. Both the source and build locations are user-selected. [llama.cpp build documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md), [CMake output configuration](https://github.com/ggml-org/llama.cpp/blob/master/CMakeLists.txt). There is no canonical `~/llama.cpp`. Detect a source build only when a user-added/project root contains strong signatures such as the llama.cpp project CMake files plus an actual `build/**/llama-cli` binary; a directory name alone is insufficient.

llama.cpp consumes arbitrary local GGUF paths and can download models from Hugging Face. [llama.cpp model documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/models.md). Its current Hugging Face cache resolver checks `LLAMA_CACHE`, `HF_HUB_CACHE`, `HUGGINGFACE_HUB_CACHE`, `HF_HOME/hub`, `XDG_CACHE_HOME/huggingface/hub`, and finally `~/.cache/huggingface/hub`. [llama.cpp cache source](https://github.com/ggml-org/llama.cpp/blob/master/common/hf-cache.cpp). Consequently, the llama.cpp middle-row count should describe **installations/builds**, while its model compatibility links should point to models physically owned by Hugging Face Hub or Standalone. Never add the same cache bytes to both rows.

### Hugging Face Hub cache

The Hub cache defaults to `~/.cache/huggingface/hub`; `HF_HUB_CACHE` overrides it and `HF_HOME` changes the parent. [Hugging Face cache layout](https://huggingface.co/docs/hub/local-cache), [environment variables](https://huggingface.co/docs/huggingface_hub/en/package_reference/environment_variables). Resolve only the current process environment in an automatic scan and let users add roots used by other shells or apps. Never inspect the token file or credential contents.

Each cached repository is encoded as `{type}s--<namespace>--<repo>` and contains `refs`, `snapshots`, and `blobs`; snapshot files are relative symlinks to content-addressed blobs, unchanged files are shared between revisions, and `.no_exist` caches known-missing files. Blob names are Git SHA-1 values for ordinary Git files or SHA-256 values for Git LFS objects. [Hugging Face cache layout](https://huggingface.co/docs/hub/local-cache).

For the requested model inventory, enumerate only `models--*` repository roots. Count each physical blob once for total storage, read `refs` only as small bounded commit identifiers, and use snapshot link names to group the files needed by a repo/revision without following those links during traversal. Dataset and Space repositories may be reported as other Hub storage, but they are not installed language models. Measure the separate Xet and assets caches as shared caches rather than allocating them to every model; their locations are independently configurable. [Hugging Face environment variables](https://huggingface.co/docs/huggingface_hub/en/package_reference/environment_variables).

The official `scan_cache_dir()`/`hf cache ls` interfaces can enrich revision-level metadata and report corrupt repositories without aborting the whole cache. [Hugging Face cache management guide](https://huggingface.co/docs/huggingface_hub/guides/manage-cache), [cache manager source](https://github.com/huggingface/huggingface_hub/blob/main/src/huggingface_hub/utils/_cache_manager.py). SpaceLens should not require a Python dependency or execute arbitrary environment tooling for the initial passive scan; implement the documented layout as a bounded recognizer and surface warnings.

### Standalone models

Standalone detection must be deliberately scoped. Search `~/Downloads` and `~/Desktop` only when those locations are inside the authorized analysis scope, plus user-added roots. Do not recursively scan all of `~/Documents` or the home directory merely because the user selected this Analysis tab. Honor Full Disk Access and provider-timeout behavior exactly as ordinary scans do.

Recognize formats by a bounded header or a coherent model directory, not filename extension alone:

- GGUF begins with its defined magic/version header and contains typed metadata before tensor descriptors/data. Standard keys include `general.name`, `general.architecture`, `general.file_type`, and `general.quantization_version`; the `general.file_type` enum includes quantization families such as Q4_K_M and Q8_0. The specification also defines conventional split-file numbering. [GGUF specification](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md).
- A SafeTensors file starts with an eight-byte little-endian header length followed by a JSON header containing tensor dtype, shape, and byte offsets. It can be one shard, an adapter, or another tensor artifact, so the extension alone does not establish a complete model. [SafeTensors format specification](https://github.com/huggingface/safetensors).
- MLX-LM loads a local model from configuration plus `model*.safetensors`, including sharded weights described by `model.safetensors.index.json`; quantization metadata is stored in configuration. [MLX-LM loader source](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/utils.py).
- Some llama.cpp multimodal models require a separate projector GGUF beside the text model. [llama.cpp multimodal documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal/gemma3.md). Group recognized companions, but do not guess that every similarly named GGUF can be deleted together.

The GGUF reader should stream and seek; cap metadata counts, string lengths, array lengths, and total header bytes before allocating; read only the small keys needed for display; and stop before tensor payloads. A corrupt or unsupported file remains visible as an unrecognized candidate with its measured size. Never load executable model code or honor `trust_remote_code` merely to derive a label.

## Storage composition

Use these mutually exclusive physical categories per measured root:

| Category | Examples | Notes |
| --- | --- | --- |
| Model weights | Ollama model/config blobs, GGUF, SafeTensors shards, MLX weight files | Usually dominant; count physical objects once |
| Manifests & presets | Ollama manifests, model JSON/YAML, tokenizer metadata, LM Studio presets | Small structured metadata; parsing must be bounded |
| Logs & diagnostics | Known runtime logs and crash diagnostics | Measure only; do not read content |
| Chats & databases | LM Studio conversations and local state databases | Measure only; never infer that these are disposable |
| Inference runtimes | LM Studio managed backends, Homebrew/source-built llama.cpp executables and libraries | Needed because runtimes/extensions are not model weights |
| UI caches & application state | LM Studio app/browser caches and non-model support data | Keep separate from logs |
| Other | Unrecognized remainder inside an owned root | Ensures category pills always reconcile to the measured total |

The user's four proposed pills can remain prominent, but omitting **Inference runtimes** and **UI caches & application state** would mislabel several gigabytes on the probed installation. Use a horizontally wrapping collection rather than forcing all categories into one line.

## Data and accounting model

Use stable path-based identifiers for UI state, but introduce a separate physical identity for accounting:

```swift
struct PhysicalObject {
    let standardizedURL: URL
    let fileIdentity: FileIdentity?       // device + inode when available
    let allocatedBytes: UInt64
    let logicalBytes: UInt64?
    let trustedDigest: ContentDigest?
}

struct ModelFileReference {
    let physicalObjectID: PhysicalObject.ID
    let role: ModelFileRole               // weights, config, tokenizer, projector, etc.
}

struct ModelRecord {
    let id: ModelID                       // runtime + manifest/repo/path identity
    let displayName: String
    let format: ModelFormat?              // GGUF, MLX/SafeTensors, unknown
    let quantization: String?
    let fileReferences: [ModelFileReference]
    let managers: Set<RuntimeID>
    let compatibleRuntimes: Set<RuntimeID>
}
```

One `PhysicalObject` can serve many `ModelRecord`s, and one `ModelRecord` can be managed by one runtime but compatible with several. Keep **manager/owner** separate from **compatible runtime**. Hugging Face owns its cache bytes even when llama.cpp loads them; LM Studio owns a copied import but only references the target of a symlink.

Deduplicate in stages:

1. Standardized identical path: one observation.
2. Same device/inode: one physical file even if several hard-link paths exist.
3. Trusted content digest: exact-content duplicate candidate across distinct physical identities. Ollama blob names and validated Hugging Face LFS blob names can supply digests without rereading giant files.
4. Optional user-requested verification: cancellable streaming SHA-256 for direct GGUF/SafeTensors files that lack a trusted digest. Do not hash tens or hundreds of gigabytes during every analysis.

APFS clones are copy-on-write objects that can share file content, and Foundation exposes `mayShareFileContent`, file-content identifiers, resource identifiers, and allocated-size values. [Apple File System overview](https://developer.apple.com/documentation/foundation/about-apple-file-system), [URL resource values](https://developer.apple.com/documentation/foundation/urlresourcevalues/maysharefilecontent). Even equal hashes at distinct paths do not establish the number of uniquely allocated blocks that deletion will free. The duplicate badge should initially say **Same weights as LM Studio model** and show the duplicated logical/allocated file size as context; it must not say **Saves 4.9 GB**. “Estimated reclaimable” belongs only to a manager-provided dry run.

## Detail-pane mapping

The right pane can preserve the existing card grammar:

- **Header:** runtime icon/name, unique physical allocated bytes, logical model/build/repository count, underlying file count, latest observed modification, and coverage state.
- **Installations:** app bundles, embedded CLI, resolved CLI, Homebrew receipt, or verified source builds. Deduplicate an app-embedded CLI and a symlink to it.
- **Storage composition:** the categories above, with an accessible legend and an **Other** remainder.
- **Models | Raw Folders:** models first. Each row shows the tag/repo/readable name, format, quantization, referenced bytes, and a shortened digest or underlying path. Explain when bytes overlap another row.

Recommended middle-column semantics:

| Item | Subtitle | Ownership rule |
| --- | --- | --- |
| Ollama | `X models · Y GB` | Unique files below resolved Ollama data/model roots plus installations/logs |
| LM Studio | `X models · Y GB` | Unique files below active/configured LM Studio roots plus app/runtime support |
| llama.cpp / CLI | `X installations · Y GB` | Executables, libraries, receipts, and verified build trees; linked models stay with their manager/root |
| Hugging Face Hub | `X cached model repos · Y GB` | Unique model-repo blobs plus model metadata; shared cache storage shown once |
| Standalone Models | `X loose models · Y GB` | Recognized files/directories in explicit bounded roots only |

If a path belongs to two recognizers, assign physical ownership once by the most specific manager contract and create cross-links for the other runtime. The All Models view can flatten `ModelRecord`s without changing totals.

## Deletion and privacy boundary

SpaceLens is currently a disk inspector, not a model package manager. The initial release should remain read-only for these additional reasons:

- Ollama's supported `DELETE /api/delete`/`ollama rm` flow removes a manifest and prunes only blobs unreferenced by remaining manifests. [Ollama delete API](https://docs.ollama.com/api/delete), [Ollama pruning implementation](https://github.com/ollama/ollama/blob/main/server/images.go). Directly deleting “the manifest and the blob” is specifically unsafe because another manifest may reference that blob.
- Hugging Face's cache manager computes a deletion strategy over revisions, refs, and blobs, and can report expected freed size before execution. [Hugging Face cache management guide](https://huggingface.co/docs/huggingface_hub/guides/manage-cache), [cache manager source](https://github.com/huggingface/huggingface_hub/blob/main/src/huggingface_hub/utils/_cache_manager.py). Directly deleting one snapshot symlink or shared blob bypasses that graph.
- LM Studio documents listing and importing local models, but its published CLI command surface does not currently document a model-removal operation. [LM Studio CLI documentation](https://lmstudio.ai/docs/cli). Direct filesystem deletion cannot safely update an undocumented internal index or account for loaded models, sibling variants, links, and custom roots.
- Standalone GGUF, MLX, and SafeTensors artifacts can have shards, projectors, tokenizers, adapters, or application references. SpaceLens cannot infer a complete deletion unit from a filename.

If the product later explicitly authorizes cleanup, design it as a separate feature and security review. It should preview exact canonical targets and manager ownership, refuse containment escapes and ambiguous links, use the vendor operation where one exists, require confirmation, remeasure afterwards, and never promise bytes beyond a manager dry run. For LM Studio, **Reveal in Finder** should remain the only action until a supported ownership-aware contract exists. Standalone files could only use a recoverable move to Trash after separate product approval and after SpaceLens can identify a complete shard/companion set; that is not part of this proposal.

Privacy behavior should be explicit:

- Parse only model manifests, bounded format headers, small configuration files needed for grouping, and filesystem metadata.
- Measure conversation stores, logs, databases, tokenizers, and presets without reading their contents.
- Never inspect Hugging Face token files or credential-bearing application state.
- Never launch a discovered executable, wake a runtime, load a model, or make a network request during passive analysis.
- Report unreadable, timed-out, linked-outside-scope, unsupported-layout, and partially parsed items separately; absence of access is not zero bytes.

## Implementation sequence and tests

1. **Domain and pure parsers.** Add runtime/model/physical-object types, safe path containment, a bounded Ollama manifest parser, a bounded GGUF metadata parser, Hugging Face repo/snapshot recognition, and MLX shard grouping. Unit-test malformed counts, traversal attempts, missing blobs/shards, symlink targets, and shared references.
2. **Discovery catalogs.** Add environment/default/candidate roots and installation definitions. Resolve LM Studio's bounded home pointer and preserve user-added custom model roots. Unit-test legacy/current layout precedence and app/CLI symlink deduplication.
3. **Targeted analysis.** Reuse `DiskScanner` and `ScanCoordinator`; extend scan observations with file identity and optionally logical size. Build category totals and object references before display compaction. Unit-test cancellation, provider timeouts, unreadable paths, bounded concurrency, and same-filesystem behavior using the existing test conventions.
4. **UI integration.** Add the sidebar section, independent store, middle ranking, installation/composition cards, and models-first toggle. Include accessible overlapping-size and partial-coverage explanations. Defer the global `By App | All Models` switch until the per-runtime models-first flow is stable.
5. **Duplicate enrichment.** Start with trusted manager digests and file identity. Make expensive hashing an explicit, cancellable action. Do not expose reclaim estimates.

Do not make application bundles, Hugging Face caches, or the entire home directory implicit recursive roots. Analyze only well-known narrowly owned roots and user-authorized locations. Preserve unrelated data and the current Full Disk Access preflight behavior.

## Acceptance criteria for a read-only first release

- The Analysis sidebar has a dedicated **AI Models & Runtimes** row and switching sections preserves other scan state.
- Ollama manifests enumerate logical tags while shared blobs contribute to physical totals once.
- LM Studio resolves the active home pointer, current and legacy homes, configured/user-added model roots, GGUF variants, and MLX shard groups without launching the service.
- llama.cpp reports verified installations/builds without claiming an arbitrary source or model directory.
- Hugging Face model repositories enumerate revisions and unique blobs without following snapshot symlinks or charging the same cache to llama.cpp.
- Standalone discovery is bounded and opt-in; extensions alone do not establish a model.
- Totals use allocated bytes and device/inode identity; referenced model-row sizes are visibly allowed to overlap.
- Duplicate badges state exact-content evidence, never guaranteed savings.
- Conversation, log, database, and credential contents are not read.
- All scans remain cancellable, bounded, filesystem-safe, and tolerant of unreadable or stalled paths.
- No delete, move, prune, model-load, service-start, or network operation is introduced.
