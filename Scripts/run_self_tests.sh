#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

sdk_path="${SPACELENS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"

swiftc \
    -parse-as-library \
    -sdk "$sdk_path" \
    -module-cache-path "$temporary_dir/module-cache" \
    "$project_dir/Sources/SpaceLens/Models/FileNode.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Domain/AICodingToolsReport.swift" \
    "$project_dir/Sources/SpaceLens/Models/PreviousScanSummary.swift" \
    "$project_dir/Sources/SpaceLens/Models/VolumeInfo.swift" \
    "$project_dir/Sources/SpaceLens/Models/ScanSessionStore.swift" \
    "$project_dir/Sources/SpaceLens/Models/SunburstLayout.swift" \
    "$project_dir/Sources/SpaceLens/Support/Formatters.swift" \
    "$project_dir/Sources/SpaceLens/Support/PerformanceSignposts.swift" \
    "$project_dir/Sources/SpaceLens/Services/BulkDirectoryReader.swift" \
    "$project_dir/Sources/SpaceLens/Services/DiskScanner.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Analysis/AICodingRootDescriptor.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Analysis/AICodingToolsAnalyzer.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Catalogs/AICodingCatalogSupport.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Catalogs/AICodingToolsCatalog.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Catalogs/AntigravityCatalog.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Catalogs/ClaudeCodeCatalog.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Catalogs/CodexCatalog.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Catalogs/CursorCatalog.swift" \
    "$project_dir/Sources/SpaceLens/Features/AICodingTools/Catalogs/OpenCodeCatalog.swift" \
    "$project_dir/Sources/SpaceLens/Services/FullDiskAccessChecker.swift" \
    "$project_dir/Sources/SpaceLens/Services/PreviousScanStore.swift" \
    "$project_dir/Sources/SpaceLens/Services/ScanCoordinator.swift" \
    "$project_dir/Scripts/SelfTests.swift" \
    -o "$temporary_dir/SpaceLensSelfTests"

"$temporary_dir/SpaceLensSelfTests"
