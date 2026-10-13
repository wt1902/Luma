import Foundation

/// Keeps MAM work below a visible frame-sized burst. A whole decoded pass is
/// still published atomically; these values only bound network and decryption
/// work performed before that publication.
enum ArchiveMessageBatchPolicy {
    static let pageSize = 40
    static let bootstrapMessageLimit = 40
    /// Decrypt this many archived stanzas per main-actor slice before yielding.
    /// One-by-one decryption turns a large MAM catch-up into hours of serialized
    /// work; a small batch keeps frames mostly intact while cutting the number
    /// of run-loop hand-offs by the same factor.
    static let decodeSliceSize = 8
    static let maximumBufferedStanzas = 96
    /// A short yield between archived decryption slices keeps touch handling
    /// responsive without the 8 ms per single message that previously dominated
    /// catch-up time.
    static let interSliceDelayNanoseconds: UInt64 = 1_000_000
}
