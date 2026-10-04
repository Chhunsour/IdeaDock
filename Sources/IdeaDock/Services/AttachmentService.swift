import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Owns copied images while leaving other files in their original locations.
@MainActor final class AttachmentService {
    static let maximumImageBytes = 50 * 1024 * 1024
    static let maximumImagePixels = 40_000_000
    static let maximumImageDimension = 16_000
    static let maximumImageFrames = 10_000

    private let store: IdeaStore
    private var scopedURLs: [String: URL] = [:]
    private let files = FileManager.default

    init(store: IdeaStore) { self.store = store }

    deinit {
        for url in scopedURLs.values { url.stopAccessingSecurityScopedResource() }
    }

    func fromFile(_ url: URL) throws -> Attachment {
        guard url.isFileURL else { throw AttachmentError.invalidFile }
        let requested = url.standardizedFileURL
        let access = requested.startAccessingSecurityScopedResource()
        defer { if access { requested.stopAccessingSecurityScopedResource() } }
        let source = requested.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard files.fileExists(atPath: source.path, isDirectory: &directory) else {
            throw AttachmentError.unavailable(source.lastPathComponent)
        }
        let values = try source.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
        guard directory.boolValue || values.isRegularFile == true else { throw AttachmentError.invalidFile }
        let type = values.contentType ?? UTType(filenameExtension: source.pathExtension)
        let count = Int64(values.fileSize ?? 0)
        if !directory.boolValue, type?.conforms(to: .image) == true {
            guard count <= Int64(Self.maximumImageBytes) else { throw AttachmentError.imageTooLarge }
            // ImageIO reads the header here, without allocating the full bitmap.
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw AttachmentError.invalidImage
            }
            try validateImage(imageSource)
            let attachment = Attachment(name: source.lastPathComponent, kind: "image", byteCount: count,
                                        typeDescription: type?.localizedDescription ?? "Image")
            let fileExtension = safeExtension(source.pathExtension, fallback: type?.preferredFilenameExtension ?? "img")
            let filename = "\(attachment.id.uuidString.lowercased()).\(fileExtension)"
            let destination = store.attachmentURL(filename)
            do {
                try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: source, to: destination)
            } catch {
                try? files.removeItem(at: destination)
                throw error
            }
            attachment.relativePath = filename
            return attachment
        }
        let bookmark = try makeBookmark(for: source)
        return Attachment(name: source.lastPathComponent, kind: "file", bookmark: bookmark,
                          originalPath: source.path, byteCount: count,
                          typeDescription: directory.boolValue ? "Folder" : (type?.localizedDescription ?? "File"))
    }

    func fromImage(_ image: NSImage, name: String = "Pasted image.png") throws -> Attachment {
        // Inspect existing representations before asking AppKit to render a bitmap.
        guard image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else { throw AttachmentError.invalidImage }
        guard image.size.width <= CGFloat(Self.maximumImageDimension), image.size.height <= CGFloat(Self.maximumImageDimension),
              image.size.width * image.size.height <= CGFloat(Self.maximumImagePixels) else { throw AttachmentError.imageTooLarge }
        for representation in image.representations {
            if representation.pixelsWide > 0, representation.pixelsHigh > 0 {
                try validateDimensions(width: representation.pixelsWide, height: representation.pixelsHigh)
            }
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw AttachmentError.invalidImage
        }
        try validateDimensions(width: cgImage.width, height: cgImage.height)
        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw AttachmentError.invalidImage
        }
        return try fromImageData(data, name: name)
    }

    /// Preserves the useful original PNG, JPEG, HEIC, GIF, or TIFF representation.
    func fromImageData(_ data: Data, name: String = "Pasted image.png") throws -> Attachment {
        guard data.count <= Self.maximumImageBytes else { throw AttachmentError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw AttachmentError.invalidImage
        }
        try validateImage(source)
        let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let fileExtension = safeExtension(type?.preferredFilenameExtension ?? "png", fallback: "png")
        let attachment = Attachment(name: name, kind: "image", byteCount: Int64(data.count),
                                    typeDescription: type?.localizedDescription ?? "Image")
        let filename = "\(attachment.id.uuidString.lowercased()).\(fileExtension)"
        let destination = store.attachmentURL(filename)
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        attachment.relativePath = filename
        return attachment
    }

    func clipboard(_ pasteboard: NSPasteboard = .general) throws -> (text: String, attachments: [Attachment]) {
        var attachments: [Attachment] = []
        var strings: [String] = []
        var seenFiles = Set<String>()
        do {
            if let items = pasteboard.pasteboardItems, !items.isEmpty {
                for item in items {
                    if let raw = item.string(forType: .fileURL), let url = URL(string: raw), url.isFileURL {
                        if seenFiles.insert(url.standardizedFileURL.path).inserted { attachments.append(try fromFile(url)) }
                        continue
                    }
                    if let imageType = preferredImageType(in: item.types), let data = item.data(forType: imageType) {
                        attachments.append(try fromImageData(data, name: "Pasted image.\(UTType(imageType.rawValue)?.preferredFilenameExtension ?? "png")"))
                        continue
                    }
                    if let link = item.string(forType: .URL), let url = URL(string: link) {
                        if url.isFileURL {
                            if seenFiles.insert(url.standardizedFileURL.path).inserted { attachments.append(try fromFile(url)) }
                        } else { strings.append(url.absoluteString) }
                    } else if let text = item.string(forType: .string), !text.isEmpty { strings.append(text) }
                }
            }
            // Older pasteboard writers expose a list rather than individual file items.
            if attachments.isEmpty, let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
                for path in paths where seenFiles.insert(path).inserted { attachments.append(try fromFile(URL(fileURLWithPath: path))) }
                if !attachments.isEmpty { strings = [] }
            }
            if attachments.isEmpty, strings.isEmpty {
                if let imageType = preferredImageType(in: pasteboard.types ?? []), let data = pasteboard.data(forType: imageType) {
                    attachments.append(try fromImageData(data))
                } else if let text = pasteboard.string(forType: .string) { strings.append(text) }
            }
            return (strings.joined(separator: "\n"), attachments)
        } catch {
            discard(attachments)
            throw error
        }
    }

    func url(for attachment: Attachment) throws -> URL {
        if attachment.relativePath != nil {
            guard let url = ownedImageURL(attachment) else { throw AttachmentError.invalidStoredImage }
            guard files.fileExists(atPath: url.path) else { throw AttachmentError.unavailable(attachment.name) }
            return url
        }
        var stale = false
        var bookmarkFailure: Error?
        var resolved: URL?
        if let bookmark = attachment.bookmark {
            do {
                resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            } catch {
                do {
                    resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                } catch { bookmarkFailure = error }
            }
        }
        if resolved == nil, let path = attachment.originalPath, !path.isEmpty { resolved = URL(fileURLWithPath: path) }
        guard let resolved, resolved.isFileURL else {
            if let bookmarkFailure { throw AttachmentError.referenceFailed(attachment.name, bookmarkFailure.localizedDescription) }
            throw AttachmentError.unavailable(attachment.name)
        }
        let url = resolved.standardizedFileURL
        // The UI may read this URL after returning. Hold granted access for the service's lifetime.
        if scopedURLs[url.path] == nil, url.startAccessingSecurityScopedResource() { scopedURLs[url.path] = url }
        guard files.fileExists(atPath: url.path) else { throw AttachmentError.unavailable(attachment.name) }
        if stale || attachment.originalPath != url.path || attachment.bookmark == nil {
            if let bookmark = try? makeBookmark(for: url) { attachment.bookmark = bookmark }
            attachment.originalPath = url.path
            if attachment.modelContext != nil { _ = store.save() }
        }
        return url
    }

    func open(_ attachment: Attachment) throws {
        let target = try url(for: attachment)
        guard NSWorkspace.shared.open(target) else { throw AttachmentError.openFailed(attachment.name) }
    }

    func reveal(_ attachment: Attachment) throws {
        NSWorkspace.shared.activateFileViewerSelecting([try url(for: attachment)])
    }

    /// Only app-owned images are removed; referenced originals are never deleted.
    func discard(_ attachments: [Attachment]) {
        for attachment in attachments {
            if let url = ownedImageURL(attachment) { try? files.removeItem(at: url) }
        }
    }

    private func ownedImageURL(_ attachment: Attachment) -> URL? {
        guard attachment.kind == "image", let path = attachment.relativePath,
              !path.isEmpty, path == (path as NSString).lastPathComponent,
              UUID(uuidString: (path as NSString).deletingPathExtension) == attachment.id else { return nil }
        return store.attachmentURL(path)
    }

    private func makeBookmark(for url: URL) throws -> Data {
        do { return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
    }

    private func validateImage(_ source: CGImageSource) throws {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw AttachmentError.invalidImage }
        guard count <= Self.maximumImageFrames else { throw AttachmentError.imageTooLarge }
        var totalFramePixels = 0
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw AttachmentError.invalidImage }
            let pixelsWide = width.intValue, pixelsHigh = height.intValue
            try validateDimensions(width: pixelsWide, height: pixelsHigh)
            guard pixelsWide <= (Self.maximumImagePixels - totalFramePixels) / pixelsHigh else {
                throw AttachmentError.imageTooLarge
            }
            totalFramePixels += pixelsWide * pixelsHigh
        }
    }

    private func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw AttachmentError.invalidImage }
        guard width <= Self.maximumImageDimension, height <= Self.maximumImageDimension,
              width <= Self.maximumImagePixels / height else { throw AttachmentError.imageTooLarge }
    }

    private func safeExtension(_ value: String, fallback: String) -> String {
        let lowered = value.lowercased()
        return !lowered.isEmpty && lowered.count <= 10 && lowered.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) ? lowered : fallback
    }

    private func preferredImageType(in types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType? {
        for preferred in [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier, UTType.gif.identifier] {
            if let match = types.first(where: { $0.rawValue == preferred }) { return match }
        }
        return types.first { UTType($0.rawValue)?.conforms(to: .image) == true }
    }
}

enum AttachmentError: LocalizedError {
    case invalidFile, invalidImage, imageTooLarge, invalidStoredImage
    case unavailable(String), referenceFailed(String, String), openFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Choose a file or folder on this Mac."
        case .invalidImage: return "This image could not be read. Try a PNG, JPEG, HEIC, GIF, or TIFF image."
        case .imageTooLarge: return "This image is too large to capture. Use an image smaller than 50 MB and 40 million total frame pixels."
        case .invalidStoredImage: return "This saved image has an invalid local path."
        case .unavailable(let name): return "“\(name)” is unavailable. It may have been moved, deleted, or stored on a disconnected drive. Attach it again to update the reference."
        case .referenceFailed(let name, let reason): return "The reference to “\(name)” could not be opened: \(reason)"
        case .openFailed(let name): return "macOS could not find an application to open “\(name)”."
        }
    }
}

extension AttachmentService {
    /// Formats raw byte sizes into human-readable strings (e.g., "4.2 MB").
    static func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
