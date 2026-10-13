import CoreGraphics

struct MessageReplySwipePolicy {
    static let triggerDistance: CGFloat = 64
    /// Horizontal travel required before the indicator starts following the
    /// finger; keeps per-cell state untouched during ordinary scrolling.
    static let activationDistance: CGFloat = 24
    static let maximumOffset: CGFloat = 76
    /// Ratio required to lock the gesture into a reply swipe. Mostly vertical
    /// timeline scrolls (even diagonal ones) never reach it.
    static let lockDominance: CGFloat = 1.6
    /// Relaxed ratio once locked, so the finger can drift while finishing
    /// the swipe without it being cancelled by the scroll view.
    static let followDominance: CGFloat = 1.05

    /// Whether this translation can lock the gesture as a horizontal swipe.
    /// Both directions are accepted, and the lock is only available early:
    /// once the finger has travelled mostly vertically the scroll view owns
    /// the touch and the swipe must never activate for the rest of that
    /// gesture.
    static func canLock(_ translation: CGSize) -> Bool {
        abs(translation.height) <= 24
            && isHorizontal(translation, dominance: lockDominance)
            && abs(translation.width) >= activationDistance * 0.5
    }

    static func isHorizontal(_ translation: CGSize) -> Bool {
        isHorizontal(translation, dominance: lockDominance)
    }

    /// Visual offset of the bubble: negative for a left swipe, positive for
    /// a right swipe, zero while the movement is not clearly horizontal.
    static func offset(locked: Bool, translation: CGSize) -> CGFloat {
        let dominance = locked ? followDominance : lockDominance
        guard isHorizontal(translation, dominance: dominance) else { return 0 }
        let width = abs(translation.width)
        guard width >= activationDistance else { return 0 }
        let distance = min((width - activationDistance) * 0.72 + 12, maximumOffset)
        return translation.width < 0 ? -distance : distance
    }

    static func shouldReply(
        locked: Bool,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        let candidate = abs(predictedEndTranslation.width) > abs(translation.width)
            ? predictedEndTranslation
            : translation
        let dominance = locked ? followDominance : lockDominance
        return isHorizontal(candidate, dominance: dominance)
            && abs(candidate.width) >= triggerDistance
    }

    static func progress(for offset: CGFloat) -> CGFloat {
        min(1, abs(offset) / triggerDistance)
    }

    private static func isHorizontal(_ translation: CGSize, dominance: CGFloat) -> Bool {
        abs(translation.width) > abs(translation.height) * dominance
    }
}

