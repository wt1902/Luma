import CoreGraphics

#if os(iOS)
    import UIKit
#endif

/// Clockwise rotation, in degrees, applied to the video-note capture so the
/// recorded QuickTime track plays upright. The camera sensor is
/// landscape-native: per Apple's videoOrientation<->videoRotationAngle
/// equivalence a portrait recording needs a 90-degree clockwise rotation
/// (a QuickTime track matrix), never 0 — 0 leaves the circle sideways.
enum VideoNoteRotationPolicy {
    enum InterfaceOrientation: Equatable, Sendable {
        case portrait
        case portraitUpsideDown
        case landscapeLeft
        case landscapeRight
    }

    static func angle(for orientation: InterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        }
    }

    #if os(iOS)
        /// The orientation of the interface the user actually sees. The device
        /// sensor (UIDevice.current.orientation) can report landscape or
        /// face-up while the app stays portrait, which is exactly how a
        /// portrait circle ended up encoded sideways.
        @MainActor
        static var currentInterfaceOrientation: InterfaceOrientation {
            let orientation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .effectiveGeometry.interfaceOrientation
            switch orientation {
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: return .portrait
            }
        }
    #endif
}
