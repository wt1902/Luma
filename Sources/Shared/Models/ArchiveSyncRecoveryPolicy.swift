import Foundation

/// Bounds whole-query MAM recovery so a server that keeps returning the same
/// broken page cannot leave the client in an endless restart loop.
enum ArchiveSyncRecoveryPolicy {
    static let incrementalOverlap: TimeInterval = 60
    static let interPageDelayNanoseconds: UInt64 = 100_000_000
    static let queryTimeoutNanoseconds: UInt64 = 20_000_000_000
    static let pageApplyTimeoutNanoseconds: UInt64 = 20_000_000_000
    static let pageRetryLimit = 1
    static let resumeAfterCaptureDelayNanoseconds: UInt64 = 3_000_000_000
    /// Delay before automatically resuming a failed catch-up pass while the
    /// app stays connected and foregrounded. Prevents a single slow page from
    /// silently leaving history unloaded until the next app activation.
    static let retryAfterFailureDelayNanoseconds: UInt64 = 20_000_000_000
    /// Consecutive automatic catch-up retries before falling back to
    /// resume-on-activation, so a persistently broken server cannot loop.
    static let maximumAutomaticRetries = 3
}
