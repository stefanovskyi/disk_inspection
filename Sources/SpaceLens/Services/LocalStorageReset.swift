import Foundation

/// Forgets everything SpaceLens keeps between launches so the next launch
/// behaves like the first one. Only SpaceLens' own preferences and support
/// folders are removed; scanned disks and folders are never touched.
struct LocalStorageReset {
    /// Tells a relaunched SpaceLens to clear its storage again before reading
    /// it, removing anything the quitting instance wrote on its way out.
    static let relaunchArgument = "--reset-local-storage"

    let defaults: UserDefaults
    let defaultsDomain: String
    let directories: [URL]

    static func forCurrentApplication(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> LocalStorageReset {
        var directories = [PreviousScanStore.defaultDirectoryURL]
        if let identifier = bundle.bundleIdentifier {
            let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library", isDirectory: true)
            directories.append(
                library.appendingPathComponent("Caches", isDirectory: true)
                    .appendingPathComponent(identifier, isDirectory: true)
            )
            directories.append(
                library.appendingPathComponent("Saved Application State", isDirectory: true)
                    .appendingPathComponent("\(identifier).savedState", isDirectory: true)
            )
        }
        return LocalStorageReset(
            defaults: .standard,
            // Without a bundle (`swift run`), standard defaults use the process name.
            defaultsDomain: bundle.bundleIdentifier ?? ProcessInfo.processInfo.processName,
            directories: directories
        )
    }

    /// Removes the preferences domain and the support folders.
    /// - Returns: The folders that exist but could not be removed.
    @discardableResult
    func perform(fileManager: FileManager = .default) -> [URL] {
        defaults.removePersistentDomain(forName: defaultsDomain)
        return directories.filter { directory in
            // Neither call follows a symbolic link: a linked folder's
            // destination is left alone and only the link is removed.
            guard (try? fileManager.attributesOfItem(atPath: directory.path)) != nil else {
                return false
            }
            do {
                try fileManager.removeItem(at: directory)
                return false
            } catch {
                return true
            }
        }
    }
}
