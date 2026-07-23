import Foundation

// MARK: - Self-relaunch command
//
// macOS applies a freshly granted Screen Recording permission only to a newly
// launched process (per-process TCC cache), so after the user grants it we offer
// a one-click self-relaunch instead of making them quit/reopen by hand. This
// builds the detached shell command that waits for the current process to exit,
// then reopens the app bundle. Pure (Foundation only) so the shell escaping is
// unit-tested; the macOS layer runs it and then terminates.

public enum RelaunchCommand {
    /// `/bin/sh -c` argv that waits for `pid` to die, then `open`s `bundlePath`.
    /// The path is POSIX single-quoted (embedded single quotes escaped) so spaces
    /// and shell metacharacters can neither break the command nor inject into it.
    public static func shell(pid: Int32, bundlePath: String) -> [String] {
        let quoted = singleQuoted(bundlePath)
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \(quoted)"
        return ["/bin/sh", "-c", script]
    }

    /// POSIX single-quote: wrap in '…', turning each embedded ' into the '\'' idiom.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
