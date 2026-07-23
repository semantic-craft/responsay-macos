import Foundation

/// Makes dictated/transformed text safe to insert into a shell prompt.
///
/// A terminal interprets a newline (or a pasted carriage return / control char) as
/// **Enter**, so a transcript like `ls\nmkdir foo` would *execute* `ls` the moment it
/// lands — a destructive P0 (`rm`, `git push --force`, …). The insertion path treats
/// all targets as plain text fields, so nothing else strips these.
///
/// Policy: for a known shell target, convert every newline / carriage-return /
/// other control character to a single space, collapse the resulting runs, and trim
/// the ends. The user can still type Return themselves; we never synthesize one.
/// (openless only `.trim()`s its LLM output — it does not strip *embedded* newlines —
/// so we deliberately go further for shell targets.)
public enum ShellTargetSanitizer {
    /// Bundle identifiers of terminal emulators where an implicit Return is dangerous.
    public static let shellBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "org.tabby",
        "com.alacritty"
    ]

    /// Whether `bundleID` is a terminal where newline → command execution.
    public static func isShell(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return shellBundleIDs.contains(bundleID)
    }

    /// Collapse every newline / control character to a single space so a shell can
    /// never receive an implicit Return. Returns the text unchanged for non-shell use.
    public static func sanitizeForShell(_ text: String) -> String {
        let controls = CharacterSet.controlCharacters
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" || controls.contains(scalar) {
                out.append(" ")
            } else {
                out.append(scalar)
            }
        }
        // Collapse runs of spaces introduced by the conversion, then trim the ends.
        let collapsed = String(out)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    /// Convenience: sanitize only when the target is a shell, otherwise pass through.
    public static func sanitize(_ text: String, forTargetBundleID bundleID: String?) -> String {
        isShell(bundleID) ? sanitizeForShell(text) : text
    }
}
