import AppKit
import SwiftUI

@MainActor
enum ChartPrototypeExporter {
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for variant in HyperspaceVariant.allCases {
            for scheme in [ColorScheme.dark, .light] {
                let content = HyperspaceStage(
                    variant: variant, root: ChartPrototypeData.disk, volume: ChartPrototypeData.volume
                )
                .frame(width: 1080, height: 730)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1.5
                guard let cgImage = renderer.cgImage else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let name = "\(variant.rawValue)-\(scheme == .dark ? "dark" : "light").png"
                try png.write(to: directory.appendingPathComponent(name))
                print("Rendered \(name)")
            }
        }
        try exportSceneData(to: directory.deletingLastPathComponent().appendingPathComponent("space-scenes.json"))
    }

    private static func exportSceneData(to url: URL) throws {
        var scenes: [String: Any] = [:]
        func append(_ root: FileNode, volume: VolumeInfo? = nil) {
            guard !root.children.isEmpty else { return }
            let extent = (volume?.usedFraction ?? 1) * .pi * 2
            let scene = SunburstScene(root: root, maxDepth: 6, angularExtent: extent,
                                      interactionRadius: 100, policy: .interactive)
            scenes[root.id] = [
                "id": root.id, "name": root.name, "size": root.size,
                "free": volume?.availableCapacity ?? 0, "extent": extent,
                "rings": scene.ringCount,
                "children": root.sortedChildren.map { child -> [String: Any] in
                    ["id": child.id, "name": child.name, "size": child.size,
                     "directory": child.isDirectory && !child.children.isEmpty]
                },
                "segments": scene.segments.map { segment -> [String: Any] in
                    ["id": segment.id, "target": segment.node?.id ?? segment.id,
                     "name": segment.name, "size": segment.size, "depth": segment.depth,
                     "start": segment.startAngle, "end": segment.endAngle, "hue": segment.hue]
                }
            ]
            for child in root.children { append(child) }
        }
        append(ChartPrototypeData.disk, volume: ChartPrototypeData.volume)
        append(ChartPrototypeData.folder)
        let document: [String: Any] = ["diskRoot": ChartPrototypeData.disk.id,
                                       "folderRoot": ChartPrototypeData.folder.id, "scenes": scenes]
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]).write(to: url)
        print("Exported native SunburstScene geometry")
    }
}
