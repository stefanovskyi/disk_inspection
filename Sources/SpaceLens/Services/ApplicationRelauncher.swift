import Foundation

enum ApplicationRelauncher {
    /// Starts a helper that waits for this process to exit and then opens the
    /// app bundle again with `arguments`. Returns false when SpaceLens is not
    /// running from an app bundle (for example `swift run`) and cannot reopen.
    static func scheduleRelaunch(of bundle: Bundle = .main, arguments: [String]) -> Bool {
        let bundleURL = bundle.bundleURL
        guard bundleURL.pathExtension == "app" else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", helperScript, "spacelens-relaunch", String(getpid()), bundleURL.path]
            + arguments
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    /// Gives the quitting app up to 30 seconds to exit before reopening it.
    private static let helperScript = """
        pid="$1"; app="$2"; shift 2
        attempts=0
        while /bin/kill -0 "$pid" 2>/dev/null; do
            attempts=$((attempts + 1))
            [ "$attempts" -gt 300 ] && exit 1
            /bin/sleep 0.1
        done
        exec /usr/bin/open -n "$app" --args "$@"
        """
}
