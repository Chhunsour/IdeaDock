import Foundation
import Darwin
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// The JSON format is a versioned, portable library merge. Owned images are embedded;
/// external file references keep their bookmark and original location without copying bytes.
@MainActor enum ExportService {
    enum ExportError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }

    private struct Library: Codable {
        var format = "IdeaDock"
        var version = 1
        var exportedAt = Date.now
        var categories: [CategoryRecord]
        var ideas: [IdeaRecord]
    }
    private struct CategoryRecord: Codable {
        var id: UUID
        var name: String
        var icon: String
        var accent: String
        var sortOrder: Int
        var isInbox: Bool
        init(_ category: IdeaCategory) {
            id = category.id; name = category.name; icon = category.icon; accent = category.accent
            sortOrder = category.sortOrder; isInbox = category.isInbox
        }
    }
    private struct IdeaRecord: Codable {
        var id: UUID
        var title: String
        var content: String
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool
        var isFavorite: Bool
        var isArchived: Bool
        var categoryID: UUID
        var tags: [String]
        var contentType: String
        var sourceURL: String?
        var sortOrder: Double
        var attachments: [AttachmentRecord]
        init(_ idea: Idea, attachments: [AttachmentRecord]) {
            id = idea.id; title = idea.title; content = idea.content; createdAt = idea.createdAt
            updatedAt = idea.updatedAt; isPinned = idea.isPinned; isFavorite = idea.isFavorite
            isArchived = idea.isArchived; categoryID = idea.categoryID; tags = idea.tags
            contentType = idea.contentType; sourceURL = idea.sourceURL; sortOrder = idea.sortOrder
            self.attachments = attachments
        }
    }
    private struct AttachmentRecord: Codable {
        var id: UUID
        var name: String
        var kind: String
        var relativePath: String?
        var bookmark: Data?
        var originalPath: String?
        var byteCount: Int64
        var typeDescription: String
        var imageData: Data?
        init(_ attachment: Attachment, imageData: Data?) {
            id = attachment.id; name = attachment.name; kind = attachment.kind
            relativePath = attachment.relativePath; bookmark = attachment.bookmark
            originalPath = attachment.originalPath; byteCount = attachment.byteCount
            typeDescription = attachment.typeDescription; self.imageData = imageData
        }
    }

    private static let imageLimit = 50 * 1024 * 1024
    private static let aggregateImageLimit = 250 * 1024 * 1024
    private static let documentLimit = 400 * 1024 * 1024

    static func exportJSON(store: IdeaStore, to destination: URL) throws {
        guard destination.isFileURL else { throw ExportError.invalid("Choose a local file for your JSON backup.") }
        let library = try snapshot(store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(library)
        guard data.count <= documentLimit else { throw ExportError.invalid("This library exceeds the 400 MB JSON backup limit. Export smaller libraries separately.") }
        try data.write(to: destination, options: .atomic)
    }

    static func exportMarkdown(store: IdeaStore, to destination: URL) throws {
        guard destination.isFileURL else { throw ExportError.invalid("Choose a local folder for Markdown export.") }
        let library = try snapshot(store)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else {
            throw ExportError.invalid("Choose a new folder for Markdown export. Existing folders are kept intact.")
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".IdeaDock-export-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging.appendingPathComponent("ideas"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        try manager.createDirectory(at: staging.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        var index = "# IdeaDock Library\n\nExported \(dateText(library.exportedAt)).\n\n"
        for category in library.categories.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            index += "## \(oneLine(category.name))\n\n"
            for idea in library.ideas.filter({ $0.categoryID == category.id }).sorted(by: { $0.createdAt > $1.createdAt }) {
                index += "- [\(markdownLabel(idea.title))](ideas/\(idea.id.uuidString.lowercased()).md)"
                if idea.isArchived { index += " — archived" }
                if idea.isPinned { index += " · pinned" }
                if idea.isFavorite { index += " · favorite" }
                index += "\n"
                var document = "# \(oneLine(idea.title))\n\n"
                document += "- Category: \(oneLine(category.name))\n- Created: \(dateText(idea.createdAt))\n- Updated: \(dateText(idea.updatedAt))\n"
                document += "- Type: \(idea.contentType)\n- Tags: \(idea.tags.map { "#" + $0 }.joined(separator: ", "))\n"
                document += "- Pinned: \(idea.isPinned) · Favorite: \(idea.isFavorite) · Archived: \(idea.isArchived)\n"
                document += "- ID: \(idea.id.uuidString)\n\n\(idea.content)\n"
                if !idea.attachments.isEmpty { document += "\n## Attachments\n\n" }
                for attachment in idea.attachments {
                    if let data = attachment.imageData, let path = attachment.relativePath {
                        try data.write(to: staging.appendingPathComponent("attachments").appendingPathComponent(path), options: .atomic)
                        document += "![\(markdownLabel(attachment.name))](../attachments/\(path))\n\n"
                    } else if let path = attachment.originalPath {
                        let link = URL(fileURLWithPath: path).absoluteString
                        document += "- [\(markdownLabel(attachment.name))](<\(link)>) — external reference; keep the original file.\n"
                    } else {
                        document += "- \(oneLine(attachment.name)) — external reference; original location unavailable.\n"
                    }
                }
                try document.write(to: staging.appendingPathComponent("ideas").appendingPathComponent("\(idea.id.uuidString.lowercased()).md"), atomically: true, encoding: .utf8)
            }
            index += "\n"
        }
        index += "Owned image attachments are included. Referenced files and folders remain at their original locations. Use a JSON export to restore a library in IdeaDock.\n"
        try index.write(to: staging.appendingPathComponent("Library.md"), atomically: true, encoding: .utf8)
        try manager.moveItem(at: staging, to: destination)
    }

    /// Returns the number of new ideas. Existing IDs are skipped; existing data is never overwritten.
    static func importJSON(store: IdeaStore, from source: URL) throws -> Int {
        guard source.isFileURL else { throw ExportError.invalid("Choose a local IdeaDock JSON backup.") }
        let properties = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true, let size = properties.fileSize, size <= documentLimit else {
            throw ExportError.invalid("Choose an IdeaDock JSON backup smaller than 400 MB.")
        }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count <= documentLimit else { throw ExportError.invalid("The JSON backup exceeds 400 MB.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let library: Library
        do { library = try decoder.decode(Library.self, from: data) }
        catch { throw ExportError.invalid("This file is not a valid IdeaDock JSON backup: \(error.localizedDescription)") }
        try validate(library)
        let existingIdeaIDs = Set(store.ideas.map(\.id))
        let newRecords = library.ideas.filter { !existingIdeaIDs.contains($0.id) }
        let existingAttachments = Set(store.ideas.flatMap { $0.attachments.map(\.id) })
        guard newRecords.flatMap(\.attachments).allSatisfy({ !existingAttachments.contains($0.id) }) else {
            throw ExportError.invalid("An imported attachment ID is already used by a different idea. Nothing was imported.")
        }
        let existingCategories = Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0) })
        var mapping: [UUID: UUID] = [:]
        var categoriesToInsert: [CategoryRecord] = []
        for category in library.categories {
            if category.isInbox { mapping[category.id] = store.inboxID }
            else if let existing = existingCategories[category.id] {
                guard !existing.isInbox else { throw ExportError.invalid("An imported category conflicts with the local Inbox. Nothing was imported.") }
                mapping[category.id] = existing.id
            } else {
                mapping[category.id] = category.id; categoriesToInsert.append(category)
            }
        }
        // Flush current UI edits before starting the import transaction, so rollback
        // can never discard an unrelated unsaved edit.
        try store.context.save()
        let manager = FileManager.default
        var copiedFiles: [URL] = []
        do {
            for category in categoriesToInsert {
                let model = IdeaCategory(name: category.name, icon: category.icon, accent: category.accent, sortOrder: category.sortOrder)
                model.id = category.id; store.context.insert(model)
            }
            for record in newRecords {
                var attachments: [Attachment] = []
                for item in record.attachments {
                    if let bytes = item.imageData, let path = item.relativePath {
                        let target = store.attachmentURL(path)
                        guard !manager.fileExists(atPath: target.path) else {
                            throw ExportError.invalid("An attachment file already exists at \(path). Nothing was imported.")
                        }
                        try installImage(bytes, at: target)
                        copiedFiles.append(target)
                    }
                    let model = Attachment(name: item.name, kind: item.kind, relativePath: item.relativePath, bookmark: item.bookmark, originalPath: item.originalPath, byteCount: item.byteCount, typeDescription: item.typeDescription)
                    model.id = item.id; attachments.append(model)
                }
                let idea = Idea(content: record.content, categoryID: mapping[record.categoryID]!, title: record.title, attachments: attachments)
                idea.id = record.id; idea.createdAt = record.createdAt; idea.updatedAt = record.updatedAt
                idea.isPinned = record.isPinned; idea.isFavorite = record.isFavorite; idea.isArchived = record.isArchived
                idea.tags = record.tags; idea.contentType = record.contentType; idea.sourceURL = record.sourceURL; idea.sortOrder = record.sortOrder
                store.context.insert(idea)
            }
            // Fetch includes pending inserts. Do the potentially throwing refresh
            // before committing, so any error can still roll back the whole merge.
            try store.reload()
            try store.context.save()
        } catch {
            store.context.rollback()
            for file in copiedFiles { try? manager.removeItem(at: file) }
            try? store.reload()
            throw error
        }
        return newRecords.count
    }

    private static func snapshot(_ store: IdeaStore) throws -> Library {
        var total = 0
        var records: [IdeaRecord] = []
        for idea in store.ideas {
            var attachments: [AttachmentRecord] = []
            for attachment in idea.attachments {
                var data: Data?
                if let path = attachment.relativePath {
                    try validateOwnedPath(path, attachmentID: attachment.id)
                    let source = store.attachmentURL(path)
                    let root = store.root.appendingPathComponent("Attachments").resolvingSymlinksInPath().standardizedFileURL.path + "/"
                    guard source.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else {
                        throw ExportError.invalid("An image attachment points outside this library.")
                    }
                    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true, let count = values.fileSize, count <= imageLimit else {
                        throw ExportError.invalid("An image is missing, invalid, or exceeds the 50 MB attachment limit: \(attachment.name).")
                    }
                    data = try Data(contentsOf: source)
                    total += data!.count
                    guard total <= aggregateImageLimit else { throw ExportError.invalid("Owned images exceed the 250 MB backup limit.") }
                }
                attachments.append(AttachmentRecord(attachment, imageData: data))
            }
            records.append(IdeaRecord(idea, attachments: attachments))
        }
        let library = Library(categories: store.categories.map(CategoryRecord.init), ideas: records)
        try validate(library)
        return library
    }

    private static func validate(_ library: Library) throws {
        guard library.format == "IdeaDock", library.version == 1 else { throw ExportError.invalid("This backup uses an unsupported format or version.") }
        guard library.categories.count <= 10_000, library.ideas.count <= 100_000 else { throw ExportError.invalid("This backup contains too many categories or ideas.") }
        guard library.categories.filter(\.isInbox).count == 1 else { throw ExportError.invalid("A backup must contain exactly one Inbox category.") }
        var categoryIDs = Set<UUID>()
        for category in library.categories {
            guard categoryIDs.insert(category.id).inserted else { throw ExportError.invalid("This backup contains duplicate category IDs.") }
            try boundedText(category.name, limit: 1_024, label: "category name")
            try boundedText(category.icon, limit: 256, label: "category icon")
            try boundedText(category.accent, limit: 256, label: "category accent")
            guard !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ExportError.invalid("An imported category has an empty name.") }
            guard category.sortOrder >= 0, category.sortOrder <= 1_000_000,
                  category.isInbox ? category.sortOrder == 0 : category.sortOrder > 0 else {
                throw ExportError.invalid("An imported category has an invalid order. Inbox must remain first.")
            }
        }
        var ideaIDs = Set<UUID>(); var attachmentIDs = Set<UUID>(); var total = 0
        for idea in library.ideas {
            guard ideaIDs.insert(idea.id).inserted, categoryIDs.contains(idea.categoryID) else { throw ExportError.invalid("This backup has duplicate ideas or an unknown category reference.") }
            try boundedText(idea.title, limit: 100_000, label: "idea title")
            try boundedText(idea.content, limit: 5 * 1024 * 1024, label: "idea content")
            guard ContentKind(rawValue: idea.contentType) != nil, idea.sortOrder.isFinite,
                  abs(idea.createdAt.timeIntervalSince1970) < 1_000_000_000_000,
                  abs(idea.updatedAt.timeIntervalSince1970) < 1_000_000_000_000,
                  idea.tags.count <= 1_000, idea.attachments.count <= 1_000 else { throw ExportError.invalid("An idea has invalid metadata or exceeds import limits.") }
            for tag in idea.tags { try boundedText(tag, limit: 256, label: "tag") }
            if let url = idea.sourceURL {
                try boundedText(url, limit: 16_384, label: "source URL")
                guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
                      parsed.host?.isEmpty == false else { throw ExportError.invalid("An idea has an invalid source URL.") }
            }
            for item in idea.attachments {
                guard attachmentIDs.insert(item.id).inserted, ["image", "file", "folder"].contains(item.kind), item.byteCount >= 0 else { throw ExportError.invalid("This backup contains invalid or duplicate attachment metadata.") }
                try boundedText(item.name, limit: 1_024, label: "attachment name")
                try boundedText(item.typeDescription, limit: 1_024, label: "attachment type")
                if let path = item.originalPath {
                    try boundedText(path, limit: 16_384, label: "external path")
                    guard (path as NSString).isAbsolutePath else { throw ExportError.invalid("An external attachment must use an absolute original path.") }
                }
                guard (item.bookmark?.count ?? 0) <= 1024 * 1024 else { throw ExportError.invalid("An external bookmark exceeds 1 MB.") }
                if let path = item.relativePath {
                    try validateOwnedPath(path, attachmentID: item.id)
                    guard item.kind == "image", let bytes = item.imageData, bytes.count == item.byteCount,
                          item.originalPath == nil, item.bookmark == nil else { throw ExportError.invalid("An owned image has incomplete or conflicting attachment data.") }
                    try validateImage(bytes)
                    total += bytes.count
                    guard total <= aggregateImageLimit else { throw ExportError.invalid("Owned images exceed the 250 MB backup limit.") }
                } else {
                    guard item.imageData == nil, item.bookmark != nil || item.originalPath != nil else {
                        throw ExportError.invalid("An external attachment contains embedded bytes or has no original reference.")
                    }
                }
            }
        }
    }
    private static func validateOwnedPath(_ path: String, attachmentID: UUID) throws {
        let url = URL(fileURLWithPath: path)
        let suffix = url.pathExtension
        guard path.utf8.count <= 100, !path.contains("/"), !path.contains("\\"), !path.contains(":"),
              !suffix.isEmpty, suffix.utf8.count <= 12,
              suffix.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }),
              UTType(filenameExtension: suffix)?.conforms(to: .image) == true,
              url.deletingPathExtension().lastPathComponent.lowercased() == attachmentID.uuidString.lowercased() else {
            throw ExportError.invalid("An image attachment has an unsafe filename.")
        }
        try boundedText(path, limit: 100, label: "image filename")
    }
    private static func installImage(_ bytes: Data, at target: URL) throws {
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".IdeaDock-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .atomic)
        // Both paths are on the library's volume. An exclusive hard link installs
        // the complete file atomically and cannot replace a file created by a race.
        // The temporary link is then removed, leaving an ordinary owned image.
        let result = temporary.path.withCString { source in target.path.withCString { destination in Darwin.link(source, destination) } }
        guard result == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: target.path])
        }
    }
    private static func validateImage(_ data: Data) throws {
        guard !data.isEmpty, data.count <= imageLimit,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, CGImageSourceGetCount(source) <= 10_000 else {
            throw ExportError.invalid("An embedded image is invalid or exceeds the 50 MB / 40 megapixel import limit.")
        }
        // Validate every frame's header so an animated image cannot hide an
        // excessive dimension behind a valid first frame.
        var remainingPixels = 40_000_000
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.intValue > 0, height.intValue > 0,
                  width.intValue <= 16_000, height.intValue <= 16_000,
                  width.intValue <= remainingPixels / height.intValue else {
                throw ExportError.invalid("An embedded image is invalid or exceeds 50 MB / 40 million total frame pixels.")
            }
            remainingPixels -= width.intValue * height.intValue
        }
        guard CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else {
            throw ExportError.invalid("An embedded image could not be decoded.")
        }
    }
    private static func boundedText(_ value: String, limit: Int, label: String) throws {
        guard value.utf8.count <= limit, !value.contains("\0") else { throw ExportError.invalid("An imported \(label) exceeds its limit or contains invalid characters.") }
    }
    private static func oneLine(_ value: String) -> String { value.components(separatedBy: .newlines).joined(separator: " ") }
    private static func markdownLabel(_ value: String) -> String {
        oneLine(value).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
    private static func dateText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
