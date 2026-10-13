import Foundation
import SwiftData

/// Codable representation of a single durable MAM checkpoint, keyed by the
/// archive it belongs to (account or a specific MUC).
struct MAMCheckpointEntry: Codable, Equatable, Sendable {
    let key: MAMArchiveKey
    let checkpoint: MAMArchiveCheckpoint
}

/// Singleton per-account metadata that used to live in the JSON snapshot:
/// locally deleted message IDs, roster contact JIDs and MAM checkpoints.
@Model
final class ArchiveMetadata {
    @Attribute(.unique) var accountJID: String
    var locallyDeletedMessageIDs: [String]
    var rosterContactJIDs: [String]
    var lastSuccessfulMAMSync: Date?
    var lastSuccessfulMAMCursor: String?
    var mamCheckpoints: [MAMCheckpointEntry]

    init(
        accountJID: String,
        locallyDeletedMessageIDs: [String] = [],
        rosterContactJIDs: [String] = [],
        lastSuccessfulMAMSync: Date? = nil,
        lastSuccessfulMAMCursor: String? = nil,
        mamCheckpoints: [MAMCheckpointEntry] = []
    ) {
        self.accountJID = accountJID
        self.locallyDeletedMessageIDs = locallyDeletedMessageIDs
        self.rosterContactJIDs = rosterContactJIDs
        self.lastSuccessfulMAMSync = lastSuccessfulMAMSync
        self.lastSuccessfulMAMCursor = lastSuccessfulMAMCursor
        self.mamCheckpoints = mamCheckpoints
    }
}
