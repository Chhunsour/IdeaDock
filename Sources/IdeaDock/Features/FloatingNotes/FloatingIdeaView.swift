import SwiftUI

struct FloatingIdeaView: View {
    let state: WorkspaceState
    let preferences: Preferences
    let ideaID: UUID
    var body: some View {
        Group {
            if let idea = state.store.ideas.first(where: { $0.id == ideaID }) { FloatingNoteEditor(store: state.store, preferences: preferences, idea: idea) }
            else { VStack(spacing: 12) { Image(systemName: "archivebox"); Text("This idea was deleted.").font(.system(size: 13)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.tint(.dockAccent)
    }
}
private struct FloatingNoteEditor: View {
    let store: IdeaStore
    let preferences: Preferences
    @Bindable var idea: Idea
    @ViewState private var saveTask: Task<Void, Never>?
    @ViewState private var savePending = false
    @ViewState private var savedTitle: String?
    @ViewState private var savedContent: String?

    init(store: IdeaStore, preferences: Preferences, idea: Idea) {
        self.store = store
        self.preferences = preferences
        _idea = Bindable(wrappedValue: idea)
        _savedTitle = ViewState(initialValue: idea.title)
        _savedContent = ViewState(initialValue: idea.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WindowDragRegion(label: "Drag floating note")
                .overlay { Capsule().fill(Color.primary.opacity(0.13)).frame(width: 28, height: 3).allowsHitTesting(false) }
                .frame(height: 12).padding(.top, 12)
            HStack { TextField("Title", text: $idea.title).textFieldStyle(.plain).font(.system(size: 17, weight: .semibold)); Image(systemName: "pin.fill").foregroundStyle(Color.dockAccent).font(.system(size: 11)) }
            TextEditor(text: $idea.content).font(idea.kind == .code ? .system(size: 12, design: .monospaced) : .system(size: 14)).scrollContentBackground(.hidden).lineSpacing(4).accessibilityLabel("Floating idea body")
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack {
                    CaptureTimestamp(date: idea.createdAt, updatedAt: idea.updatedAt, compact: true, now: context.date)
                        .lineLimit(1).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(store.lastSaveFailed ? "Changes need saving" : savePending ? "Saving…" : "Autosaved")
                        .fixedSize()
                }
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(18).background { if preferences.translucent { Rectangle().fill(.regularMaterial).overlay(Color.dockCanvas.opacity(0.65)) } else { Color.dockCanvas } }
        .onChange(of: idea.content) { _, _ in schedule() }.onChange(of: idea.title) { _, _ in schedule() }
        .onDisappear { saveTask?.cancel(); flushSave() }
    }
    private func schedule() {
        saveTask?.cancel()
        guard idea.title != savedTitle || idea.content != savedContent else {
            saveTask = nil; savePending = false; return
        }
        savePending = true
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, store.ideas.contains(where: { $0 === idea }) else { return }
            flushSave()
        }
    }
    private func flushSave() {
        saveTask = nil
        guard let savedTitle, let savedContent,
              store.ideas.contains(where: { $0 === idea }) else { return }
        guard idea.title != savedTitle || idea.content != savedContent else { savePending = false; return }
        savePending = true
        store.changed(idea)
        guard !store.lastSaveFailed else { return }
        self.savedTitle = idea.title; self.savedContent = idea.content; savePending = false
    }
}
