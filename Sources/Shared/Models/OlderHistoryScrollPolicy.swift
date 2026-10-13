import Foundation

/// One interactive backward-history page handed to the UI: whether older
/// history remains and the cursor the next request must use.
struct OlderHistoryScrollPage: Equatable, Sendable {
    let hasMore: Bool
    let nextBefore: String?
}

/// Interactive scroll-back policy. The cursor for the next page must come
/// from the server's RSM <first> of the page that was just returned, not from
/// the oldest local message: a page can consist entirely of reactions,
/// retractions or already-known stanzas, which insert no new message rows, so
/// a locally computed anchor would never advance and every subsequent scroll
/// would re-request the same page forever (spinner spins, nothing loads).
enum OlderHistoryScrollPolicy {
    /// - Parameter complete: the server's <fin complete="true"> flag.
    /// - Parameter pageFirstID: RSM <first> UID of the returned page — the
    ///   oldest item in it, i.e. the anchor for the next, older page.
    static func page(
        complete: Bool,
        pageFirstID: String?
    ) -> OlderHistoryScrollPage {
        let nextBefore = ArchiveSyncCheckpoint.normalizedCursor(pageFirstID)
        // An empty page (or one without RSM) cannot advance the cursor, so it
        // must never report "more" — otherwise the UI would loop on it.
        let hasMore = !complete && nextBefore != nil
        return OlderHistoryScrollPage(hasMore: hasMore, nextBefore: nextBefore)
    }
}
