import AppKit
import UniformTypeIdentifiers

@MainActor enum DropReader {
    /// Reads one preferred representation per item, then creates models on the main actor.
    static func read(_ providers: [NSItemProvider], service: AttachmentService,
                     completion: @escaping (String, [Attachment], String?) -> Void) {
        Task { @MainActor in
            var texts: [String] = []
            var attachments: [Attachment] = []
            var errors: [String] = []
            var seenFiles = Set<String>()
            for provider in providers {
                do {
                    let value = try await read(provider)
                    switch value {
                    case .file(let url):
                        if seenFiles.insert(url.standardizedFileURL.path).inserted { attachments.append(try service.fromFile(url)) }
                    case .image(let data, let name): attachments.append(try service.fromImageData(data, name: name))
                    case .renderedImage(let image, let name): attachments.append(try service.fromImage(image, name: name))
                    case .text(let text): if !text.isEmpty { texts.append(text) }
                    }
                } catch {
                    let message = error.localizedDescription
                    if !errors.contains(message) { errors.append(message) }
                }
            }
            completion(texts.joined(separator: "\n"), attachments, errors.isEmpty ? nil : errors.joined(separator: "\n"))
        }
    }

    private enum Value {
        case file(URL)
        case image(Data, String)
        case renderedImage(NSImage, String)
        case text(String)
    }

    private static func read(_ provider: NSItemProvider) async throws -> Value {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let value = try await item(from: provider, type: UTType.fileURL.identifier)
            guard let url = itemURL(value), url.isFileURL else { throw DropError.unreadableFile }
            return .file(url)
        }
        let imageTypes = provider.registeredTypeIdentifiers.filter { UTType($0)?.conforms(to: .image) == true }
        if !imageTypes.isEmpty {
            let preferences = [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier, UTType.gif.identifier]
            let chosen = preferences.first(where: imageTypes.contains) ?? imageTypes[0]
            let name = provider.suggestedName ?? "Dropped image.\(UTType(chosen)?.preferredFilenameExtension ?? "png")"
            do { return .image(try await data(from: provider, type: chosen), name) }
            catch {
                if provider.canLoadObject(ofClass: NSImage.self) { return .renderedImage(try await image(from: provider), name) }
                throw error
            }
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            return .renderedImage(try await image(from: provider), provider.suggestedName ?? "Dropped image.png")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let value = try await item(from: provider, type: UTType.url.identifier)
            guard let url = itemURL(value) else { throw DropError.unreadableLink }
            return url.isFileURL ? .file(url) : .text(url.absoluteString)
        }
        for type in [UTType.utf8PlainText.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
            let value = try await item(from: provider, type: type)
            if let string = value as? String { return .text(string) }
            if let data = value as? Data {
                if let string = String(data: data, encoding: .utf8) { return .text(string) }
                if let string = String(data: data, encoding: .utf16) { return .text(string) }
            }
            throw DropError.unreadableText
        }
        throw DropError.unsupported
    }

    private static func itemURL(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let string = item as? String { return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let data = item as? Data {
            if let string = String(data: data, encoding: .utf8) { return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        return nil
    }

    private static func item(from provider: NSItemProvider, type: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: item) }
            }
        }
    }

    private static func data(from provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? DropError.unreadableImage) }
            }
        }
    }

    private static func image(from provider: NSItemProvider) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { object, error in
                if let image = object as? NSImage { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? DropError.unreadableImage) }
            }
        }
    }
}

private enum DropError: LocalizedError {
    case unreadableFile, unreadableImage, unreadableLink, unreadableText, unsupported
    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "The dropped file reference could not be read."
        case .unreadableImage: return "The dropped image could not be read."
        case .unreadableLink: return "The dropped link could not be read."
        case .unreadableText: return "The dropped text could not be read."
        case .unsupported: return "Drop text, a link, an image, or a file to capture it."
        }
    }
}
