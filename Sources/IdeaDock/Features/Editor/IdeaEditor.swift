import SwiftUI
import UniformTypeIdentifiers

struct IdeaEditor: View {
    let state: WorkspaceState
    @Bindable var idea: Idea
    @ViewState private var preview = false
    @ViewState private var tagText = ""
    @ViewState private var showLink = false
    @ViewState private var linkText = ""
    @ViewState private var savePending = false
    @ViewState private var savedTitle: String?
    @ViewState private var savedContent: String?
    @ViewState private var dropTargeted = false
    @ViewState private var saveTask: Task<Void, Never>?
    @FocusState private var bodyFocused: Bool
    @FocusState private var tagFocused: Bool

    init(state: WorkspaceState, idea: Idea) {
        self.state = state
        _idea = Bindable(wrappedValue: idea)
        _savedTitle = ViewState(initialValue: idea.title)
        _savedContent = ViewState(initialValue: idea.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Menu { ForEach(state.store.categories) { category in Button(category.name) { idea.categoryID = category.id; state.store.changed(idea) } } } label: { Label(state.store.categoryName(idea.categoryID), systemImage: "folder") }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        CaptureTimestamp(date: idea.createdAt, updatedAt: idea.updatedAt).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    TextField("Untitled idea", text: $idea.title, axis: .vertical).textFieldStyle(.plain).font(.system(size: 27, weight: .semibold)).lineLimit(1...4).accessibilityLabel("Idea title")
                    if preview { MarkdownPreview(text: idea.content, toggle: toggleChecklist, copy: state.copy).frame(maxWidth: .infinity, alignment: .leading) }
                    else { TextEditor(text: $idea.content).font(idea.kind == .code ? .system(size: 13, design: .monospaced) : .system(size: 15)).lineSpacing(6).scrollContentBackground(.hidden).frame(minHeight: 250).focused($bodyFocused).accessibilityLabel("Idea body") }
                    if let urlString = idea.sourceURL, let url = URL(string: urlString) {
                        HStack(spacing: 10) {
                            Image(systemName: "link").foregroundStyle(Color.dockAccent)
                            VStack(alignment: .leading, spacing: 3) { Text(url.host ?? "Link").font(.system(size: 12, weight: .medium)); Text(urlString).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            Link(destination: url) { Image(systemName: "arrow.up.right") }.help("Open link")
                        }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !idea.attachments.isEmpty { attachments }
                    tagEditor
                    Spacer(minLength: 25)
                }.padding(.horizontal, 30).padding(.top, 27)
            }
            HStack { Image(systemName: state.store.lastSaveFailed ? "exclamationmark.circle" : savePending ? "ellipsis" : "checkmark"); Text(state.store.lastSaveFailed ? "Changes need saving" : savePending ? "Saving…" : "Saved on this Mac"); Spacer(); Text(idea.kind.label == "Text" ? "Plain text · Markdown supported" : idea.kind.label) }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 30).padding(.vertical, 12)
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier, UTType.url.identifier, UTType.plainText.identifier], isTargeted: $dropTargeted) { providers in
            DropReader.read(providers, service: state.attachmentService) { text, attachments, error in
                guard state.store.ideas.contains(where: { $0 === idea }) else { state.attachmentService.discard(attachments); return }
                idea.attachments.append(contentsOf: attachments)
                if !text.isEmpty { idea.content += (idea.content.isEmpty ? "" : "\n") + text }
                state.store.changed(idea); if let error { state.store.errorMessage = error }
            }; return true
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 7).stroke(Color.dockAccent.opacity(0.5), lineWidth: 2).padding(4).allowsHitTesting(false) } }
        .onChange(of: idea.content) { _, _ in scheduleSave() }
        .onChange(of: idea.title) { _, _ in scheduleSave() }
        .onAppear {
            if state.tagRequestID == idea.id { tagFocused = true; state.tagRequestID = nil }
        }
        .onChange(of: state.tagRequestID) { _, id in if id == idea.id { tagFocused = true; state.tagRequestID = nil } }
        .task(id: state.editorFocusToken) {
            guard state.editorFocusID == idea.id else { return }
            preview = false
            // Let the new TextEditor join the native responder chain first.
            await Task.yield()
            guard !Task.isCancelled, state.editorFocusID == idea.id else { return }
            bodyFocused = true
            state.editorFocusID = nil
        }
        .onKeyPress(.escape) {
            guard bodyFocused || tagFocused else { return .ignored }
            bodyFocused = false
            tagFocused = false
            state.showEditorOnly = false
            state.listFocusToken += 1
            return .handled
        }
        .onDisappear { saveTask?.cancel(); flushSave() }
        .onReceive(NotificationCenter.default.publisher(for: .ideaAddTag)) { note in if note.object as? UUID == idea.id { tagFocused = true } }
        .popover(isPresented: $showLink) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add a link").font(.headline)
                TextField("https://", text: $linkText).frame(width: 290).onSubmit(insertLink)
                HStack { Spacer(); Button("Add link", action: insertLink).keyboardShortcut(.defaultAction) }
            }.padding(18)
        }
    }
    private var toolbar: some View {
        HStack(spacing: 4) {
            if state.showEditorOnly { QuietIconButton(icon: "chevron.left", label: "Back to list") { state.showEditorOnly = false } }
            QuietIconButton(icon: "pin", label: idea.isPinned ? "Unpin idea" : "Pin idea", active: idea.isPinned) { idea.isPinned.toggle(); state.store.changed(idea) }
            QuietIconButton(icon: "star", label: "Favorite idea", active: idea.isFavorite) { idea.isFavorite.toggle(); state.store.changed(idea) }
            Spacer()
            QuietIconButton(icon: preview ? "pencil" : "text.alignleft", label: preview ? "Edit text" : "Preview Markdown", active: preview) { preview.toggle() }
            QuietIconButton(icon: "checklist", label: "Add checklist item") { idea.content += (idea.content.isEmpty ? "" : "\n") + "- [ ] "; preview = false; bodyFocused = true }
            QuietIconButton(icon: "link", label: "Add link") { linkText = idea.sourceURL ?? ""; showLink = true }
            QuietIconButton(icon: "paperclip", label: "Attach file") { state.attachFiles(idea) }
            Menu {
                Button("Float on Desktop") { state.floatIdea(idea) }
                Button(idea.kind == .code ? "Copy Code" : "Copy Text") { state.copy(idea.content) }
                Button(idea.isArchived ? "Restore" : "Archive") { state.store.archive(idea); state.selectedID = nil }
                Divider()
                Button("Delete…", role: .destructive) { state.deleteWithConfirmation(idea) }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Idea actions")
        }.padding(.horizontal, 19).padding(.vertical, 11)
    }
    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !idea.tags.isEmpty {
                // Tags remain editable without making metadata dominate the idea.
                FlowTags(tags: idea.tags) { value in idea.tags.removeAll { $0 == value }; state.store.changed(idea) }
            }
            HStack(spacing: 6) {
                Image(systemName: "number").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("Add a tag", text: $tagText).textFieldStyle(.plain).font(.system(size: 12)).focused($tagFocused).onSubmit {
                    let value = tagText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").lowercased()
                    guard !value.isEmpty else { return }
                    if !idea.tags.contains(value) { idea.tags.append(value) }; tagText = ""; state.store.changed(idea)
                }.accessibilityLabel("Add a tag")
            }
        }
    }
    private var attachments: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(idea.attachments) { attachment in
                AttachmentPreview(attachment: attachment, store: state.store, service: state.attachmentService,
                                  onRemove: { state.store.removeAttachment(attachment, from: idea) },
                                  onError: { state.store.errorMessage = $0 })
            }
        }
    }
    private func scheduleSave() {
        saveTask?.cancel()
        guard idea.title != savedTitle || idea.content != savedContent else {
            saveTask = nil; savePending = false; return
        }
        savePending = true
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, state.store.ideas.contains(where: { $0 === idea }) else { return }
            flushSave()
        }
    }
    private func flushSave() {
        saveTask = nil
        guard let savedTitle, let savedContent,
              state.store.ideas.contains(where: { $0 === idea }) else { return }
        guard idea.title != savedTitle || idea.content != savedContent else { savePending = false; return }
        savePending = true
        if state.detectTags() { idea.tags = Array(Set(idea.tags + ContentAnalysis.tags(idea.content))).sorted() }
        state.store.changed(idea)
        guard !state.store.lastSaveFailed else { return }
        self.savedTitle = idea.title; self.savedContent = idea.content; savePending = false
    }
    private func insertLink() {
        guard let url = URL(string: linkText), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        if !idea.content.contains(url.absoluteString) { idea.content += (idea.content.isEmpty ? "" : "\n") + url.absoluteString }
        state.store.changed(idea); showLink = false
    }
    private func toggleChecklist(_ index: Int) {
        var lines = idea.content.components(separatedBy: "\n")
        guard lines.indices.contains(index) else { return }
        if lines[index].contains("[ ]") { lines[index] = lines[index].replacingOccurrences(of: "[ ]", with: "[x]") }
        else { lines[index] = lines[index].replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]") }
        idea.content = lines.joined(separator: "\n"); state.store.changed(idea)
    }
}
private struct FlowTags: View {
    let tags: [String]
    let remove: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 5) {
            ForEach(tags, id: \.self) { tag in HStack(spacing: 4) { Text("#\(tag)").lineLimit(1); Button { remove(tag) } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain).accessibilityLabel("Remove tag \(tag)") }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 4).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4)) }
        }
    }
}
private struct MarkdownPreview: View {
    let text: String
    let toggle: (Int) -> Void
    let copy: (String) -> Void
    private struct Block: Identifiable {
        let id: Int
        let content: String
        var code = false
    }
    private var blocks: [Block] {
        var result: [Block] = []
        var codeStart: Int?
        var code: [String] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let start = codeStart { result.append(Block(id: start, content: code.joined(separator: "\n"), code: true)); code = []; codeStart = nil }
                else { codeStart = index }
            } else if codeStart != nil { code.append(line) }
            else { result.append(Block(id: index, content: line)) }
        }
        if let start = codeStart { result.append(Block(id: start, content: code.joined(separator: "\n"), code: true)) }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                let line = block.content
                if block.code {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Code").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("Copy") { copy(line) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Color.dockAccent) }
                        Text(line).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(13).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                    Button { toggle(block.id) } label: { HStack(alignment: .top, spacing: 8) { Image(systemName: line.hasPrefix("- [ ]") ? "square" : "checkmark.square.fill").foregroundStyle(Color.dockAccent); Text(String(line.dropFirst(6))).foregroundStyle(.primary) } }.buttonStyle(.plain)
                } else if line.hasPrefix("# ") { Text(String(line.dropFirst(2))).font(.title2.weight(.semibold)) }
                else if line.hasPrefix("## ") { Text(String(line.dropFirst(3))).font(.headline) }
                else { Text((try? AttributedString(markdown: line)) ?? AttributedString(line)).textSelection(.enabled) }
            }
        }.font(.system(size: 15)).lineSpacing(5).frame(minHeight: 250, alignment: .topLeading)
    }
}
