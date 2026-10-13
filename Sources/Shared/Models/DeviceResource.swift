import Foundation

/// Stable, per-installation XMPP resource. Two devices that both fall back to
/// the default must never share a resource: an XMPP server resolves a resource
/// collision with a `conflict` stream error, which disconnects the older
/// session. A UUID persisted in UserDefaults keeps the value stable across
/// launches (so presence and stream-management resume stay consistent) while
/// remaining distinct between macOS and iOS installs.
enum DeviceResource {
    /// The legacy hard-coded default that older Luma builds sent from every
    /// device. Treated as "automatic" so existing accounts migrate without the
    /// user having to re-enter credentials.
    static let legacyDefault = "Luma"

    private static let storageKey = "app.luma.xmpp.resource"

    static var `default`: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
            .lowercased()
        let resource = "Luma-\(suffix)"
        defaults.set(resource, forKey: storageKey)
        return resource
    }
}
