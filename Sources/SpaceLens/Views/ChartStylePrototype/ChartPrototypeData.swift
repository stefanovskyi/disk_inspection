import Foundation

// Invented filesystem data. This fixture never reads the user's disk.
enum ChartPrototypeData {
    static let volume = VolumeInfo(
        url: URL(fileURLWithPath: "/SpaceLens-Preview"), name: "Macintosh HD",
        totalCapacity: 512_000_000_000, availableCapacity: 31_020_000_000,
        isExternal: false, isReadOnly: true
    )

    static let disk = FileNode(rootURL: volume.url, snapshot: directory("Macintosh HD", [
        directory("Users", [
            directory("Alex", [
                directory("Library", [
                    directory("Application Support", [
                        directory("Local models", [item("Model A", 48), item("Model B", 24), item("Model C", 12)]),
                        directory("Creative tools", [item("Media cache", 20), item("Assets", 14)]),
                        item("Other applications", 11)
                    ]),
                    directory("Caches", [item("Build cache", 27), item("Browser data", 7)]),
                    item("Containers", 10)
                ]),
                directory("Projects", [
                    directory("Workspace", [
                        directory("Web", [item("Dependencies", 22), item("Build output", 8)]),
                        item("Native apps", 18), item("Experiments", 10)
                    ])
                ]),
                directory("Downloads", [item("Installers", 21), item("Archives", 16)]),
                directory("Pictures", [item("Photo library", 18), item("Exports", 7)]),
                item("Documents", 4.8)
            ])
        ]),
        directory("Applications", [
            directory("Creative", [item("Video editor", 28), item("Design suite", 18)]),
            directory("Development", [item("IDE", 19), item("Simulators", 13)]),
            item("Other apps", 10.6)
        ]),
        directory("Library", [
            directory("Developer", [item("Toolchains", 22), item("Device support", 16)]),
            item("Application Support", 10), item("Updates", 6.5)
        ]),
        directory("private", [item("Virtual memory", 19), item("Temporary data", 8.98)]),
        directory("System", [item("Frameworks", 8), item("Resources", 4.1)])
    ]))

    static let folder = FileNode(
        rootURL: URL(fileURLWithPath: "/SpaceLens-Preview/Projects"),
        snapshot: directory("Projects", [
            directory("Web", [item("Dependencies", 12), item("Build output", 5), item("Source", 1)]),
            directory("Native", [item("Artifacts", 8), item("Assets", 4)]),
            item("Research", 6), item("Archives", 3)
        ])
    )

    private static func item(_ name: String, _ gigabytes: Double) -> FileNodeSnapshot {
        FileNodeSnapshot(
            name: name, size: Int64((gigabytes * 1_000_000_000).rounded()),
            isDirectory: false, isReadable: true, children: [], itemCount: 1
        )
    }

    private static func directory(_ name: String, _ children: [FileNodeSnapshot]) -> FileNodeSnapshot {
        FileNodeSnapshot(
            name: name, size: children.reduce(0) { $0 + $1.size },
            isDirectory: true, isReadable: true, children: children,
            itemCount: 1 + children.reduce(0) { $0 + $1.itemCount }
        )
    }
}
