import Foundation

/// Safety fence for links whose URL string came from an attacker-influenceable
/// source — chiefly the LLM/web-search「联网核验」result URLs. Such a string can be
/// `javascript:…`, `file:///…`, `data:…`, a custom app scheme that launches
/// another app, or a `https://trusted@evil.com` userinfo-phishing URL — any of
/// which fires the moment the user clicks. We only ever make a link clickable
/// when it is a plain `http`/`https` web URL with a real host and no userinfo.
public enum ExternalLinkPolicy {
    /// A clickable URL **only** for an `http`/`https` link with a non-empty host
    /// and no embedded userinfo; `nil` otherwise (render the string as inert,
    /// non-clickable text instead of a tappable link).
    public static func safeWebURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        guard url.user == nil else { return nil }   // reject https://trusted@evil.com phishing
        return url
    }
}
