import AppKit
import SwiftData
import Observation

@MainActor @Observable final class IdeaStore {
    let container: ModelContainer
    let context: ModelContext
    let root: URL
    var ideas: [Idea] = []
    var categories: [IdeaCategory] = []
    var errorMessage: String?
    var revision = 0
    var lastSaveFailed = false
    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IdeaDock", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        let schema = Schema([Idea.self, IdeaCategory.self, Attachment.self])
        let config = ModelConfiguration("IdeaDock", schema: schema, url: self.root.appendingPathComponent("IdeaDock.store"), cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container); context.autosaveEnabled = true
        try reload()
        if categories.isEmpty {
            let defaults: [(String, String)] = [("Inbox", "tray"), ("App Idea", "app"), ("Website", "globe"), ("Feature", "sparkle"), ("UI / UX", "square.on.circle"), ("Bug", "ladybug"), ("Research", "magnifyingglass"), ("Content", "text.bubble"), ("Business", "briefcase"), ("Personal", "person")]
            for (index, entry) in defaults.enumerated() { context.insert(IdeaCategory(name: entry.0, icon: entry.1, accent: "gray", sortOrder: index, isInbox: index == 0)) }
            try context.save(); try reload()
        }
    }
    var inboxID: UUID { categories.first(where: \.isInbox)!.id }
    func reload() throws {
        ideas = try context.fetch(FetchDescriptor<Idea>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        categories = try context.fetch(FetchDescriptor<IdeaCategory>(sortBy: [SortDescriptor(\.sortOrder)])); revision += 1
    }
    @discardableResult func save() -> Bool {
        do { try context.save(); revision += 1; lastSaveFailed = false; return true }
        catch { lastSaveFailed = true; errorMessage = "Your changes could not be saved: \(error.localizedDescription)"; return false }
    }
    func categoryName(_ id: UUID) -> String { categories.first { $0.id == id }?.name ?? "Inbox" }
    @discardableResult func create(_ content: String, categoryID: UUID? = nil, attachments: [Attachment] = [], detectTags: Bool = true) -> Idea? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return nil }
        let idea = Idea(content: content, categoryID: categoryID ?? inboxID, attachments: attachments)
        if !detectTags { idea.tags = [] }
        context.insert(idea)
        guard save() else { context.delete(idea); return nil }
        ideas.insert(idea, at: 0); return idea
    }
    func changed(_ idea: Idea) { if idea.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { idea.title = ContentAnalysis.title(idea.content, fallback: idea.attachments.first?.name ?? "Untitled idea") }; idea.updatedAt = .now; idea.sourceURL = ContentAnalysis.url(idea.content); idea.contentType = ContentAnalysis.kind(idea.content, attachments: idea.attachments).rawValue; _ = save() }
    func delete(_ idea: Idea) {
        let paths = idea.attachments.compactMap(\.relativePath)
        context.delete(idea)
        guard save() else { context.rollback(); return }
        ideas.removeAll { $0 === idea }
        for path in paths { try? FileManager.default.removeItem(at: attachmentURL(path)) }
    }
    func removeAttachment(_ attachment: Attachment, from idea: Idea) {
        let path = attachment.relativePath
        idea.attachments.removeAll { $0 === attachment }
        context.delete(attachment)
        idea.contentType = ContentAnalysis.kind(idea.content, attachments: idea.attachments).rawValue
        idea.updatedAt = .now
        guard save() else { context.rollback(); try? reload(); return }
        if let path { try? FileManager.default.removeItem(at: attachmentURL(path)) }
    }
    func archive(_ idea: Idea) { idea.isArchived.toggle(); changed(idea) }
    func addCategory(_ name: String, icon: String, accent: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name for this category."; return }
        guard save() else { return }
        context.insert(IdeaCategory(name: trimmed, icon: icon, accent: accent, sortOrder: categories.count))
        guard save() else { context.rollback(); try? reload(); return }
        do { try reload() } catch { errorMessage = "Your category was saved, but the list could not refresh: \(error.localizedDescription)" }
    }
    func deleteCategory(_ category: IdeaCategory) {
        guard !category.isInbox else { return }
        guard save() else { return }
        let categoryID = category.id
        let destinationID = inboxID
        for idea in ideas where idea.categoryID == categoryID { idea.categoryID = destinationID }
        context.delete(category)
        guard save() else { context.rollback(); try? reload(); return }
        do { try reload() } catch { errorMessage = "Your category was deleted, but the list could not refresh: \(error.localizedDescription)" }
    }
    func moveCategory(_ category: IdeaCategory, offset: Int) {
        guard !category.isInbox, let index = categories.firstIndex(where: { $0.id == category.id }), index >= 1 else { return }
        let target = index + offset
        guard target >= 1 && target < categories.count else { return }
        guard save() else { return }
        categories.swapAt(index, target)
        for (position, value) in categories.enumerated() { value.sortOrder = position }
        guard save() else { context.rollback(); try? reload(); return }
    }
    func filtered(scope: LibraryScope, query: String, kind: ContentKind?, dateFilter: CaptureDateFilter = .anyTime, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> [Idea] {
        _ = revision
        return ideas.filter { idea in
            let inScope: Bool
            switch scope {
            case .inbox: inScope = !idea.isArchived && idea.categoryID == inboxID
            case .pinned: inScope = !idea.isArchived && idea.isPinned
            case .favorites: inScope = !idea.isArchived && idea.isFavorite
            case .recent: inScope = !idea.isArchived
            case .today: inScope = !idea.isArchived && CaptureDateFilter.today.matches(idea.createdAt, now: now, calendar: calendar)
            case .images: inScope = !idea.isArchived && idea.kind == .image
            case .links: inScope = !idea.isArchived && idea.sourceURL != nil
            case .archive: inScope = idea.isArchived
            case .category(let id): inScope = !idea.isArchived && idea.categoryID == id
            }
            return inScope && (kind == nil || idea.kind == kind) && dateFilter.matches(idea.createdAt, now: now, calendar: calendar) && IdeaSearch.matches(idea, query: query, category: categoryName(idea.categoryID))
        }.sorted {
            if scope != .recent && scope != .today && $0.isPinned != $1.isPinned { return $0.isPinned }
            return CaptureHistory.newestFirst($0, $1)
        }
    }
    func attachmentURL(_ path: String) -> URL { root.appendingPathComponent("Attachments").appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent) }
    func removeOrphans() throws {
        let used = Set(ideas.flatMap { $0.attachments.compactMap(\.relativePath) })
        for file in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Attachments"), includingPropertiesForKeys: nil) where !used.contains(file.lastPathComponent) { try FileManager.default.removeItem(at: file) }
    }
}
