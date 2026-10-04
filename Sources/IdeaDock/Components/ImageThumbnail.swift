import AppKit
import ImageIO
import SwiftUI

/// Small previews for the library and capture strip. Image files use immutable UUID paths.
@MainActor struct ImageThumbnail: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    @ViewState private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.primary.opacity(0.045)
                    Image(systemName: "photo").font(.system(size: 15, weight: .light)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
        .task(id: url.path) { image = ThumbnailCache.image(at: url) }
    }
}

@MainActor private enum ThumbnailCache {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL) -> NSImage? {
        guard url.isFileURL else { return nil }
        let key = url.standardizedFileURL.path as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: CGFloat(thumbnail.width), height: CGFloat(thumbnail.height)))
        images.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}
