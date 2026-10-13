import Foundation

/// A MAM UID is only meaningful inside one archive. Account MAM and every MUC
/// therefore get their own namespace and durable checkpoint.
struct MAMArchiveKey: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case account
        case muc
    }

    let kind: Kind
    let jid: String

    init(kind: Kind, jid: String) {
        self.kind = kind
        self.jid = jid.lowercased()
    }

    static func account(_ jid: String) -> Self {
        Self(kind: .account, jid: jid)
    }

    static func muc(_ jid: String) -> Self {
        Self(kind: .muc, jid: jid)
    }
}

struct MAMArchiveCheckpoint: Codable, Equatable, Sendable {
    let timestamp: Date
    let cursor: String?

    init(timestamp: Date, cursor: String? = nil) {
        self.timestamp = timestamp
        self.cursor = ArchiveSyncCheckpoint.normalizedCursor(cursor)
    }
}

/// Durable MAM position. The archive UID is the primary synchronization
/// anchor; the timestamp is retained as a compatibility fallback for legacy
/// snapshots and servers that have expired an old UID.
struct ArchiveSyncCheckpoint: Codable, Equatable, Sendable {
    let timestamp: Date
    let cursor: String?

    init(timestamp: Date, cursor: String? = nil) {
        self.timestamp = timestamp
        self.cursor = Self.normalizedCursor(cursor)
    }

    func advances(over previous: ArchiveSyncCheckpoint?) -> Bool {
        guard let previous else { return true }
        return timestamp > previous.timestamp || cursor != previous.cursor
    }

    static func normalizedCursor(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

struct ArchiveSyncRequestPosition: Equatable, Sendable {
    let start: Date?
    let after: String?
}

/// Keeps cursor-based catch-up and the timestamp fallback deterministic and
/// independently testable from Martin's callback lifecycle.
enum ArchiveSyncCursorPolicy {
    static func requestPosition(
        checkpoint: ArchiveSyncCheckpoint?,
        resumeAfter: String?,
        overlap: TimeInterval
    ) -> ArchiveSyncRequestPosition {
        let after = ArchiveSyncCheckpoint.normalizedCursor(resumeAfter)
            ?? checkpoint?.cursor
        if let after {
            return ArchiveSyncRequestPosition(start: nil, after: after)
        }
        return ArchiveSyncRequestPosition(
            start: checkpoint?.timestamp.addingTimeInterval(-overlap),
            after: nil
        )
    }

    static func resolvedCheckpoint(
        previous: ArchiveSyncCheckpoint?,
        cursor: String?,
        highWatermark: Date?,
        queryStartedAt: Date,
        caughtUp: Bool
    ) -> ArchiveSyncCheckpoint {
        let previousTimestamp = previous?.timestamp ?? .distantPast
        let boundedHighWatermark = min(highWatermark ?? previousTimestamp, queryStartedAt)
        let timestamp = caughtUp
            ? max(previousTimestamp, queryStartedAt)
            : max(previousTimestamp, boundedHighWatermark)
        return ArchiveSyncCheckpoint(
            timestamp: timestamp,
            cursor: ArchiveSyncCheckpoint.normalizedCursor(cursor) ?? previous?.cursor
        )
    }

    static func shouldFallbackFromStoredCursor(
        requestedAfter: String?,
        checkpoint: ArchiveSyncCheckpoint?,
        hasCompletedPage: Bool,
        fallbackAlreadyUsed: Bool
    ) -> Bool {
        guard !fallbackAlreadyUsed,
              !hasCompletedPage,
              let requestedAfter = ArchiveSyncCheckpoint.normalizedCursor(requestedAfter),
              requestedAfter == checkpoint?.cursor else { return false }
        return true
    }
}
