import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Uses temporary on-disk libraries. This mode never opens the user's library,
/// watches the clipboard, registers a shortcut, or starts the application UI.
@MainActor enum SelfTests {
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func run() -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IdeaDock-tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try exercise(root: root)
            print("PASS: all IdeaDock self-tests (temporary on-disk libraries; no user library access)")
            return 0
        } catch {
            print("FAIL: \(error.localizedDescription)")
            return 1
        }
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message: message) }
    }
    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure(message: message) }; return value
    }
    private static func exercise(root: URL) throws {
        try dockingGeometryTests()
        try captureHistoryTests(root: root)
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("destination", isDirectory: true)
        let backup = root.appendingPathComponent("backup.json")
        let markdown = root.appendingPathComponent("Markdown", isDirectory: true)
        var noteID = UUID(); var photoID = UUID(); var categoryID = UUID(); var imageID = UUID()
        var linkID = UUID(); var externalAttachmentID = UUID(); var imageTypeDescription = ""
        var externalIdeaID = UUID()
        var categoryOrder = 0
        let originalDate = Date(timeIntervalSince1970: 1_735_689_600.125)
        let png = try imageFixture()
        let externalURL = root.appendingPathComponent("Do not duplicate.txt")
        try "The original stays here.".write(to: externalURL, atomically: true, encoding: .utf8)
        do {
            let store = try IdeaStore(root: sourceRoot)
            try expect(store.categories.filter(\.isInbox).count == 1, "Store must start with exactly one Inbox")
            try expect(store.create("   \n") == nil, "An empty capture must not create an idea")
            let originalCount = store.categories.count
            store.addCategory("Roundtrip", icon: "lightbulb", accent: "purple")
            let category = try require(store.categories.first { $0.name == "Roundtrip" }, "Category creation failed")
            categoryID = category.id
            try expect(store.categories.count == originalCount + 1, "Category must persist")
            store.moveCategory(category, offset: -1)
            try expect(category.sortOrder == originalCount - 1, "Category ordering failed")
            categoryOrder = category.sortOrder
            let note = try require(store.create("Offline plan #launch #swift\nBuild a quieter workspace.", categoryID: category.id), "Text capture failed")
            noteID = note.id
            try expect(note.tags == ["launch", "swift"], "Hashtag extraction must be sorted and unique")
            note.isPinned = true; note.isFavorite = true; note.title = "Edited offline plan"
            note.content += "\nA persisted edit."; store.changed(note)
            try expect(store.filtered(scope: .pinned, query: "", kind: nil).contains { $0.id == noteID }, "Pinned filter failed")
            try expect(store.filtered(scope: .favorites, query: "", kind: nil).contains { $0.id == noteID }, "Favorite filter failed")
            try expect(store.filtered(scope: .category(category.id), query: "tag:launch category:roundtrip quieter", kind: .text).contains { $0.id == noteID }, "Combined tag/category/text search failed")
            try expect(store.filtered(scope: .recent, query: "definitely absent", kind: nil).isEmpty, "Search returned an unrelated idea")
            let link = try require(store.create("Useful link https://example.com/document #reading"), "Link capture failed")
            linkID = link.id
            try expect(link.kind == .link && link.sourceURL == "https://example.com/document", "URL detection failed")
            try expect(store.filtered(scope: .links, query: "type:link", kind: .link).contains { $0.id == link.id }, "Link/type filters failed")
            store.archive(note)
            try expect(store.filtered(scope: .archive, query: "tag:launch", kind: nil).contains { $0.id == noteID }, "Archive filter failed")
            try expect(!store.filtered(scope: .pinned, query: "", kind: nil).contains { $0.id == noteID }, "Archived ideas must be absent from pinned")
            store.archive(note)
            let disposable = try require(store.create("Disposable"), "Temporary idea creation failed")
            let disposableID = disposable.id; store.delete(disposable)
            try expect(!store.ideas.contains { $0.id == disposableID }, "Idea deletion failed")
            store.addCategory("Disposable category", icon: "folder", accent: "orange")
            let temporaryCategory = try require(store.categories.first { $0.name == "Disposable category" }, "Temporary category creation failed")
            let moved = try require(store.create("Move me to Inbox", categoryID: temporaryCategory.id), "Category migration fixture failed")
            let movedID = moved.id
            store.deleteCategory(temporaryCategory)
            try expect(moved.categoryID == store.inboxID, "Deleting a category must move its ideas to Inbox")
            try expect(store.ideas.first { $0.id == movedID }?.categoryID == store.inboxID, "Category migration must survive a fetch")
            let inbox = try require(store.categories.first(where: \.isInbox), "Inbox is missing")
            store.deleteCategory(inbox)
            try expect(store.categories.contains { $0.isInbox }, "Inbox deletion must be prevented")
            print("PASS: capture, edit, pin, favorite, archive, delete, tags, filters, search, and category ordering/migration")

            let service = AttachmentService(store: store)
            let attachment = try service.fromImageData(png, name: "Tiny test image.png")
            imageID = attachment.id
            imageTypeDescription = attachment.typeDescription
            let photo = try require(store.create("Image idea #visual", categoryID: category.id, attachments: [attachment]), "Image capture failed")
            photoID = photo.id
            try expect(photo.kind == .image && attachment.relativePath != nil, "Images must be owned local attachments")
            try expect(try Data(contentsOf: store.attachmentURL(attachment.relativePath!)) == png, "Stored image bytes changed")
            let reference = try service.fromFile(externalURL)
            externalAttachmentID = reference.id
            let externalIdea = try require(store.create("External file reference", attachments: [reference]), "Referenced file capture failed")
            externalIdeaID = externalIdea.id
            try expect(reference.relativePath == nil && reference.originalPath == externalURL.path, "External files must remain references")
            service.discard([reference])
            try expect(FileManager.default.fileExists(atPath: externalURL.path), "Discarding a reference deleted the original file")
            let imageSource = root.appendingPathComponent("symlink-source.png")
            let imageSymlink = root.appendingPathComponent("symlink-image.png")
            try png.write(to: imageSource)
            try FileManager.default.createSymbolicLink(at: imageSymlink, withDestinationURL: imageSource)
            let symlinkAttachment = try service.fromFile(imageSymlink)
            let copiedImageURL = try service.url(for: symlinkAttachment)
            try expect(try copiedImageURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false, "A copied image must not keep a symlink to the original")
            try expect(try Data(contentsOf: copiedImageURL) == png, "Image symlink capture changed its bytes")
            service.discard([symlinkAttachment])
            try expect(FileManager.default.fileExists(atPath: imageSource.path) && !FileManager.default.fileExists(atPath: copiedImageURL.path), "Discard must remove only the copied symlink image")
            let missingURL = root.appendingPathComponent("missing-reference.txt")
            try Data("missing".utf8).write(to: missingURL)
            let missingReference = try service.fromFile(missingURL)
            try FileManager.default.removeItem(at: missingURL)
            var missingReported = false
            do { _ = try service.url(for: missingReference) } catch { missingReported = true }
            try expect(missingReported, "Missing external references must report an error")
            do {
                _ = try service.fromImageData(Data("not an image".utf8), name: "bad.png")
                throw Failure(message: "Invalid image bytes were accepted")
            } catch is Failure { throw Failure(message: "Invalid image bytes were accepted") }
            catch { /* Expected validation error. */ }
            note.createdAt = originalDate; note.updatedAt = originalDate.addingTimeInterval(123.25)
            note.sortOrder = 42.875; note.tags = ["swift", "custom", "launch"]
            note.isArchived = true
            try expect(store.save(), "Source library save failed")
            try ExportService.exportJSON(store: store, to: backup)
            try ExportService.exportMarkdown(store: store, to: markdown)
            try expect(FileManager.default.fileExists(atPath: markdown.appendingPathComponent("Library.md").path), "Markdown index is missing")
            try expect(try Data(contentsOf: markdown.appendingPathComponent("attachments").appendingPathComponent(attachment.relativePath!)) == png, "Markdown image bytes changed")
            let externalCopies = try FileManager.default.contentsOfDirectory(at: markdown.appendingPathComponent("attachments"), includingPropertiesForKeys: nil)
            try expect(externalCopies.count == 1, "Markdown export duplicated an external file")
            let markdownNotes = try FileManager.default.contentsOfDirectory(atPath: markdown.appendingPathComponent("ideas").path)
            try expect(markdownNotes.count == 5, "Markdown export did not include every idea")
            let noteMarkdown = try String(contentsOf: markdown.appendingPathComponent("ideas/\(noteID.uuidString.lowercased()).md"), encoding: .utf8)
            try expect(noteMarkdown.contains("Edited offline plan") && noteMarkdown.contains("A persisted edit.") && noteMarkdown.contains("Category: Roundtrip") && noteMarkdown.contains("Archived: true") && noteMarkdown.contains("#swift, #custom, #launch"), "Markdown lost note content, flags, category, or tags")
            let photoMarkdown = try String(contentsOf: markdown.appendingPathComponent("ideas/\(photoID.uuidString.lowercased()).md"), encoding: .utf8)
            try expect(photoMarkdown.contains("Image idea #visual") && photoMarkdown.contains("../attachments/\(attachment.relativePath!)"), "Markdown lost the image body or portable image link")
            let externalMarkdown = try String(contentsOf: markdown.appendingPathComponent("ideas/\(externalIdeaID.uuidString.lowercased()).md"), encoding: .utf8)
            try expect(externalMarkdown.contains(URL(fileURLWithPath: externalURL.path).absoluteString) && externalMarkdown.contains("external reference"), "Markdown lost the external reference link")
            print("PASS: image validation/storage, external references, portable JSON, and Markdown with images")
        }
        do {
            let reopened = try IdeaStore(root: sourceRoot)
            let note = try require(reopened.ideas.first { $0.id == noteID }, "Text idea did not survive a store reopen")
            let photo = try require(reopened.ideas.first { $0.id == photoID }, "Image idea did not survive a store reopen")
            try expect(note.title == "Edited offline plan" && note.content.contains("persisted edit"), "Edits did not persist")
            try expect(note.isPinned && note.isFavorite && note.isArchived && note.tags == ["swift", "custom", "launch"], "Flags/tags did not persist")
            try expect(abs(note.createdAt.timeIntervalSince(originalDate)) < 0.00001 && note.sortOrder == 42.875, "Date/order persistence failed")
            try expect(abs(note.updatedAt.timeIntervalSince(originalDate.addingTimeInterval(123.25))) < 0.00001, "Updated date did not persist")
            try expect(photo.attachments.first?.id == imageID && photo.categoryID == categoryID, "Attachment/category relationships did not persist")
            print("PASS: real on-disk SwiftData persistence and reopen")
        }
        do {
            let store = try IdeaStore(root: destinationRoot)
            let initialInbox = store.inboxID
            let count = try ExportService.importJSON(store: store, from: backup)
            try expect(count == 5, "JSON import did not restore all five fixture ideas")
            let note = try require(store.ideas.first { $0.id == noteID }, "JSON import lost an idea UUID")
            let photo = try require(store.ideas.first { $0.id == photoID }, "JSON import lost an image idea")
            try expect(note.isArchived && note.isPinned && note.isFavorite && note.tags == ["swift", "custom", "launch"], "Import lost flags/tags or tag order")
            try expect(note.categoryID == categoryID && store.categories.contains { $0.id == categoryID }, "Import lost a category UUID")
            let category = try require(store.categories.first { $0.id == categoryID }, "Imported category is missing")
            try expect(category.name == "Roundtrip" && category.icon == "lightbulb" && category.accent == "purple" && category.sortOrder == categoryOrder, "Import lost category name/icon/accent/order")
            try expect(abs(note.createdAt.timeIntervalSince(originalDate)) < 0.00001 && note.sortOrder == 42.875, "Import lost dates/order")
            try expect(abs(note.updatedAt.timeIntervalSince(originalDate.addingTimeInterval(123.25))) < 0.00001, "Import lost the updated date")
            let link = try require(store.ideas.first { $0.id == linkID }, "Import lost the link UUID")
            try expect(link.sourceURL == "https://example.com/document" && link.kind == .link && link.tags == ["reading"], "Import lost link metadata")
            try expect(store.inboxID == initialInbox && store.categories.filter(\.isInbox).count == 1, "Import must map source Inbox to local Inbox")
            let attachment = try require(photo.attachments.first, "Import lost an image attachment")
            try expect(attachment.id == imageID && (try Data(contentsOf: store.attachmentURL(attachment.relativePath!))) == png, "Import changed image UUID/bytes")
            try expect(attachment.name == "Tiny test image.png" && attachment.kind == "image" && attachment.byteCount == Int64(png.count) && attachment.typeDescription == imageTypeDescription, "Import lost image attachment metadata")
            let external = try require(store.ideas.flatMap(\.attachments).first { $0.id == externalAttachmentID }, "Import lost an external attachment UUID")
            try expect(external.relativePath == nil && external.originalPath == externalURL.path && external.bookmark?.isEmpty == false, "Import lost the external path/bookmark reference")
            let filesBefore = try FileManager.default.contentsOfDirectory(atPath: destinationRoot.appendingPathComponent("Attachments").path)
            let categoriesBefore = store.categories.count
            note.title = "Local edit kept"; try expect(store.save(), "Local fixture edit failed")
            try expect(try ExportService.importJSON(store: store, from: backup) == 0, "Reimport must be idempotent")
            try expect(store.ideas.count == count && store.categories.count == categoriesBefore, "Reimport created duplicate ideas/categories")
            try expect(note.title == "Local edit kept", "Reimport overwrote a local edit")
            try expect(try FileManager.default.contentsOfDirectory(atPath: destinationRoot.appendingPathComponent("Attachments").path) == filesBefore, "Reimport duplicated owned images")
            try expect(try FileManager.default.contentsOfDirectory(atPath: destinationRoot.appendingPathComponent("Attachments").path).count == 1, "JSON import copied an external file")
            print("PASS: JSON identity/metadata/image roundtrip, Inbox mapping, and idempotent merge preserving local edits")
        }
        do {
            let reopened = try IdeaStore(root: destinationRoot)
            try expect(reopened.ideas.first { $0.id == noteID }?.title == "Local edit kept", "Imported data did not persist after reopening")
            let photo = try require(reopened.ideas.first { $0.id == photoID }, "Imported photo is missing after reopen")
            let ownedPath = try require(photo.attachments.first?.relativePath, "Imported image path is missing")
            let ownedURL = reopened.attachmentURL(ownedPath)
            reopened.delete(photo)
            try expect(!FileManager.default.fileExists(atPath: ownedURL.path), "Deleting an idea must delete its owned image")
            try expect(FileManager.default.fileExists(atPath: externalURL.path), "Deleting an owned image removed an unrelated external file")
            print("PASS: imported library reopen and owned image deletion without touching external files")
        }
        try rejectionTests(root: root, backup: backup)
        try dropTests(root: root, png: png, externalURL: externalURL)
        try clipboardTests(root: root, png: png, externalURL: externalURL)
    }

    private static func dockingGeometryTests() throws {
        let screen = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let fixtures: [(DockEdge, NSRect, NSPoint)] = [
            (.left, NSRect(x: 0, y: 320, width: 300, height: 160), NSPoint(x: -15, y: 0)),
            (.right, NSRect(x: 700, y: 320, width: 300, height: 160), NSPoint(x: 15, y: 0)),
            (.top, NSRect(x: 350, y: 640, width: 300, height: 160), NSPoint(x: 0, y: 15)),
            (.bottom, NSRect(x: 350, y: 0, width: 300, height: 160), NSPoint(x: 0, y: -15)),
            (.topLeft, NSRect(x: 0, y: 640, width: 300, height: 160), NSPoint(x: -15, y: 15)),
            (.topRight, NSRect(x: 700, y: 640, width: 300, height: 160), NSPoint(x: 15, y: 15)),
            (.bottomLeft, NSRect(x: 0, y: 0, width: 300, height: 160), NSPoint(x: -15, y: -15)),
            (.bottomRight, NSRect(x: 700, y: 0, width: 300, height: 160), NSPoint(x: 15, y: -15))
        ]
        let expectedHandles: [DockEdge: NSRect] = [
            .left: NSRect(x: 0, y: 358, width: 22, height: 84),
            .right: NSRect(x: 978, y: 358, width: 22, height: 84),
            .top: NSRect(x: 458, y: 778, width: 84, height: 22),
            .bottom: NSRect(x: 458, y: 0, width: 84, height: 22),
            .topLeft: NSRect(x: 0, y: 770, width: 30, height: 30),
            .topRight: NSRect(x: 970, y: 770, width: 30, height: 30),
            .bottomLeft: NSRect(x: 0, y: 0, width: 30, height: 30),
            .bottomRight: NSRect(x: 970, y: 0, width: 30, height: 30)
        ]
        for (edge, frame, movement) in fixtures {
            let placement = try require(EdgeDockGeometry.candidate(for: frame, in: screen), "No docking candidate for \(edge.label)")
            try expect(placement.edge == edge && (0...1).contains(placement.fraction), "Wrong docking candidate for \(edge.label)")
            let handle = EdgeDockGeometry.handleFrame(for: placement, in: screen)
            let expectedSize = edge.isCorner ? NSSize(width: 30, height: 30) : (edge.isVertical ? NSSize(width: 22, height: 84) : NSSize(width: 84, height: 22))
            try expect(handle == expectedHandles[edge] && handle.size == expectedSize && screen.contains(handle), "Dock handle is incorrectly anchored, sized, or outside the screen for \(edge.label)")
            let moved = EdgeDockGeometry.translatedFrame(frame, toward: edge, distance: 15)
            try expect(moved.origin == NSPoint(x: frame.origin.x + movement.x, y: frame.origin.y + movement.y) && moved.size == frame.size, "Dock animation travels in the wrong direction for \(edge.label)")
            try expect(EdgeDockGeometry.translatedFrame(moved, toward: edge, distance: -15) == frame, "Dock animation cannot reverse for \(edge.label)")
        }
        try expect(Set(DockEdge.allCases).count == 8 && DockEdge.allCases.filter(\.isCorner).count == 4 && DockEdge.allCases.filter(\.isVertical).count == 2, "Dock edge helpers do not distinguish sides and corners")
        try expect(try JSONDecoder().decode([DockEdge].self, from: JSONEncoder().encode(DockEdge.allCases)) == DockEdge.allCases, "Dock edge identities cannot roundtrip through preferences")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 350, y: 320, width: 300, height: 160), in: screen) == nil, "A centered window must not dock")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 22, y: 320, width: 300, height: 160), in: screen)?.edge == .left, "Dock proximity must include the threshold")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 22.01, y: 320, width: 300, height: 160), in: screen) == nil, "Dock proximity extended beyond its threshold")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: -47, y: 320, width: 300, height: 160), in: screen)?.edge == .left, "Dragging past the screen edge must retain the docking candidate")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 750, y: 700, width: 300, height: 160), in: screen)?.edge == .topRight, "Adjacent overshot edges must produce a corner")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 18, y: 320, width: 966, height: 160), in: screen)?.edge == .right, "When opposing horizontal edges qualify, docking must choose the nearer one")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 350, y: 20, width: 300, height: 765), in: screen)?.edge == .top, "When opposing vertical edges qualify, docking must choose the nearer one")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 10, y: 320, width: 980, height: 160), in: screen)?.edge == .left && EdgeDockGeometry.candidate(for: NSRect(x: 350, y: 10, width: 300, height: 780), in: screen)?.edge == .bottom, "Opposing-edge ties must resolve deterministically")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: 1, y: 320, width: 300, height: 160), in: screen, threshold: -10) == nil && EdgeDockGeometry.candidate(for: NSRect(x: 1, y: 320, width: 300, height: 160), in: screen, threshold: .nan) == nil, "Invalid thresholds must not broaden docking proximity")

        let secondScreen = NSRect(x: -1_200, y: -240, width: 1_200, height: 900)
        let secondWindow = NSRect(x: -1_180, y: 50, width: 280, height: 170)
        let secondPlacement = try require(EdgeDockGeometry.candidate(for: secondWindow, in: secondScreen), "Docking failed on a display with negative coordinates")
        let secondHandle = EdgeDockGeometry.handleFrame(for: secondPlacement, in: secondScreen)
        try expect(secondPlacement.edge == .left && secondHandle.minX == secondScreen.minX && abs(secondHandle.midY - secondWindow.midY) < 0.000_001 && secondScreen.contains(secondHandle), "Docking assumes the screen origin is zero or loses its position")
        try expect(EdgeDockGeometry.candidate(for: NSRect(x: -280, y: -251, width: 280, height: 170), in: secondScreen)?.edge == .bottomRight, "Corner detection failed on a secondary display")
        let horizontalWindow = NSRect(x: -1_000, y: 500, width: 120, height: 160)
        let horizontalPlacement = try require(EdgeDockGeometry.candidate(for: horizontalWindow, in: secondScreen), "Horizontal docking failed on a secondary display")
        let horizontalHandle = EdgeDockGeometry.handleFrame(for: horizontalPlacement, in: secondScreen)
        try expect(horizontalPlacement.edge == .top && abs(horizontalHandle.midX - horizontalWindow.midX) < 0.000_001 && horizontalHandle.maxY == secondScreen.maxY, "Horizontal docking lost its noncentral position on a secondary display")

        let lowVertical = EdgeDockGeometry.handleFrame(for: DockPlacement(edge: .left, fraction: -0.7), in: secondScreen)
        let highVertical = EdgeDockGeometry.handleFrame(for: DockPlacement(edge: .right, fraction: 1.5), in: secondScreen)
        let lowHorizontal = EdgeDockGeometry.handleFrame(for: DockPlacement(edge: .bottom, fraction: -2), in: secondScreen)
        let highHorizontal = EdgeDockGeometry.handleFrame(for: DockPlacement(edge: .top, fraction: 3), in: secondScreen)
        try expect(lowVertical.minY == secondScreen.minY && highVertical.maxY == secondScreen.maxY && lowHorizontal.minX == secondScreen.minX && highHorizontal.maxX == secondScreen.maxX, "Dock fractions must clamp safely at both ends of every axis")
        let undefinedFraction = EdgeDockGeometry.handleFrame(for: DockPlacement(edge: .left, fraction: .nan), in: screen)
        try expect(undefinedFraction.midY == screen.midY && screen.contains(undefinedFraction), "Invalid persisted fractions must produce a visible handle")

        let oversized = EdgeDockGeometry.restoredFrame(NSRect(x: -3_000, y: -2_000, width: 5_000, height: 3_000), in: screen)
        try expect(oversized == NSRect(x: 12, y: 12, width: 976, height: 776), "An oversized restored window must fit within visible screen margins")
        let offscreen = EdgeDockGeometry.restoredFrame(NSRect(x: 1_600, y: 2_000, width: 100, height: 80), in: secondScreen)
        try expect(offscreen == NSRect(x: -112, y: 568, width: 100, height: 80), "Restoration failed to bring a window onto a secondary display")
        let alreadyVisible = NSRect(x: -800, y: 30, width: 210, height: 140)
        try expect(EdgeDockGeometry.restoredFrame(alreadyVisible, in: secondScreen) == alreadyVisible, "Restoration moved an already visible window")
        let tinyScreen = NSRect(x: 4, y: 5, width: 12, height: 9)
        for edge in DockEdge.allCases {
            try expect(tinyScreen.contains(EdgeDockGeometry.handleFrame(for: DockPlacement(edge: edge, fraction: 1), in: tinyScreen)), "A docking handle overflowed a screen smaller than itself")
        }
        try expect(EdgeDockGeometry.restoredFrame(NSRect(x: -80, y: 1_500, width: 640, height: 400), in: tinyScreen) == tinyScreen, "Restoration produced an invalid frame when the screen cannot fit the default margins")
        let damagedFrame = EdgeDockGeometry.restoredFrame(NSRect(x: CGFloat.nan, y: CGFloat.infinity, width: CGFloat.infinity, height: -20), in: secondScreen)
        try expect(damagedFrame.width > 0 && damagedFrame.height > 0 && secondScreen.contains(damagedFrame), "Invalid persisted window geometry must restore to a finite visible frame")
        try expect(EdgeDockGeometry.candidate(for: .zero, in: screen) == nil && EdgeDockGeometry.handleFrame(for: DockPlacement(edge: .left, fraction: 0), in: .zero) == .zero, "Unavailable screen/window geometry must be handled safely")
        print("PASS: all eight dock edges/corners, threshold/overflow, negative screen coordinates, handle fractions, animation directions, and visible window restoration")
    }

    private static func captureHistoryTests(root: URL) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try require(TimeZone(secondsFromGMT: 0), "History test time zone is unavailable")
        calendar.locale = Locale(identifier: "en_US_POSIX")
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar) throws -> Date {
            try require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)), "History date fixture is invalid")
        }
        let now = try date(2026, 10, 3, 12, 30, in: calendar)
        let today = try require(calendar.dateInterval(of: .day, for: now), "Current day interval is unavailable")
        let yesterday = try date(2026, 10, 2, in: calendar)
        let justBeforeMidnight = today.start.addingTimeInterval(-0.001)
        try expect(CaptureDateFilter.today.matches(today.start, now: now, calendar: calendar) && !CaptureDateFilter.today.matches(today.end, now: now, calendar: calendar), "Today must include midnight at its start and exclude midnight of the next day")
        try expect(CaptureDateFilter.yesterday.matches(yesterday, now: now, calendar: calendar) && CaptureDateFilter.yesterday.matches(justBeforeMidnight, now: now, calendar: calendar) && !CaptureDateFilter.yesterday.matches(today.start, now: now, calendar: calendar), "Yesterday must use its exact calendar-day boundaries")
        try expect(CaptureDateFilter.today.matches(now.addingTimeInterval(1), now: now, calendar: calendar), "Today must match the full current calendar interval")
        for (filter, precedingDays) in [(CaptureDateFilter.last7Days, 6), (.last30Days, 29)] {
            let start = try require(calendar.date(byAdding: .day, value: -precedingDays, to: today.start), "Recent-history boundary fixture failed")
            try expect(filter.matches(start, now: now, calendar: calendar) && !filter.matches(start.addingTimeInterval(-0.001), now: now, calendar: calendar), "\(filter.label) did not include the exact first day")
            try expect(filter.matches(now, now: now, calendar: calendar) && !filter.matches(now.addingTimeInterval(0.001), now: now, calendar: calendar), "\(filter.label) must include now and exclude later timestamps")
        }
        try expect(CaptureDateFilter.anyTime.matches(today.end, now: now, calendar: calendar) && CaptureDateFilter.anyTime.matches(try date(1990, 1, 1, in: calendar), now: now, calendar: calendar), "Any time must preserve future and old saved dates")

        var daylightCalendar = calendar
        daylightCalendar.timeZone = try require(TimeZone(identifier: "America/New_York"), "Daylight-saving time zone is unavailable")
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let daylightNow = try date(2026, month, day, 12, in: daylightCalendar)
            let interval = try require(daylightCalendar.dateInterval(of: .day, for: daylightNow), "Daylight-saving day interval is unavailable")
            let nextDayNoon = try require(daylightCalendar.date(byAdding: .day, value: 1, to: daylightNow), "Daylight-saving next day fixture failed")
            try expect(interval.duration == Double(hours * 3_600), "Daylight-saving fixture does not have its expected \(hours)-hour day")
            try expect(CaptureDateFilter.today.matches(interval.start, now: daylightNow, calendar: daylightCalendar) && CaptureDateFilter.today.matches(interval.end.addingTimeInterval(-0.001), now: daylightNow, calendar: daylightCalendar) && !CaptureDateFilter.today.matches(interval.end, now: daylightNow, calendar: daylightCalendar), "Today used a fixed 24-hour interval across daylight-saving time")
            try expect(CaptureDateFilter.yesterday.matches(interval.start, now: nextDayNoon, calendar: daylightCalendar) && CaptureDateFilter.yesterday.matches(interval.end.addingTimeInterval(-0.001), now: nextDayNoon, calendar: daylightCalendar) && !CaptureDateFilter.yesterday.matches(interval.end, now: nextDayNoon, calendar: daylightCalendar), "Yesterday lost a boundary across daylight-saving time")
            for (filter, precedingDays) in [(CaptureDateFilter.last7Days, 6), (.last30Days, 29)] {
                let start = try require(daylightCalendar.date(byAdding: .day, value: -precedingDays, to: daylightCalendar.startOfDay(for: nextDayNoon)), "Daylight-saving recent-history fixture failed")
                try expect(filter.matches(start, now: nextDayNoon, calendar: daylightCalendar) && !filter.matches(start.addingTimeInterval(-0.001), now: nextDayNoon, calendar: daylightCalendar), "Recent-history filters used elapsed hours rather than calendar days")
            }
        }

        let libraryRoot = root.appendingPathComponent("capture-history", isDirectory: true)
        var originalID = UUID()
        do {
            let store = try IdeaStore(root: libraryRoot)
            func note(_ content: String, at createdAt: Date, pinned: Bool = false) throws -> Idea {
                let idea = try require(store.create(content), "History note fixture could not be saved")
                idea.createdAt = createdAt; idea.updatedAt = createdAt; idea.isPinned = pinned
                return idea
            }
            let older = try note("Old pinned note", at: date(2025, 1, 10, 9, in: calendar), pinned: true)
            let nearMidnight = try note("Last capture before midnight", at: justBeforeMidnight)
            let firstToday = try note("First capture today", at: today.start)
            let latest = try note("Latest capture today", at: now)
            originalID = latest.id
            let tied = try note("Same capture instant", at: now)
            let future = try note("A saved future-clock timestamp", at: today.end)
            let archived = try note("Archived today", at: now.addingTimeInterval(-1))
            archived.isArchived = true
            try expect(store.save(), "History fixtures could not be saved")
            let chronological = store.filtered(scope: .recent, query: "", kind: nil, now: now, calendar: calendar)
            let expectedTies = [latest, tied].sorted { $0.id.uuidString < $1.id.uuidString }.map(\.id)
            try expect(chronological.map(\.id) == [future.id] + expectedTies + [firstToday.id, nearMidnight.id, older.id], "All Notes must be chronological, stable for equal timestamps, and exclude archives; old pins must not jump ahead")
            let current = store.filtered(scope: .today, query: "", kind: nil, now: now, calendar: calendar)
            try expect(current.map(\.id) == expectedTies + [firstToday.id], "Today scope must include active current-day notes in chronological order")
            try expect(store.filtered(scope: .inbox, query: "", kind: nil, now: now, calendar: calendar).first?.id == older.id, "Existing scoped lists must retain pin-first ordering")
            try expect(store.filtered(scope: .recent, query: "", kind: nil, dateFilter: .yesterday, now: now, calendar: calendar).map(\.id) == [nearMidnight.id], "The capture-time filter was not applied to All Notes")
            try expect(store.filtered(scope: .today, query: "", kind: nil, dateFilter: .yesterday, now: now, calendar: calendar).isEmpty, "Today scope and a supplied time filter must both apply")
            try expect(store.filtered(scope: .recent, query: "Latest", kind: .text, dateFilter: .today, now: now, calendar: calendar).map(\.id) == [latest.id], "Capture-time filtering must compose with text search and content type")
            let sections = CaptureHistory.sections(chronological, now: now, calendar: calendar)
            try expect(sections.count == 4 && sections[0].id == today.end && sections[0].title.contains("2026") && sections[0].title != "Today", "Future saved dates need their actual calendar heading")
            try expect(sections[1].id == today.start && sections[1].title == "Today" && sections[1].ideas.map(\.id) == expectedTies + [firstToday.id], "Today's automatic history section lost capture order")
            try expect(sections[2].id == yesterday && sections[2].title == "Yesterday" && sections[2].ideas.map(\.id) == [nearMidnight.id], "History misgrouped a capture immediately before midnight")
            try expect(sections[3].title.contains("2025") && sections[3].ideas.map(\.id) == [older.id], "Older history headings must include the year")
            try expect(sections.flatMap(\.ideas).map(\.id) == chronological.map(\.id) && CaptureHistory.sections([], now: now, calendar: calendar).isEmpty, "History sections must preserve canonical keyboard-navigation order and handle an empty library")
            latest.content += "\nEdited later."; store.changed(latest)
            try expect(latest.createdAt == now, "Editing a note must not change its original capture timestamp")
            latest.isPinned = true; store.changed(latest)
            try expect(latest.createdAt == now, "Pinning a note must not change its original capture timestamp")
        }
        let reopened = try IdeaStore(root: libraryRoot)
        let preserved = try require(reopened.ideas.first { $0.id == originalID }, "History note is missing after reopening")
        try expect(preserved.createdAt == now && preserved.content.contains("Edited later.") && preserved.isPinned, "Original capture time or later edits did not survive a disk reopen")
        print("PASS: calendar history/time filters, exact midnight boundaries, 23/25-hour DST days, chronological pins/UUID ties, and immutable capture timestamps after edits/reopen")
    }

    private static func dropTests(root: URL, png: Data, externalURL: URL) throws {
        let libraryRoot = root.appendingPathComponent("drop-pipeline", isDirectory: true)
        let imageSource = root.appendingPathComponent("drop-source.png")
        try png.write(to: imageSource)
        var ideaID = UUID()
        do {
            let store = try IdeaStore(root: libraryRoot)
            let service = AttachmentService(store: store)
            let url = try require(URL(string: "https://example.com/drop"), "Drop URL fixture failed")
            let nativeURL = NSItemProvider(object: url as NSURL)
            nativeURL.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(Data("Duplicate fallback title must not appear".utf8), nil); return nil
            }
            let registeredImage = dataProvider(png, type: .png)
            registeredImage.suggestedName = "Registered drop.png"
            let fileBackedImage = try require(NSItemProvider(contentsOf: imageSource), "File-backed image provider failed")
            let providers = [
                dataProvider(Data(externalURL.absoluteString.utf8), type: .fileURL),
                NSItemProvider(object: externalURL as NSURL),
                NSItemProvider(object: "Dropped text #drop" as NSString),
                nativeURL, registeredImage, fileBackedImage
            ]
            let result = try readProviders(providers, service: service)
            try expect(result.error == nil, "A supported native drop provider failed: \(result.error ?? "unknown error")")
            try expect(result.text == "Dropped text #drop\nhttps://example.com/drop", "Drop provider priority duplicated or lost text/URL representations")
            try expect(result.attachments.count == 3 && result.attachments.filter { $0.relativePath == nil }.count == 1, "Drop pipeline did not deduplicate file URLs or retain both image items")
            let images = result.attachments.filter { $0.relativePath != nil }
            try expect(images.count == 2, "Raw and file-backed image drops did not produce owned images")
            for image in images {
                try expect(try Data(contentsOf: service.url(for: image)) == png, "Drop pipeline changed image bytes")
            }
            let idea = try require(store.create(result.text, attachments: result.attachments), "Dropped content could not be captured")
            ideaID = idea.id
            try expect(idea.tags == ["drop"] && idea.kind == .image && idea.sourceURL == url.absoluteString, "Dropped content classification/tags failed")

            let partial = try readProviders([NSItemProvider(), NSItemProvider(object: "Surviving text" as NSString)], service: service)
            try expect(partial.error?.isEmpty == false && partial.text == "Surviving text" && partial.attachments.isEmpty, "Unsupported drop data should report an error while retaining supported items")

            let draft = CaptureDraft(store: store, service: service)
            draft.drop([dataProvider(png, type: .png)])
            try expect(draft.isLoading && !draft.canSave, "Capture must wait for asynchronous drop loading")
            try pumpUntil({ !draft.isLoading }, message: "Capture draft drop did not complete within four seconds")
            try expect(draft.error == nil && draft.canSave && draft.attachments.count == 1, "Capture draft did not receive the dropped image")
            let disposable = try require(draft.attachments.first?.relativePath, "Dropped draft image has no owned path")
            draft.clear()
            try expect(!FileManager.default.fileExists(atPath: store.attachmentURL(disposable).path), "Clearing an unsaved dropped draft must remove its copied image")
        }
        let reopened = try IdeaStore(root: libraryRoot)
        let idea = try require(reopened.ideas.first { $0.id == ideaID }, "Dropped idea did not survive on-disk reopen")
        try expect(reopened.ideas.count == 1 && idea.attachments.count == 3 && idea.tags == ["drop"], "Drop pipeline lost persisted attachment relationships")
        for image in idea.attachments where image.relativePath != nil {
            try expect(try Data(contentsOf: reopened.attachmentURL(image.relativePath!)) == png, "Persisted dropped image bytes changed")
        }
        print("PASS: native asynchronous NSItemProvider text/URL/file/image drops, priority/deduplication, capture/reopen, and draft cleanup")
    }

    private static func clipboardTests(root: URL, png: Data, externalURL: URL) throws {
        let store = try IdeaStore(root: root.appendingPathComponent("clipboard-pipeline", isDirectory: true))
        let service = AttachmentService(store: store)
        // A uniquely named pasteboard exercises AppKit without reading or writing
        // NSPasteboard.general or changing the user's current clipboard.
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        try expect(pasteboard.setString("Private clipboard text #clip", forType: .string), "Could not populate private text pasteboard")
        let text = try service.clipboard(pasteboard)
        try expect(text.text == "Private clipboard text #clip" && text.attachments.isEmpty, "Private clipboard text capture failed")

        let link = NSPasteboardItem()
        try expect(link.setString("https://example.com/clipboard", forType: .URL) && link.setString("A browser title", forType: .string), "Could not populate private URL pasteboard")
        pasteboard.clearContents(); try expect(pasteboard.writeObjects([link]), "Could not write private URL item")
        let url = try service.clipboard(pasteboard)
        try expect(url.text == "https://example.com/clipboard" && url.attachments.isEmpty, "Clipboard URL representation should take priority over a title")

        let image = NSPasteboardItem(); try expect(image.setData(png, forType: .png), "Could not populate private image pasteboard")
        let caption = NSPasteboardItem(); try expect(caption.setString("A separate image caption", forType: .string), "Could not populate image caption")
        pasteboard.clearContents(); try expect(pasteboard.writeObjects([image, caption]), "Could not write image/caption items")
        let imageResult = try service.clipboard(pasteboard)
        try expect(imageResult.text == "A separate image caption" && imageResult.attachments.count == 1, "Clipboard should preserve separate image and caption items")
        let ownedPath = try require(imageResult.attachments.first?.relativePath, "Clipboard image has no owned path")
        try expect(try Data(contentsOf: store.attachmentURL(ownedPath)) == png, "Clipboard image bytes changed")
        service.discard(imageResult.attachments)
        try expect(!FileManager.default.fileExists(atPath: store.attachmentURL(ownedPath).path), "Discarded private clipboard image was left behind")

        let file = NSPasteboardItem(); let duplicate = NSPasteboardItem()
        try expect(file.setString(externalURL.absoluteString, forType: .fileURL) && duplicate.setString(externalURL.absoluteString, forType: .fileURL), "Could not populate private file pasteboard")
        pasteboard.clearContents(); try expect(pasteboard.writeObjects([file, duplicate]), "Could not write private file references")
        let files = try service.clipboard(pasteboard)
        try expect(files.attachments.count == 1 && files.attachments.first?.relativePath == nil && files.attachments.first?.originalPath == externalURL.path, "Clipboard file references should be deduplicated without copying originals")
        service.discard(files.attachments)
        try expect(FileManager.default.fileExists(atPath: externalURL.path), "Clipboard discard removed an external original")

        let missing = NSPasteboardItem()
        let failureImage = NSPasteboardItem(); try expect(failureImage.setData(png, forType: .png), "Could not populate failure image")
        let missingURL = root.appendingPathComponent("not-a-real-clipboard-file.txt")
        try expect(missing.setString(missingURL.absoluteString, forType: .fileURL), "Could not populate missing private file reference")
        pasteboard.clearContents(); try expect(pasteboard.writeObjects([failureImage, missing]), "Could not write private failure fixture")
        var failed = false
        do { _ = try service.clipboard(pasteboard) } catch { failed = true }
        try expect(failed, "A missing clipboard file reference must report an error")
        try expect(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("Attachments").path).isEmpty, "Failed clipboard capture did not discard an earlier copied image")
        print("PASS: private named-pasteboard text/URL/image+caption/file capture, representation priority, deduplication, and failure cleanup; general clipboard untouched")
    }

    private static func dataProvider(_ data: Data, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in completion(data, nil); return nil }
        return provider
    }
    private static func readProviders(_ providers: [NSItemProvider], service: AttachmentService) throws -> (text: String, attachments: [Attachment], error: String?) {
        var result: (text: String, attachments: [Attachment], error: String?)?
        DropReader.read(providers, service: service) { text, attachments, error in result = (text, attachments, error) }
        try pumpUntil({ result != nil }, message: "DropReader did not complete within four seconds")
        return result!
    }
    private static func pumpUntil(_ predicate: () -> Bool, message: String) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while !predicate() && ProcessInfo.processInfo.systemUptime < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date.now.addingTimeInterval(0.01))
        }
        try expect(predicate(), message)
    }
    private static func rejectionTests(root: URL, backup: URL) throws {
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as! [String: Any]
        let rootDirectory = root.appendingPathComponent("rejections", isDirectory: true)
        let store = try IdeaStore(root: rootDirectory)
        let initialCategoryCount = store.categories.count
        func rejected(_ document: [String: Any], label: String) throws {
            let file = root.appendingPathComponent("crafted-\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]).write(to: file)
            var accepted = false
            do { _ = try ExportService.importJSON(store: store, from: file); accepted = true } catch { }
            try expect(!accepted, label)
            try expect(store.ideas.isEmpty && store.categories.count == initialCategoryCount, "Rejected import mutated the database")
            try expect(try FileManager.default.contentsOfDirectory(atPath: rootDirectory.appendingPathComponent("Attachments").path).isEmpty, "Rejected import left image files behind")
        }
        var future = original; future["version"] = 999
        try rejected(future, label: "Unsupported JSON versions must be rejected")
        var duplicate = original
        var duplicateIdeas = duplicate["ideas"] as! [[String: Any]]; duplicateIdeas.append(duplicateIdeas[0]); duplicate["ideas"] = duplicateIdeas
        try rejected(duplicate, label: "Duplicate idea IDs must be rejected")
        var traversal = original; var ideas = traversal["ideas"] as! [[String: Any]]
        let index = try require(ideas.firstIndex { !(($0["attachments"] as? [[String: Any]]) ?? []).isEmpty && (($0["attachments"] as? [[String: Any]]) ?? []).contains { $0["imageData"] != nil } }, "Image export fixture is missing")
        var attachments = ideas[index]["attachments"] as! [[String: Any]]
        attachments[0]["relativePath"] = "../outside.png"; ideas[index]["attachments"] = attachments; traversal["ideas"] = ideas
        try rejected(traversal, label: "Path traversal filenames must be rejected")
        var executableSuffix = original; ideas = executableSuffix["ideas"] as! [[String: Any]]; attachments = ideas[index]["attachments"] as! [[String: Any]]
        let uuid = attachments[0]["id"] as! String
        attachments[0]["relativePath"] = "\(uuid.lowercased()).command"; ideas[index]["attachments"] = attachments; executableSuffix["ideas"] = ideas
        try rejected(executableSuffix, label: "Owned images with executable filename extensions must be rejected")
        var invalidImage = original; ideas = invalidImage["ideas"] as! [[String: Any]]; attachments = ideas[index]["attachments"] as! [[String: Any]]
        let bad = Data("invalid image".utf8)
        attachments[0]["imageData"] = bad.base64EncodedString(); attachments[0]["byteCount"] = bad.count
        ideas[index]["attachments"] = attachments; invalidImage["ideas"] = ideas
        try rejected(invalidImage, label: "Corrupt embedded images must be rejected before mutation")
        var excessiveDimensions = original; ideas = excessiveDimensions["ideas"] as! [[String: Any]]; attachments = ideas[index]["attachments"] as! [[String: Any]]
        let oversized = try imageFixture(width: 16_001, height: 1)
        attachments[0]["imageData"] = oversized.base64EncodedString(); attachments[0]["byteCount"] = oversized.count
        ideas[index]["attachments"] = attachments; excessiveDimensions["ideas"] = ideas
        try rejected(excessiveDimensions, label: "Images exceeding dimension limits must be rejected")
        var excessiveFrames = original; ideas = excessiveFrames["ideas"] as! [[String: Any]]; attachments = ideas[index]["attachments"] as! [[String: Any]]
        let gif = try repeatedGIF(png: try imageFixture(), frames: 10_001)
        attachments[0]["relativePath"] = "\((attachments[0]["id"] as! String).lowercased()).gif"
        attachments[0]["imageData"] = gif.base64EncodedString(); attachments[0]["byteCount"] = gif.count
        ideas[index]["attachments"] = attachments; excessiveFrames["ideas"] = ideas
        try rejected(excessiveFrames, label: "Animations exceeding the frame count limit must be rejected")
        var dangling = original; ideas = dangling["ideas"] as! [[String: Any]]; ideas[0]["categoryID"] = UUID().uuidString; dangling["ideas"] = ideas
        try rejected(dangling, label: "Unknown category references must be rejected")

        // Trigger a failure after category insertion by preoccupying the owned file.
        let originalIdeas = original["ideas"] as! [[String: Any]]
        let path = (originalIdeas[index]["attachments"] as! [[String: Any]])[0]["relativePath"] as! String
        let occupied = store.attachmentURL(path)
        try Data("existing file".utf8).write(to: occupied)
        let unrelated = try require(store.create("Unrelated existing note"), "Rollback preservation fixture failed")
        let unrelatedID = unrelated.id
        unrelated.content = "Unrelated local edit waiting to save"
        try expect(store.context.hasChanges, "Runtime edits must mark the SwiftData context dirty")
        var firstImageIdea = originalIdeas[index]
        firstImageIdea["id"] = UUID().uuidString
        var firstAttachment = (firstImageIdea["attachments"] as! [[String: Any]])[0]
        let newAttachmentID = UUID()
        let newPath = "\(newAttachmentID.uuidString.lowercased()).png"
        firstAttachment["id"] = newAttachmentID.uuidString; firstAttachment["relativePath"] = newPath
        firstImageIdea["attachments"] = [firstAttachment]
        var collisionDocument = original
        collisionDocument["ideas"] = [firstImageIdea, originalIdeas[index]]
        let collisionBackup = root.appendingPathComponent("collision.json")
        try JSONSerialization.data(withJSONObject: collisionDocument).write(to: collisionBackup)
        var rejectedCollision = false
        do { _ = try ExportService.importJSON(store: store, from: collisionBackup) } catch { rejectedCollision = true }
        try expect(rejectedCollision && store.ideas.count == 1 && store.ideas.first?.id == unrelatedID && store.categories.count == initialCategoryCount, "Attachment collision must roll back only inserted categories/ideas")
        try expect(store.ideas.first?.content == "Unrelated local edit waiting to save", "Failed import discarded an unrelated local edit")
        try expect(try Data(contentsOf: occupied) == Data("existing file".utf8), "Import overwrote an existing attachment file")
        try expect(!FileManager.default.fileExists(atPath: store.attachmentURL(newPath).path), "Failed import did not remove a newly copied image")
        try FileManager.default.removeItem(at: occupied)
        let reopened = try IdeaStore(root: rootDirectory)
        try expect(reopened.ideas.count == 1 && reopened.ideas.first?.id == unrelatedID && reopened.ideas.first?.content == "Unrelated local edit waiting to save" && reopened.categories.count == initialCategoryCount, "Import rollback did not persist the unrelated edit or left a partial import on disk")
        print("PASS: unsupported versions, duplicate IDs, unsafe paths, corrupt/oversized images, dangling categories, and import rollback")
    }
    private static func imageFixture(width: Int = 2, height: Int = 2) throws -> Data {
        let representation = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Could not create PNG fixture")
        for x in 0..<width { for y in 0..<height { representation.setColor(NSColor(calibratedRed: 0.92, green: 0.34, blue: 0.19, alpha: 1), atX: x, y: y) } }
        return try require(representation.representation(using: .png, properties: [:]), "Could not encode PNG fixture")
    }
    private static func repeatedGIF(png: Data, frames: Int) throws -> Data {
        let bitmap = try require(NSBitmapImageRep(data: png), "Could not read animation fixture")
        let gif = try require(bitmap.representation(using: .gif, properties: [:]), "Could not encode animation fixture")
        try expect(gif.count > 14 && gif.last == 0x3B, "Animation fixture has no GIF trailer")
        let packed = Int(gif[10])
        let paletteSize = packed & 0x80 == 0 ? 0 : 3 * (1 << ((packed & 7) + 1))
        let headerLength = 13 + paletteSize
        try expect(headerLength < gif.count - 1, "Animation fixture has no image block")
        var repeated = Data(gif.prefix(headerLength))
        let frame = Data(gif[headerLength..<(gif.count - 1)])
        for _ in 0..<frames { repeated.append(frame) }
        repeated.append(0x3B)
        let source = try require(CGImageSourceCreateWithData(repeated as CFData, nil), "Repeated animation fixture is invalid")
        try expect(CGImageSourceGetCount(source) == frames && CGImageSourceCreateImageAtIndex(source, 0, nil) != nil, "Repeated animation fixture does not contain the expected valid frames")
        return repeated
    }
}

extension SelfTests {
    /// Verifies all edge variants are defined.
    static func verifyEdgeCases() -> Bool {
        DockEdge.allCases.count == 8
    }
}
