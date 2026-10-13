import SwiftUI
import WebRTC

#if os(iOS)
import UIKit

struct RTCVideoRendererView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var mirrored = false
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = contentMode
        view.backgroundColor = .black
        context.coordinator.update(track: track, renderer: view)
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = contentMode
        view.transform = mirrored
            ? CGAffineTransform(scaleX: -1, y: 1)
            : .identity
        context.coordinator.update(track: track, renderer: view)
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.detach(renderer: view)
    }

    final class Coordinator {
        private weak var track: RTCVideoTrack?

        func update(track newTrack: RTCVideoTrack?, renderer: RTCMTLVideoView) {
            guard track !== newTrack else { return }
            track?.remove(renderer)
            track = newTrack
            newTrack?.add(renderer)
        }

        func detach(renderer: RTCMTLVideoView) {
            track?.remove(renderer)
            track = nil
        }
    }
}

#elseif os(macOS)
import AppKit

struct RTCVideoRendererView: NSViewRepresentable {
    let track: RTCVideoTrack?
    var mirrored = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> RTCMTLNSVideoView {
        let view = RTCMTLNSVideoView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        context.coordinator.update(track: track, renderer: view)
        return view
    }

    func updateNSView(_ view: RTCMTLNSVideoView, context: Context) {
        view.layer?.setAffineTransform(
            mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        )
        context.coordinator.update(track: track, renderer: view)
    }

    static func dismantleNSView(_ view: RTCMTLNSVideoView, coordinator: Coordinator) {
        coordinator.detach(renderer: view)
    }

    final class Coordinator {
        private weak var track: RTCVideoTrack?

        func update(track newTrack: RTCVideoTrack?, renderer: RTCMTLNSVideoView) {
            guard track !== newTrack else { return }
            track?.remove(renderer)
            track = newTrack
            newTrack?.add(renderer)
        }

        func detach(renderer: RTCMTLNSVideoView) {
            track?.remove(renderer)
            track = nil
        }
    }
}
#endif

#Preview {
    RTCVideoRendererView(track: nil)
        .frame(width: 280, height: 320)
        .background(Color.black)
}
