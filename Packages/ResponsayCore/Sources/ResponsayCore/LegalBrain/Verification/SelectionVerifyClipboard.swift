import Foundation

// MARK: - Selection-verify clipboard hygiene
//
// When a selection-`.verify` action opens browser deep-links, some sources carry
// the query in the URL (百度学术 ?wd=…, 知网 ?kw=…) and need nothing pasted; others
// are no-param front-end/paywalled search pages (国家法规库, 北大法宝, 人民法院案例库)
// where the user must paste the query into the site's own search box.
//
// The old path always clobbered the user's clipboard with the query — even when
// every opened source already carried it in the URL. Borrowing openless's clipboard
// hygiene (snapshot/sentinel restore on the read path), we only touch the clipboard
// when it is actually needed for a manual paste, and leave it untouched otherwise.

public enum SelectionVerifyClipboard {
    /// The query to pre-load onto the clipboard for manual paste, or `nil` to leave
    /// the user's clipboard untouched. Returns a value only when an opened deep-link
    /// route is a no-param site (its URL carries no query string) that the user must
    /// paste into; when every opened source already carries the query in its URL, the
    /// clipboard is left alone.
    public static func pasteQuery(openedRoutes: [VerificationRoute]) -> String? {
        openedRoutes.first { route in
            guard let url = route.url else { return false }   // never-opened routes don't count
            return url.query?.isEmpty ?? true                 // no query string → paste-required
        }?.query
    }
}
