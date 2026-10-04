import AppKit
import Observation

@MainActor @Observable final class WorkspaceState {
    let store: IdeaStore
    let attachmentService: AttachmentService
    var captureDrop: ([NSItemProvider]) -> Void = { _ in }
    var detectTags: () -> Bool = { true }
    var openScope: (LibraryScope) -> Void = { _ in }
    var focusSearch: () -> Void = {}
    var scope: LibraryScope = .recent
    var selectedID: UUID?
    var tagRequestID: UUID?
    var search = ""
    var filter: ContentKind?
    var dateFilter: CaptureDateFilter = .anyTime
    var showSidebar = true
    var showEditorOnly = false
    var searchFocusToken = 0
    var listFocusToken = 0
    var editorFocusID: UUID?
    var editorFocusToken = 0
    var capture: () -> Void = {}
    var pasteClipboard: () -> Void = {}
    var settings: () -> Void = {}
    var palette: () -> Void = {}
    var toggleFloating: () -> Void = {}
    var floatIdea: (Idea) -> Void = { _ in }
    var openIdea: (UUID) -> Void = { _ in }
    var attachFiles: (Idea) -> Void = { _ in }
    init(store: IdeaStore) { self.store = store; self.attachmentService = AttachmentService(store: store) }
    var selected: Idea? { store.ideas.first { $0.id == selectedID } }
    var visibleIdeas: [Idea] { store.filtered(scope: scope, query: search, kind: filter, dateFilter: dateFilter) }
    var scopeTitle: String { if case .category(let id) = scope { return store.categoryName(id) }; return scope.label }
    func navigate(_ scope: LibraryScope) { self.scope = scope; search = ""; filter = nil; dateFilter = .anyTime; selectedID = nil; showEditorOnly = false; listFocusToken += 1 }
    func searchIdeas() { scope = .recent; filter = nil; dateFilter = .anyTime; searchFocusToken += 1; showEditorOnly = false }
    func focusEditor(_ id: UUID? = nil) {
        guard let id = id ?? selectedID, store.ideas.contains(where: { $0.id == id }) else { return }
        selectedID = id
        editorFocusID = id
        editorFocusToken += 1
    }
    func moveSelection(_ delta: Int) {
        let values = visibleIdeas
        guard !values.isEmpty else { return }
        let current = values.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : values.count)
        selectedID = values[max(0, min(values.count - 1, current + delta))].id
    }
    func togglePin() { if let selected { selected.isPinned.toggle(); store.changed(selected) } }
    func archiveSelected() {
        guard let selected else { return }
        let id = selected.id; let values = visibleIdeas; let index = values.firstIndex { $0.id == id } ?? 0
        if scope == .archive { deleteWithConfirmation(selected) } else { store.archive(selected) }
        let remaining = visibleIdeas; selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
    func deleteWithConfirmation(_ idea: Idea) {
        let alert = NSAlert(); alert.messageText = "Delete this idea?"; alert.informativeText = "This permanently deletes the idea and its stored images. Referenced files remain on your Mac."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel"); alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let id = idea.id
        if selectedID == id { selectedID = nil }
        store.delete(idea)
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
