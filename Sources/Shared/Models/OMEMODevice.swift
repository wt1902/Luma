import Foundation

struct OMEMODevice: Identifiable, Hashable, Sendable {
    enum Trust: String, Sendable {
        case undecided
        case trusted
        case verified
        case compromised
    }

    let jid: String
    let deviceID: Int32
    let fingerprint: String
    let trust: Trust
    let isActive: Bool
    let isOwn: Bool
    let isOMEMO2: Bool

    var id: String { "\(jid)|\(deviceID)|\(isOMEMO2 ? "omemo2" : "legacy")" }

    /// Short protocol label for the encryption screen badge.
    var protocolName: String {
        isOMEMO2 ? "OMEMO 2" : "OMEMO"
    }

    var formattedFingerprint: String {
        fingerprint.chunked(every: 8).joined(separator: " ")
    }
}

private extension String {
    func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}

