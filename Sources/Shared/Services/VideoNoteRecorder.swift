@preconcurrency import AVFoundation
import Combine
import CoreImage
import Foundation
import os

private let videoNoteFinalizeLogger = Logger(
    subsystem: "Luma",
    category: "video-note-finalize"
)

#if os(iOS)
    import UIKit
#endif

@MainActor
final class VideoNoteRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    struct Recording {
        let url: URL
        let duration: TimeInterval
    }

    @Published private(set) var isPrepared = false
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isUsingFrontCamera = true
    @Published private(set) var hasAlternateCamera = false
    @Published private(set) var isMicrophoneMuted = false

    let session = AVCaptureSession()
    var onFinished: ((Result<Recording, Error>) -> Void)?

    var hasRequiredAuthorization: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(
        label: "app.luma.video-note.capture-session",
        qos: .userInitiated
    )
    private let fileInspector = VideoNoteFileInspector()
    private var cameraInput: AVCaptureDeviceInput?
    private var microphoneInput: AVCaptureDeviceInput?
    private var timer: Timer?
    private var startedAt: Date?
    private var discardCurrentRecording = false
    private var stopRequested = false
    private var requestedMinimumDuration: TimeInterval = 0
    private var sessionGeneration = UUID()
    private var lifecycle: VideoNoteRecordingLifecycle = .idle
    private var activeRecordingURL: URL?
    private var stopRequestTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var finalizationTimeoutTask: Task<Void, Never>?
    private var fileValidationTask: Task<Void, Never>?
    private var cameraSwitchContinuation: CheckedContinuation<Void, Error>?
    private var cameraFlipTimeoutTask: Task<Void, Never>?
    private var restoreAudioRouteTask: Task<Void, Never>?
    private var cameraFlipRequested = false
    private var restartingSegmentForCameraFlip = false
    private var recordedSegments: [URL] = []
    private var segmentsTotalDuration: TimeInterval = 0
    /// The iOS front camera routes the quiet earpiece microphone, so the
    /// finalized audio gets a gain boost when any segment used it.
    private var usedFrontCamera = false

    private struct CaptureGraph {
        let cameraInput: AVCaptureDeviceInput
        let microphoneInput: AVCaptureDeviceInput
        let usesFrontCamera: Bool
    }

    private struct MovieOutputSnapshot: Sendable {
        let isRecording: Bool
        let recordedDuration: TimeInterval
    }

    func prepare() async throws {
        try await waitForPreviousRecordingToFinish()
        if lifecycle == .prepared, isPrepared { return }
        guard lifecycle == .idle, !isPrepared else {
            throw VideoNoteRecorderError.recordingBusy
        }

        let generation = UUID()
        sessionGeneration = generation
        await waitForPendingSessionOperations()
        guard !Task.isCancelled, sessionGeneration == generation else {
            throw CancellationError()
        }
        guard await Self.requestAccess(for: .video) else {
            throw VideoNoteRecorderError.cameraPermissionDenied
        }
        guard !Task.isCancelled, sessionGeneration == generation else {
            throw CancellationError()
        }
        guard await Self.requestAccess(for: .audio) else {
            throw VideoNoteRecorderError.microphonePermissionDenied
        }
        guard !Task.isCancelled, sessionGeneration == generation else {
            throw CancellationError()
        }

        var didPrepare = false
        defer {
            if !didPrepare {
                performShutdown()
            }
        }

        #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                // .default keeps voice processing and automatic gain control:
                // a talking circle recorded at arm's length (front camera)
                // stays loud and consistent, unlike .videoRecording which
                // disables AGC and records the raw microphone level.
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        #endif

        let graph = try await configureCaptureGraph()
        guard !Task.isCancelled, sessionGeneration == generation else {
            throw CancellationError()
        }
        cameraInput = graph.cameraInput
        microphoneInput = graph.microphoneInput
        isUsingFrontCamera = graph.usesFrontCamera
        hasAlternateCamera =
            hasCamera(at: graph.usesFrontCamera ? .back : .front)

        configureVideoConnection()
        try await startCaptureSession(generation: generation)
        isPrepared = true
        lifecycle = .prepared
        didPrepare = true
    }

    func start() throws {
        guard lifecycle == .prepared,
            isPrepared,
            session.isRunning
        else { throw VideoNoteRecorderError.notPrepared }
        guard !movieOutput.isRecording,
            activeRecordingURL == nil
        else {
            throw VideoNoteRecorderError.recordingBusy
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("video-note-\(UUID().uuidString).mov")

        discardCurrentRecording = false
        stopRequested = false
        requestedMinimumDuration = 0
        activeRecordingURL = url
        lifecycle = .starting
        if !restartingSegmentForCameraFlip {
            startedAt = nil
            elapsed = 0
        }
        restartingSegmentForCameraFlip = false
        if isUsingFrontCamera {
            usedFrontCamera = true
        }
        isRecording = true

        let output = movieOutput
        let delegate = self
        sessionQueue.async {
            output.startRecording(to: url, recordingDelegate: delegate)
        }
        scheduleStartupTimeout(for: url)
    }

    func stop() {
        requestStop(afterMinimumDuration: VideoNoteStopPolicy.minimumCaptureDuration)
    }

    func stop(afterMinimumDuration minimumDuration: TimeInterval) async {
        requestStop(afterMinimumDuration: minimumDuration)
    }

    func cancel() {
        discardCurrentRecording = true
        stopRequested = true
        requestedMinimumDuration = 0

        switch lifecycle {
        case .starting, .recording:
            lifecycle = .stopping
            stopRequestTask?.cancel()
            stopRequestTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stopMovieOutput()
                guard !Task.isCancelled,
                    self.lifecycle == .stopping,
                    let url = self.activeRecordingURL
                else { return }
                self.scheduleFinalizationTimeout(for: url)
            }
        case .stopping:
            break
        case .idle, .prepared:
            performShutdown()
        }
    }

    /// Flips between the front and the back camera. While recording,
    /// AVFoundation tears the active movie down when its input is removed, so
    /// the current segment is closed first, the camera is swapped, and a new
    /// segment starts; the segments are merged back together on finalization.
    func switchCamera() async throws {
        #if os(iOS)
            guard isPrepared,
                hasAlternateCamera,
                let currentInput = cameraInput
            else {
                throw VideoNoteRecorderError.notPrepared
            }
            switch lifecycle {
            case .prepared:
                try await swapCameraInput(replacing: currentInput)
            case .starting, .recording:
                try await stopSegmentForCameraFlip()
                guard let input = cameraInput else {
                    throw VideoNoteRecorderError.notPrepared
                }
                try await swapCameraInput(replacing: input)
                restartingSegmentForCameraFlip = true
                try start()
            case .stopping, .idle:
                throw VideoNoteRecorderError.notPrepared
            }
        #else
            throw VideoNoteRecorderError.alternateCameraUnavailable
        #endif
    }

    /// Closes the in-flight segment without finishing the whole recording:
    /// the file is kept (when non-empty), per-segment state resets, and the
    /// pending switchCamera call resumes.
    private func stopSegmentForCameraFlip() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            cameraSwitchContinuation = continuation
            cameraFlipRequested = true
            requestStop(afterMinimumDuration: 0)
            scheduleCameraFlipTimeout()
        }
    }

    private func scheduleCameraFlipTimeout() {
        cameraFlipTimeoutTask?.cancel()
        cameraFlipTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled,
                let self,
                let continuation = self.cameraSwitchContinuation
            else { return }
            self.cameraSwitchContinuation = nil
            self.cameraFlipRequested = false
            continuation.resume(
                throwing: VideoNoteRecorderError.finalizationTimedOut
            )
        }
    }

    private func handleCameraFlipSegment(url: URL) {
        cameraFlipTimeoutTask?.cancel()
        cameraFlipTimeoutTask = nil
        let continuation = cameraSwitchContinuation
        cameraSwitchContinuation = nil

        fileValidationTask?.cancel()
        fileValidationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let inspection = await self.fileInspector.inspect(
                url: url,
                fallbackDuration: self.measuredWallClockDuration
            )
            guard !Task.isCancelled,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }
            self.fileValidationTask = nil
            if let inspection, inspection.duration > 0.05 {
                self.recordedSegments.append(url)
                self.segmentsTotalDuration += inspection.duration
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            self.resetForNextSegment()
            continuation?.resume(returning: ())
        }
    }

    private func resetForNextSegment() {
        lifecycle = .prepared
        activeRecordingURL = nil
        discardCurrentRecording = false
        stopRequested = false
        requestedMinimumDuration = 0
        isRecording = false
        timer?.invalidate()
        timer = nil
    }

    private func swapCameraInput(
        replacing currentInput: AVCaptureDeviceInput
    ) async throws {
        let nextPosition: AVCaptureDevice.Position =
            isUsingFrontCamera ? .back : .front
        guard
            let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: nextPosition
            )
        else {
            throw VideoNoteRecorderError.alternateCameraUnavailable
        }

        let nextInput = try AVCaptureDeviceInput(device: camera)
        let session = session
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                session.beginConfiguration()
                session.removeInput(currentInput)
                guard session.canAddInput(nextInput) else {
                    if session.canAddInput(currentInput) {
                        session.addInput(currentInput)
                    }
                    session.commitConfiguration()
                    continuation.resume(
                        throwing: VideoNoteRecorderError.configurationFailed
                    )
                    return
                }
                session.addInput(nextInput)
                session.commitConfiguration()
                continuation.resume()
            }
        }

        cameraInput = nextInput
        isUsingFrontCamera = nextPosition == .front
        hasAlternateCamera =
            hasCamera(at: nextPosition == .front ? .back : .front)
        configureVideoConnection()
        #if os(iOS)
            // Flipping to the front camera makes iOS re-route the audio to
            // the earpiece and switch the voice processing into the quiet
            // receiver mode — but the system performs that re-routing
            // asynchronously AFTER the swap commits. Restore the speaker
            // route with a short delay so it wins the race.
            restoreAudioRouteTask?.cancel()
            restoreAudioRouteTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled, let self, self.isPrepared else {
                    return
                }
                let audioSession = AVAudioSession.sharedInstance()
                try? audioSession.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetoothHFP]
                )
                try? audioSession.overrideOutputAudioPort(.speaker)
            }
        #endif
    }

    func toggleMicrophoneMuted() {
        guard isPrepared, let connection = movieOutput.connection(with: .audio) else { return }
        isMicrophoneMuted.toggle()
        connection.isEnabled = !isMicrophoneMuted
    }

    func shutdown() {
        if lifecycle.isBusy || movieOutput.isRecording {
            cancel()
            return
        }
        performShutdown()
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor [weak self] in
            self?.recordingDidStart(url: fileURL)
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            await self?.recordingDidFinish(url: outputFileURL, error: error)
        }
    }

    private func requestStop(afterMinimumDuration minimumDuration: TimeInterval) {
        guard isRecording,
            lifecycle == .starting || lifecycle == .recording
        else { return }
        stopRequested = true
        requestedMinimumDuration = max(
            requestedMinimumDuration,
            max(0, minimumDuration)
        )
        scheduleStopAfterActualStartIfNeeded()
    }

    private func recordingDidStart(url: URL) {
        guard
            VideoNoteRecordingLifecycle.acceptsCompletion(
                activeURL: activeRecordingURL,
                outputURL: url
            ), isRecording,
            lifecycle == .starting || lifecycle == .stopping
        else { return }

        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        if startedAt == nil {
            startedAt = Date()
        }

        if lifecycle == .stopping {
            // Cancellation can be requested while startRecording is still
            // crossing the capture queue. If the first stop observed
            // isRecording == false, stop again after the real didStart rather
            // than leaving an orphaned capture running until the watchdog.
            stopRequestTask?.cancel()
            stopRequestTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.stopMovieOutput()
                guard !Task.isCancelled,
                    self.lifecycle == .stopping,
                    VideoNoteRecordingLifecycle.acceptsCompletion(
                        activeURL: self.activeRecordingURL,
                        outputURL: url
                    )
                else { return }
                self.scheduleFinalizationTimeout(for: url)
            }
            return
        }

        lifecycle = .recording
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = min(
                    VideoNoteStopPolicy.maximumCaptureDuration,
                    Date().timeIntervalSince(startedAt)
                )
            }
        }
        scheduleStopAfterActualStartIfNeeded()
    }

    private func scheduleStopAfterActualStartIfNeeded() {
        guard stopRequested,
            lifecycle == .recording,
            startedAt != nil,
            let url = activeRecordingURL
        else { return }

        stopRequestTask?.cancel()
        let minimumDuration = requestedMinimumDuration
        let mediaDeadline = Date().addingTimeInterval(
            VideoNoteStopPolicy.recordedDurationWaitTimeout
        )
        stopRequestTask = Task { @MainActor [weak self] in
            while true {
                guard !Task.isCancelled,
                    let self,
                    self.lifecycle == .recording,
                    VideoNoteRecordingLifecycle.acceptsCompletion(
                        activeURL: self.activeRecordingURL,
                        outputURL: url
                    )
                else { return }

                let snapshot = await self.movieOutputSnapshot()
                guard !Task.isCancelled,
                    self.lifecycle == .recording,
                    VideoNoteRecordingLifecycle.acceptsCompletion(
                        activeURL: self.activeRecordingURL,
                        outputURL: url
                    )
                else { return }

                if !snapshot.isRecording {
                    // AVFoundation stopped without the user's stop reaching
                    // the output. Wait for didFinish, but never let this state
                    // remain without a finalization watchdog.
                    self.lifecycle = .stopping
                    self.scheduleFinalizationTimeout(for: url)
                    return
                }

                let remaining = VideoNoteStopPolicy.remainingRecordedDuration(
                    recordedDuration: snapshot.recordedDuration
                        + self.segmentsTotalDuration,
                    minimumDuration: minimumDuration
                )
                if remaining <= 0 || Date() >= mediaDeadline { break }

                do {
                    try await Task.sleep(
                        nanoseconds: min(
                            VideoNoteStopPolicy.recordedDurationPollNanoseconds,
                            UInt64((remaining * 1_000_000_000).rounded(.up))
                        )
                    )
                } catch {
                    return
                }
            }

            guard !Task.isCancelled,
                let self,
                self.lifecycle == .recording,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }

            self.lifecycle = .stopping
            await self.stopMovieOutput()
            guard !Task.isCancelled,
                self.lifecycle == .stopping,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }
            self.scheduleFinalizationTimeout(for: url)
        }
    }

    private func recordingDidFinish(url: URL, error: Error?) async {
        guard
            VideoNoteRecordingLifecycle.acceptsCompletion(
                activeURL: activeRecordingURL,
                outputURL: url
            )
        else {
            // A delayed callback from an earlier attempt must not tear down a
            // newer capture graph. Do not delete it here: macOS can spell the
            // same temporary URL through a filesystem alias, and preserving a
            // doubtful callback is safer than deleting the active movie.
            return
        }

        stopRequestTask?.cancel()
        stopRequestTask = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        lifecycle = .stopping

        if cameraFlipRequested {
            // A flip during recording first closes the current segment: keep
            // it and hand control back to the pending switchCamera call.
            cameraFlipRequested = false
            handleCameraFlipSegment(url: url)
            return
        }

        let fallbackDuration = measuredWallClockDuration
        let shouldDiscard = discardCurrentRecording
        let wasStopRequested = stopRequested
        if shouldDiscard {
            try? FileManager.default.removeItem(at: url)
            finishAndReset(nil)
            return
        }

        // Release the camera BEFORE the finalize re-encode runs. While the
        // capture session is still live, the writer's encoder contends with
        // it for the media hardware and its input can block forever in
        // isReadyForMoreMediaData — the «Завершение…» hang.
        await flushCaptureSessionForFinalization()

        fileValidationTask?.cancel()
        fileValidationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let inspection = await self.fileInspector.inspect(
                url: url,
                fallbackDuration: fallbackDuration
            )
            guard !Task.isCancelled,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }
            self.fileValidationTask = nil

            if self.discardCurrentRecording {
                try? FileManager.default.removeItem(at: url)
                self.finishAndReset(nil)
                return
            }

            if let inspection,
                VideoNoteRecordingCompletionPolicy.wasRequestedOrReachedLimit(
                    stopRequested: wasStopRequested,
                    error: error,
                    recordedDuration: self.segmentsTotalDuration
                        + inspection.duration,
                    maximumDuration: VideoNoteStopPolicy.maximumCaptureDuration
                ),
                VideoNoteStopPolicy.isValidFinalDuration(
                    self.segmentsTotalDuration + inspection.duration
                )
            {
                let totalDuration =
                    self.segmentsTotalDuration + inspection.duration
                // Merge the flip segments back together (passthrough, no
                // re-encode). The circle bubble crops the picture visually.
                let finalization = await self.fileInspector.finalizeVideoNote(
                    segments: self.recordedSegments + [url],
                    frontCameraUsed: self.usedFrontCamera
                )
                guard !Task.isCancelled,
                    VideoNoteRecordingLifecycle.acceptsCompletion(
                        activeURL: self.activeRecordingURL,
                        outputURL: url
                    )
                else { return }
                if let finalization {
                    if finalization.url != url {
                        try? FileManager.default.removeItem(at: url)
                    }
                    self.finishAndReset(
                        .success(
                            Recording(
                                url: finalization.url,
                                duration: finalization.duration
                            )))
                } else {
                    // The transcode fell through; the raw file was already
                    // validated, so send it uncropped instead of losing the
                    // recording entirely.
                    self.finishAndReset(
                        .success(
                            Recording(url: url, duration: totalDuration)
                        ))
                }
                return
            }

            try? FileManager.default.removeItem(at: url)
            let failure: Error
            if !wasStopRequested,
                !VideoNoteRecordingCompletionPolicy.wasRequestedOrReachedLimit(
                    stopRequested: false,
                    error: error,
                    recordedDuration: inspection?.duration ?? fallbackDuration,
                    maximumDuration: VideoNoteStopPolicy.maximumCaptureDuration
                )
            {
                failure = VideoNoteRecorderError.recordingInterrupted
            } else if !VideoNoteRecordingCompletionPolicy.shouldKeepOutput(for: error), let error {
                failure = error
            } else {
                failure = VideoNoteRecorderError.emptyRecording
            }
            self.finishAndReset(.failure(failure))
        }
    }

    private var measuredWallClockDuration: TimeInterval {
        guard let startedAt else { return max(0, elapsed) }
        return max(elapsed, Date().timeIntervalSince(startedAt))
    }

    private func stopMovieOutput() async {
        let output = movieOutput
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if output.isRecording {
                    output.stopRecording()
                }
                continuation.resume()
            }
        }
    }

    private func movieOutputSnapshot() async -> MovieOutputSnapshot {
        let output = movieOutput
        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                let seconds = CMTimeGetSeconds(output.recordedDuration)
                continuation.resume(
                    returning: MovieOutputSnapshot(
                        isRecording: output.isRecording,
                        recordedDuration: seconds.isFinite && seconds > 0 ? seconds : 0
                    ))
            }
        }
    }

    private func flushCaptureSessionForFinalization() async {
        let output = movieOutput
        let session = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if output.isRecording {
                    output.stopRecording()
                }
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
        // stopRunning is asynchronous: wait until the camera pipeline really
        // released its media resources. The finalize re-encode must not start
        // while the capture session still holds the encoder/muxer, otherwise
        // the writer's inputs never become ready.
        let stopDeadline = Date().addingTimeInterval(10)
        while session.isRunning, Date() < stopDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func scheduleStartupTimeout(for url: URL) {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: VideoNoteStopPolicy.startupTimeoutNanoseconds
            )
            guard !Task.isCancelled,
                let self,
                self.lifecycle == .starting,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }

            self.lifecycle = .stopping
            await self.stopMovieOutput()
            guard !Task.isCancelled,
                self.lifecycle == .stopping,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }
            self.scheduleFinalizationTimeout(for: url)
        }
    }

    private func scheduleFinalizationTimeout(for url: URL) {
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: VideoNoteStopPolicy.finalizationTimeoutNanoseconds
            )
            guard !Task.isCancelled,
                let self,
                self.lifecycle == .stopping,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }

            // A few macOS camera drivers stop the file output but delay its
            // delegate callback until the capture session itself is flushed.
            // This is recovery-only; the normal path still waits for
            // didFinishRecording before touching the session.
            await self.flushCaptureSessionForFinalization()
            try? await Task.sleep(
                nanoseconds: VideoNoteStopPolicy.finalizationRecoveryGraceNanoseconds
            )
            guard !Task.isCancelled,
                self.lifecycle == .stopping,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }
            let fallbackDuration = self.measuredWallClockDuration
            let inspection = await self.fileInspector.inspect(
                url: url,
                fallbackDuration: fallbackDuration
            )
            guard !Task.isCancelled,
                self.lifecycle == .stopping,
                VideoNoteRecordingLifecycle.acceptsCompletion(
                    activeURL: self.activeRecordingURL,
                    outputURL: url
                )
            else { return }

            self.finalizationTimeoutTask = nil
            if self.discardCurrentRecording {
                try? FileManager.default.removeItem(at: url)
                self.finishAndReset(nil)
            } else if let inspection,
                VideoNoteRecordingCompletionPolicy.wasRequestedOrReachedLimit(
                    stopRequested: self.stopRequested,
                    error: nil,
                    recordedDuration: inspection.duration,
                    maximumDuration: VideoNoteStopPolicy.maximumCaptureDuration
                ),
                VideoNoteStopPolicy.isValidFinalDuration(inspection.duration)
            {
                // Some macOS camera drivers finalize the .mov but omit the
                // delegate callback. A playable file is more authoritative
                // than the missing callback and remains safe to send.
                self.finishAndReset(
                    .success(
                        Recording(
                            url: url,
                            duration: inspection.duration
                        )))
            } else if !self.stopRequested {
                try? FileManager.default.removeItem(at: url)
                self.finishAndReset(.failure(VideoNoteRecorderError.recordingInterrupted))
            } else {
                try? FileManager.default.removeItem(at: url)
                self.finishAndReset(.failure(VideoNoteRecorderError.finalizationTimedOut))
            }
        }
    }

    private func finishAndReset(_ result: Result<Recording, Error>?) {
        fileValidationTask = nil
        let completion = onFinished
        performShutdown()
        if let result {
            completion?(result)
        }
    }

    private func performShutdown() {
        sessionGeneration = UUID()
        stopRequestTask?.cancel()
        stopRequestTask = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        fileValidationTask?.cancel()
        fileValidationTask = nil
        cameraSwitchContinuation = nil
        cameraFlipTimeoutTask?.cancel()
        cameraFlipTimeoutTask = nil
        cameraFlipRequested = false
        restartingSegmentForCameraFlip = false
        usedFrontCamera = false
        let segments = recordedSegments
        recordedSegments = []
        segmentsTotalDuration = 0
        for segment in segments {
            try? FileManager.default.removeItem(at: segment)
        }
        timer?.invalidate()
        timer = nil
        resetCaptureGraph()
        lifecycle = .idle
        activeRecordingURL = nil
        discardCurrentRecording = false
        stopRequested = false
        requestedMinimumDuration = 0
        startedAt = nil
        elapsed = 0
        isPrepared = false
        isRecording = false
        isUsingFrontCamera = true
        hasAlternateCamera = false
        isMicrophoneMuted = false
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func waitForPreviousRecordingToFinish() async throws {
        guard lifecycle != .starting, lifecycle != .recording else {
            throw VideoNoteRecorderError.recordingBusy
        }
        let deadline = Date().addingTimeInterval(10)
        while lifecycle == .stopping, Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard lifecycle != .stopping else {
            throw VideoNoteRecorderError.finalizationTimedOut
        }
    }

    private func configureVideoConnection() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        #if os(iOS)
            configureInteroperableVideoCodec(for: connection)
        #endif
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isUsingFrontCamera
        }
        #if os(iOS)
            // iOS records upright portrait at capture time; macOS keeps the
            // camera's native landscape orientation (the circle bubble crops
            // it visually).
            let rotationAngle = videoRotationAngle
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        #endif
    }

    #if os(iOS)
        private var videoRotationAngle: CGFloat {
            // The interface orientation is authoritative: it is what the user
            // actually sees. The device sensor can claim landscape (or
            // face-up) while the app stays portrait, and recording with the
            // sensor value rotated portrait circles by 90 degrees.
            VideoNoteRotationPolicy.angle(
                for: VideoNoteRotationPolicy.currentInterfaceOrientation
            )
        }

    #endif

    #if os(iOS)
        private func configureInteroperableVideoCodec(for connection: AVCaptureConnection) {
            guard movieOutput.availableVideoCodecTypes.contains(.h264) else { return }
            movieOutput.setOutputSettings(
                [AVVideoCodecKey: AVVideoCodecType.h264],
                for: connection
            )
        }
    #endif

    private func resetCaptureGraph() {
        let session = session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
            guard !session.inputs.isEmpty || !session.outputs.isEmpty else { return }
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
        }
        cameraInput = nil
        microphoneInput = nil
    }

    private func waitForPendingSessionOperations() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                continuation.resume()
            }
        }
    }

    private func hasCamera(at position: AVCaptureDevice.Position) -> Bool {
        AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        ) != nil
    }

    private func configureCaptureGraph() async throws -> CaptureGraph {
        let session = session
        let movieOutput = movieOutput
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                session.beginConfiguration()
                do {
                    session.sessionPreset =
                        session.canSetSessionPreset(.vga640x480)
                        ? .vga640x480
                        : .medium

                    #if os(iOS)
                        let camera =
                            AVCaptureDevice.default(
                                .builtInWideAngleCamera,
                                for: .video,
                                position: .front
                            ) ?? AVCaptureDevice.default(for: .video)
                    #else
                        let camera = AVCaptureDevice.default(for: .video)
                    #endif
                    guard let camera else {
                        throw VideoNoteRecorderError.cameraUnavailable
                    }
                    let cameraInput = try AVCaptureDeviceInput(device: camera)
                    guard session.canAddInput(cameraInput) else {
                        throw VideoNoteRecorderError.configurationFailed
                    }
                    session.addInput(cameraInput)

                    #if os(iOS)
                        // iOS routes the microphone by the active camera:
                        // the front camera gets the quiet earpiece mic and the
                        // back camera the loud bottom mic. Pin the bottom
                        // microphone explicitly so the voice level stays
                        // consistent no matter which camera is recording.
                        let microphone =
                            AVCaptureDevice.default(
                                .microphone,
                                for: .audio,
                                position: .back
                            )
                            ?? AVCaptureDevice.default(for: .audio)
                    #else
                        let microphone = AVCaptureDevice.default(for: .audio)
                    #endif
                    guard let microphone else {
                        throw VideoNoteRecorderError.microphoneUnavailable
                    }
                    let microphoneInput = try AVCaptureDeviceInput(device: microphone)
                    guard session.canAddInput(microphoneInput) else {
                        throw VideoNoteRecorderError.configurationFailed
                    }
                    session.addInput(microphoneInput)

                    guard session.canAddOutput(movieOutput) else {
                        throw VideoNoteRecorderError.configurationFailed
                    }
                    session.addOutput(movieOutput)
                    movieOutput.maxRecordedDuration = CMTime(
                        seconds: VideoNoteStopPolicy.maximumCaptureDuration,
                        preferredTimescale: 600
                    )
                    session.commitConfiguration()
                    continuation.resume(
                        returning: CaptureGraph(
                            cameraInput: cameraInput,
                            microphoneInput: microphoneInput,
                            usesFrontCamera: camera.position == .front
                        ))
                } catch {
                    session.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startCaptureSession(generation: UUID) async throws {
        let session = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
        guard !Task.isCancelled,
            sessionGeneration == generation,
            session.isRunning
        else {
            throw CancellationError()
        }
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        @unknown default:
            return false
        }
    }
}

private actor VideoNoteFileInspector {
    struct Inspection: Sendable {
        let duration: TimeInterval
    }

    struct Finalization: Sendable {
        let url: URL
        let duration: TimeInterval
    }

    private struct Composition {
        let asset: AVAsset
        let videoTrack: AVMutableCompositionTrack
        let transform: CGAffineTransform
        let duration: TimeInterval
    }

    /// Hands the finished recording back for sending. The capture is
    /// already rotated to portrait at record time, so no re-encode is needed:
    /// the raw file is sent as-is and camera flips are merged with a
    /// passthrough export (audio and video stay bit-exact). On iOS, when the
    /// quiet front camera was used, the audio gets a deterministic volume
    /// boost (see boostFrontCameraAudio).
    func finalizeVideoNote(
        segments: [URL],
        frontCameraUsed: Bool
    ) async -> Finalization? {
        videoNoteFinalizeLogger.info(
            "finalize start segments=\(segments.count) front=\(frontCameraUsed)"
        )
        #if os(iOS)
            if frontCameraUsed, segments.count == 1 {
                if let boosted = await Self.boostFrontCameraAudio(
                    segment: segments[0]
                ) {
                    videoNoteFinalizeLogger.info("finalize boosted OK")
                    return boosted
                }
                videoNoteFinalizeLogger.info("finalize boost failed, raw")
            }
        #endif
        if segments.count == 1 {
            let duration =
                (try? await AVURLAsset(url: segments[0]).load(.duration)
                    .seconds) ?? 0
            videoNoteFinalizeLogger.info("finalize raw")
            return Finalization(url: segments[0], duration: max(0, duration))
        }
        videoNoteFinalizeLogger.info("finalize passthrough")
        return await Self.passthroughMerge(segments: segments)
    }

    /// Re-encodes a single segment with a fixed audio gain. The iOS front
    /// camera routes the quiet earpiece microphone, and the system offers no
    /// app-level way to override that routing — so the finished recording
    /// gets a deterministic volume boost instead. The video frames are
    /// copied verbatim (same dimensions and rotation transform); the audio
    /// goes through an AVAudioMix that applies the gain without manual
    /// sample math.
    private static func boostFrontCameraAudio(
        segment: URL
    ) async -> Finalization? {
        let asset = AVURLAsset(url: segment)
        guard
            let videoTrack = try? await asset.loadTracks(withMediaType: .video)
                .first,
            let audioTrack = try? await asset.loadTracks(withMediaType: .audio)
                .first,
            let duration = try? await asset.load(.duration)
        else { return nil }
        guard let outputURL = finalizationOutputURL() else { return nil }
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            return nil
        }
        let size = try? await videoTrack.load(.naturalSize)
        let width = max(1, Int(size?.width ?? 640))
        let height = max(1, Int(size?.height ?? 480))
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ]
        )
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else { return nil }
        writer.add(audioInput)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return nil
        }
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
        )
        guard reader.canAdd(videoOutput) else { return nil }
        reader.add(videoOutput)
        // The reader applies the gain via the audio mix.
        let mix = AVMutableAudioMix()
        let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
        parameters.setVolume(3.5, at: .zero)
        mix.inputParameters = [parameters]
        let audioOutput = AVAssetReaderAudioMixOutput(
            audioTracks: [audioTrack],
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM
            ]
        )
        audioOutput.audioMix = mix
        guard reader.canAdd(audioOutput) else { return nil }
        reader.add(audioOutput)

        guard reader.startReading() else { return nil }
        guard writer.startWriting() else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        guard let pool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        var sessionStarted = false
        var videoSample = videoOutput.copyNextSampleBuffer()
        var audioSample = audioOutput.copyNextSampleBuffer()
        while videoSample != nil || audioSample != nil {
            let videoPTS = videoSample.map {
                CMSampleBufferGetPresentationTimeStamp($0)
            }
            let audioPTS = audioSample.map {
                CMSampleBufferGetPresentationTimeStamp($0)
            }
            let takeVideo: Bool
            switch (videoPTS, audioPTS) {
            case let (video?, audio?): takeVideo = video <= audio
            case (_?, nil): takeVideo = true
            default: takeVideo = false
            }
            if takeVideo, let sample = videoSample {
                videoSample = videoOutput.copyNextSampleBuffer()
                guard let source = CMSampleBufferGetImageBuffer(sample)
                else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                if !sessionStarted {
                    writer.startSession(atSourceTime: pts)
                    sessionStarted = true
                }
                while !videoInput.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(
                    kCFAllocatorDefault, pool, &buffer
                )
                guard let buffer else { continue }
                CVPixelBufferLockBaseAddress(source, .readOnly)
                CVPixelBufferLockBaseAddress(buffer, [])
                let srcBase = CVPixelBufferGetBaseAddress(source)!
                let dstBase = CVPixelBufferGetBaseAddress(buffer)!
                let srcBytes = CVPixelBufferGetBytesPerRow(source)
                let dstBytes = CVPixelBufferGetBytesPerRow(buffer)
                let copyHeight = min(
                    CVPixelBufferGetHeight(source),
                    CVPixelBufferGetHeight(buffer)
                )
                let copyBytes = min(srcBytes, dstBytes)
                for row in 0..<copyHeight {
                    memcpy(
                        dstBase.advanced(by: row * dstBytes),
                        srcBase.advanced(by: row * srcBytes),
                        copyBytes
                    )
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                CVPixelBufferUnlockBaseAddress(source, .readOnly)
                guard adaptor.append(buffer, withPresentationTime: pts)
                else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    return nil
                }
            } else if let sample = audioSample {
                audioSample = audioOutput.copyNextSampleBuffer()
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                guard pts.isValid else { continue }
                while !audioInput.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
                guard audioInput.append(sample) else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    return nil
                }
            }
        }
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        let finishTask = Task { await writer.finishWriting() }
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if !Task.isCancelled {
                writer.cancelWriting()
            }
        }
        await finishTask.value
        watchdog.cancel()
        guard writer.status == .completed else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return Finalization(url: outputURL, duration: duration.seconds)
    }

    private static func composition(from urls: [URL]) async -> Composition? {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return nil }
        // The audio track is created lazily and only when a segment really
        // has audio. An empty audio track breaks the macOS exporter.
        var compositionAudioTrack: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        var transform = CGAffineTransform.identity
        var hasVideo = false
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard
                let duration = try? await asset.load(.duration),
                let source = try? await asset.loadTracks(withMediaType: .video)
                    .first
            else { return nil }
            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try videoTrack.insertTimeRange(range, of: source, at: cursor)
                if let audio = try? await asset.loadTracks(
                    withMediaType: .audio
                ).first {
                    if compositionAudioTrack == nil {
                        compositionAudioTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )
                    }
                    if let compositionAudioTrack {
                        try? compositionAudioTrack.insertTimeRange(
                            range,
                            of: audio,
                            at: cursor
                        )
                    }
                }
            } catch {
                return nil
            }
            if !hasVideo {
                transform = (try? await source.load(.preferredTransform)) ?? .identity
                hasVideo = true
            }
            cursor = cursor + duration
        }
        videoTrack.preferredTransform = transform
        return Composition(
            asset: composition,
            videoTrack: videoTrack,
            transform: transform,
            duration: cursor.seconds
        )
    }

    private static func passthroughMerge(
        segments: [URL]
    ) async -> Finalization? {
        guard let composition = await composition(from: segments) else {
            return nil
        }
        guard let outputURL = finalizationOutputURL() else { return nil }
        guard let exporter = AVAssetExportSession(
            asset: composition.asset,
            presetName: AVAssetExportPresetPassthrough
        ) else { return nil }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exporter.export(to: outputURL, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return Finalization(url: outputURL, duration: composition.duration)
    }

    private static func finalizationOutputURL() -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaRecordings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent(
                "video-note-final-\(UUID().uuidString).mov"
            )
        } catch {
            return nil
        }
    }

    func inspect(url: URL, fallbackDuration: TimeInterval) async -> Inspection? {
        let retryDelays: [UInt64] = [0, 120_000_000, 300_000_000]
        for delay in retryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let size = values.fileSize,
                size > 1_024
            else { continue }

            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration),
                duration.seconds.isFinite,
                duration.seconds > 0.04,
                let tracks = try? await asset.loadTracks(withMediaType: .video),
                !tracks.isEmpty
            else { continue }
            return Inspection(duration: duration.seconds)
        }

        // Keep a non-empty file only when AVFoundation reported enough wall
        // clock time to make a useful fallback. This branch covers a small set
        // of macOS camera drivers that delay movie metadata longer than the
        // delegate callback itself.
        guard fallbackDuration > 0.25,
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize,
            size > 16_384
        else { return nil }
        return Inspection(duration: fallbackDuration)
    }
}

enum VideoNoteStopPolicy {
    static let minimumCaptureDuration: TimeInterval = 1.2
    static let minimumValidFileDuration: TimeInterval = 0.8
    static let maximumCaptureDuration: TimeInterval = 60
    static let recordedDurationWaitTimeout: TimeInterval = 5
    static let recordedDurationPollNanoseconds: UInt64 = 80_000_000
    static let startupTimeoutNanoseconds: UInt64 = 6_000_000_000
    static let finalizationTimeoutNanoseconds: UInt64 = 12_000_000_000
    static let finalizationRecoveryGraceNanoseconds: UInt64 = 1_000_000_000

    static func remainingRecordedDuration(
        recordedDuration: TimeInterval,
        minimumDuration: TimeInterval
    ) -> TimeInterval {
        max(0, max(0, minimumDuration) - max(0, recordedDuration))
    }

    static func isValidFinalDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite && duration >= minimumValidFileDuration
    }
}

// #if os(iOS)
//     extension VideoNoteRecorder {
//         fileprivate static var currentVideoOrientation: AVCaptureVideoOrientation {
//             switch UIDevice.current.orientation {
//             case .portraitUpsideDown:
//                 return .portraitUpsideDown
//             case .landscapeLeft:
//                 return .landscapeRight
//             case .landscapeRight:
//                 return .landscapeLeft
//             default:
//                 return .portrait
//             }
//         }
//     }
// #endif

private enum VideoNoteRecorderError: LocalizedError {
    case cameraPermissionDenied
    case microphonePermissionDenied
    case cameraUnavailable
    case alternateCameraUnavailable
    case microphoneUnavailable
    case configurationFailed
    case notPrepared
    case recordingBusy
    case recordingInterrupted
    case finalizationTimedOut
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Разрешите Luma доступ к камере в системных настройках."
        case .microphonePermissionDenied:
            return "Разрешите Luma доступ к микрофону в системных настройках."
        case .cameraUnavailable:
            return "Камера недоступна."
        case .alternateCameraUnavailable:
            return "Вторая камера недоступна."
        case .microphoneUnavailable:
            return "Микрофон недоступен."
        case .configurationFailed:
            return "Не удалось настроить запись видеосообщения."
        case .notPrepared:
            return "Камера ещё не готова."
        case .recordingBusy:
            return "Предыдущая запись ещё завершается. Подождите секунду и повторите."
        case .recordingInterrupted:
            return
                "Камера прервала запись раньше времени. Видеосообщение не отправлено. Повторите запись."
        case .finalizationTimedOut:
            return "Камера не смогла завершить видеофайл. Повторите запись."
        case .emptyRecording:
            return "Камера создала пустой или нечитаемый видеофайл. Повторите запись."
        }
    }
}
