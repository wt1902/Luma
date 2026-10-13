import Foundation

#if os(iOS)
import UIKit
typealias ChatMediaPlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias ChatMediaPlatformImage = NSImage
#endif

/// SwiftUI can evaluate every visible bubble repeatedly during scrolling.
/// Keep decoded thumbnails in a bounded native-image cache so those passes do
/// not repeatedly decompress JPEG/HEIC data on the main actor.
@MainActor
enum ChatMediaImageCache {
    private static let cache: NSCache<NSString, ChatMediaPlatformImage> = {
        let cache = NSCache<NSString, ChatMediaPlatformImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    static func image(
        for message: ChatMessage,
        data: Data
    ) -> ChatMediaPlatformImage? {
        let cacheKey = "\(message.conversationID)\u{1F}\(message.clientID)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        guard let image = ChatMediaPlatformImage(data: data) else { return nil }
        cache.setObject(image, forKey: cacheKey, cost: data.count)
        return image
    }
}
