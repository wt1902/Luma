import SwiftUI

/// Messages-style entrance for chat rows.
///
/// Opening a conversation reveals its first page as a bottom-up cascade
/// (`.cascade`), and a row appended while the timeline is already rendered
/// springs out of the composer's send control when outgoing (`.launch`).
/// Everything else stays `.settled`, which keeps history scrolling, reactions
/// and selection updates free of animation.
struct MessageBubbleEntrance: ViewModifier {
    enum Mode: Equatable {
        case settled
        case cascade(delay: TimeInterval)
        case launch(outgoing: Bool)

        var isSettled: Bool {
            if case .settled = self { return true }
            return false
        }
    }

    let mode: Mode

    // A settled row must never pass through an invisible frame, so only the
    // rows that actually animate start hidden.
    @State private var isRevealed: Bool
    @State private var hasStarted = false

    init(mode: Mode) {
        self.mode = mode
        _isRevealed = State(initialValue: mode.isSettled)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .scaleEffect(isRevealed ? 1 : displacedScale, anchor: scaleAnchor)
            .offset(y: isRevealed ? 0 : displacedRise)
            .onAppear(perform: reveal)
    }

    /// Outgoing bubbles shrink toward the trailing bottom corner, where the
    /// composer's send control sits; incoming ones grow from their own edge.
    private var displacedScale: CGFloat {
        switch mode {
        case .settled, .cascade:
            return ChatMessageEntrancePolicy.entranceScale
        case .launch(let outgoing):
            return outgoing
                ? ChatMessageEntrancePolicy.sendScale
                : ChatMessageEntrancePolicy.receiveScale
        }
    }

    private var scaleAnchor: UnitPoint {
        if case .launch(let outgoing) = mode, outgoing { return .bottomTrailing }
        return .bottom
    }

    private var displacedRise: CGFloat {
        switch mode {
        case .settled, .cascade:
            return ChatMessageEntrancePolicy.entranceRise
        case .launch(let outgoing):
            return outgoing
                ? ChatMessageEntrancePolicy.sendRise
                : ChatMessageEntrancePolicy.receiveRise
        }
    }

    private func reveal() {
        guard !hasStarted else { return }
        hasStarted = true
        guard !isRevealed else { return }
        let delay: TimeInterval
        if case .cascade(let cascadeDelay) = mode {
            delay = cascadeDelay
        } else {
            delay = 0
        }
        withAnimation(
            ChatMessageEntrancePolicy.appendAnimation.delay(delay)
        ) {
            isRevealed = true
        }
    }
}
