import Foundation
import SwiftUI

/// Timing and geometry for the Messages-style chat animations.
///
/// Two effects live here: the staggered rise of the first visible page when a
/// conversation opens, and the transition a freshly appended row uses while the
/// user already watches the timeline (an outgoing bubble launches from the
/// composer's send control, an incoming one springs from its own edge).
enum ChatMessageEntrancePolicy {
    /// A row waits this long behind every newer row below it, so the visible
    /// page unfolds bottom-up the way Messages does.
    static let entranceStagger: TimeInterval = 0.035

    /// Rows further from the bottom than this are left alone: past a screenful
    /// the cascade is invisible and the row may only appear on a later scroll.
    static let entranceCascadeLimit = 12

    static let entranceRise: CGFloat = 16
    static let entranceScale: CGFloat = 0.94

    static let sendScale: CGFloat = 0.2
    /// Launch point sits next to the composer's send control so the bubble
    /// reads as thrown out of the field instead of fading in place.
    static let sendRise: CGFloat = 12

    static let receiveScale: CGFloat = 0.4
    static let receiveRise: CGFloat = 10

    /// Upper bound of the spring used by both effects. The owning view keeps a
    /// row's entrance state alive for this long so a recycled row that reappears
    /// while scrolling plays nothing.
    static let entranceAnimationDuration: TimeInterval = 0.75

    /// A burst larger than this is a history page arriving, not a conversation:
    /// animating every row of a page would flash the whole timeline.
    static let appendAnimationLimit = 4

    /// Total time the opening cascade can still be pending for the last row.
    static var entranceCascadeDuration: TimeInterval {
        TimeInterval(entranceCascadeLimit - 1) * entranceStagger
            + entranceAnimationDuration
    }

    static var appendAnimation: Animation {
        .spring(response: 0.44, dampingFraction: 0.68)
    }

    /// Per-row delays keyed by client ID. The newest row leads the cascade and
    /// every older row follows one stagger step behind it; rows outside the
    /// cascade get no delay and therefore no entrance at all.
    static func entranceDelays(forIDs ids: [String]) -> [String: TimeInterval] {
        let last = ids.count - 1
        guard last >= 0 else { return [:] }
        let firstAnimated = max(0, ids.count - entranceCascadeLimit)
        var delays: [String: TimeInterval] = [:]
        delays.reserveCapacity(ids.count - firstAnimated)
        for index in firstAnimated...last {
            delays[ids[index]] = TimeInterval(last - index) * entranceStagger
        }
        return delays
    }

    /// Rows a query refresh added below everything already on screen.
    ///
    /// A MAM page paged in above the viewport is deliberately ignored: replaying
    /// the entrance mid-scroll would yank the timeline the user is reading. A
    /// burst of rows is treated as the same kind of archive delivery.
    static func appendedLaunchIDs(
        in ids: [String],
        after previous: Set<String>
    ) -> [String] {
        guard !previous.isEmpty else { return [] }
        guard let lastKnownIndex = ids.lastIndex(where: previous.contains)
        else { return [] }
        let appended = ids.dropFirst(lastKnownIndex + 1).filter {
            !previous.contains($0)
        }
        guard appended.count <= appendAnimationLimit else { return [] }
        return Array(appended)
    }
}