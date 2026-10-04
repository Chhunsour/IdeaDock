import AppKit
import Observation

@MainActor @Observable final class CaptureDraft {
    var text = ""
    var attachments: [Attachment] = []
    var categoryID: UUID?
    var focusToken = 0
    var isLoading = false
    var error: String?
    var saved = false
    var lastSavedID: UUID?
    let store: IdeaStore
    let service: AttachmentService
    init(store: IdeaStore, service: AttachmentService) { self.store = store; self.service = service }
    var canSave: Bool { (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) && !isLoading }
    func pasteClipboard() {
        do {
            let value = try service.clipboard()
            if !value.text.isEmpty { text += (text.isEmpty ? "" : "\n") + value.text }
            attachments.append(contentsOf: value.attachments); focusToken += 1
        } catch { self.error = error.localizedDescription }
    }
    func drop(_ providers: [NSItemProvider]) {
        guard !isLoading else { return }
        isLoading = true
        DropReader.read(providers, service: service) { [weak self] text, attachments, error in
            guard let self else { return }
            if !text.isEmpty { self.text += (self.text.isEmpty ? "" : "\n") + text }
            self.attachments.append(contentsOf: attachments); self.error = error; self.isLoading = false; self.focusToken += 1
        }
    }
    func attachFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                guard let self else { return }
                for url in panel.urls { do { self.attachments.append(try self.service.fromFile(url)) } catch { self.error = error.localizedDescription } }
                self.focusToken += 1
            }
        }
    }
    func remove(_ attachment: Attachment) { service.discard([attachment]); attachments.removeAll { $0.id == attachment.id } }
    func clear() { service.discard(attachments); attachments = []; text = ""; error = nil }
    @discardableResult func save(detectTags: Bool) -> Idea? {
        guard canSave, let idea = store.create(text, categoryID: categoryID.flatMap { id in store.categories.contains { $0.id == id } ? id : nil }, attachments: attachments, detectTags: detectTags) else {
            if canSave { error = store.errorMessage ?? "The idea could not be saved. Your draft is still here." }; return nil
        }
        text = ""; attachments = []; error = nil; saved = true; lastSavedID = idea.id; focusToken += 1
        Task { @MainActor [weak self] in try? await Task.sleep(for: .seconds(1.5)); self?.saved = false }
        return idea
    }
}
