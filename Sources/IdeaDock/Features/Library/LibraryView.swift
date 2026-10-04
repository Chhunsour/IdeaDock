import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var state: WorkspaceState
    @ViewState private var showCategories = false
    @ViewState private var categoriesExpanded = false
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if state.showSidebar && geometry.size.width >= 880 && !state.showEditorOnly {
                    sidebar.frame(width: 190)
                    Divider()
                }
                if !state.showEditorOnly {
                    VStack(spacing: 0) { listHeader; Divider(); ideasList; listFooter }.frame(minWidth: 240, idealWidth: 300, maxWidth: geometry.size.width < 880 ? 280 : 330).background(Color.dockListSurface)
                    Divider()
                }
                Group {
                    if let idea = state.selected { IdeaEditor(state: state, idea: idea).id(idea.id) }
                    else { EmptyLibraryView(searching: state.visibleIdeas.isEmpty && (!state.search.isEmpty || state.filter != nil || state.dateFilter != .anyTime), title: state.visibleIdeas.isEmpty ? "Your next idea starts here." : "Select a note to open it.", hasNotes: !state.visibleIdeas.isEmpty, action: state.capture) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color.dockCanvas)
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier, UTType.url.identifier, UTType.plainText.identifier], isTargeted: nil) { providers in state.captureDrop(providers); return true }
        .tint(.dockAccent)
        .frame(minWidth: 620, minHeight: 430)
        .sheet(isPresented: $showCategories) { CategoriesView(store: state.store) }
        .alert("Something needs attention", isPresented: Binding(get: { state.store.errorMessage != nil }, set: { if !$0 { state.store.errorMessage = nil } })) { Button("OK") { state.store.errorMessage = nil } } message: { Text(state.store.errorMessage ?? "") }
        .onChange(of: state.selectedID) { _, id in if id != nil { searchFocused = false } }
        .onChange(of: state.searchFocusToken) { _, _ in listFocused = false; searchFocused = true }
        .onChange(of: state.listFocusToken) { _, _ in searchFocused = false; listFocused = true }
        .onChange(of: state.search) { _, query in
            // Ordinary search finds captured notes without requiring the user
            // to remember which category they chose months ago.
            if !query.isEmpty, state.scope != .archive { state.scope = .recent }
            if let selected = state.selectedID, !state.visibleIdeas.contains(where: { $0.id == selected }) { state.selectedID = nil }
        }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").foregroundStyle(Color.dockAccent).font(.system(size: 18, weight: .semibold))
                Text("IdeaDock").font(.system(size: 16, weight: .semibold))
                Spacer()
            }.padding(.horizontal, 19).padding(.top, 24).padding(.bottom, 20)
            List(selection: Binding(get: { state.scope }, set: { state.navigate($0) })) {
                Section {
                    ForEach([LibraryScope.recent, .today, .pinned, .favorites, .images, .links, .inbox, .archive], id: \.self) { scope in
                        HStack {
                            Label { Text(scope.label) } icon: { Image(systemName: scope.icon).foregroundStyle(scope == state.scope ? Color.dockAccent : .secondary) }.font(.system(size: 13))
                            Spacer()
                            if scope == .today || scope == .pinned {
                                let count = state.store.filtered(scope: scope, query: "", kind: nil).count
                                if count > 0 { Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
                            }
                        }.tag(scope).padding(.vertical, 3)
                    }
                }
                Section(isExpanded: $categoriesExpanded) {
                    ForEach(state.store.categories.filter { !$0.isInbox }) { category in
                        Label { Text(category.name).font(.system(size: 13)) } icon: { Image(systemName: category.icon).foregroundStyle(state.scope == .category(category.id) ? Color.categoryAccent(category.accent) : Color.categoryAccent(category.accent).opacity(0.65)) }
                            .tag(LibraryScope.category(category.id)).padding(.vertical, 3)
                            .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                                guard let provider = providers.first else { return false }
                                provider.loadObject(ofClass: NSString.self) { value, _ in
                                    guard let value = value as? String, value.hasPrefix("ideadock:"), let id = UUID(uuidString: String(value.dropFirst(9))) else { return }
                                    Task { @MainActor in if let idea = state.store.ideas.first(where: { $0.id == id }) { idea.categoryID = category.id; state.store.changed(idea) } }
                                }; return true
                            }
                    }
                } header: {
                    HStack {
                        Text("Categories").help("Optional organization")
                        Spacer()
                        Button { showCategories = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Manage categories").accessibilityLabel("Manage categories")
                    }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            HStack {
                QuietIconButton(icon: "gearshape", label: "Settings", action: state.settings)
                Spacer()
                QuietIconButton(icon: "rectangle.on.rectangle", label: "Toggle floating capture", action: state.toggleFloating)
            }.padding(.horizontal, 15).padding(.vertical, 10)
        }.background(.regularMaterial)

    }
    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(state.scopeTitle).font(.system(size: 21, weight: .semibold))
                Spacer()
                QuietIconButton(icon: "sidebar.left", label: "Toggle sidebar") { state.showSidebar.toggle() }
                QuietIconButton(icon: "square.and.pencil", label: "New idea", action: state.capture)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all notes", text: $state.search).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search all notes")
                    .onSubmit { state.selectedID = state.visibleIdeas.first?.id; searchFocused = false; listFocused = false; state.focusEditor() }
                    .onKeyPress(.downArrow) { state.moveSelection(1); searchFocused = false; listFocused = true; return .handled }
                    .onExitCommand { searchFocused = false; state.search = "" }
                if !state.search.isEmpty { Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).accessibilityLabel("Clear search") }
            }.font(.system(size: 13)).padding(8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Menu {
                    Button("All types") { state.filter = nil }
                    Divider()
                    ForEach(ContentKind.allCases) { kind in Button { state.filter = kind } label: { Label(kind.label, systemImage: kind.icon) } }
                } label: { HStack(spacing: 4) { Text(state.filter?.label ?? "All types"); Image(systemName: "chevron.down").font(.system(size: 9)) } }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).foregroundStyle(.secondary)
                if state.scope != .today { Menu {
                    ForEach(CaptureDateFilter.allCases) { range in Button(range.label) { state.dateFilter = range; state.selectedID = nil } }
                } label: { HStack(spacing: 4) { Text(state.dateFilter.label); Image(systemName: "chevron.down").font(.system(size: 9)) } }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).foregroundStyle(.secondary).accessibilityLabel("Capture time filter") }
                Spacer()
                Text("\(state.visibleIdeas.count) \(state.visibleIdeas.count == 1 ? "note" : "notes")").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }.padding(.horizontal, 18).padding(.top, 23).padding(.bottom, 14)
    }
    @ViewBuilder private var ideasList: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
        let values = state.store.filtered(scope: state.scope, query: state.search, kind: state.filter, dateFilter: state.dateFilter, now: context.date)
        if values.isEmpty {
            VStack(spacing: 7) {
                Text(!state.search.isEmpty || state.filter != nil || state.dateFilter != .anyTime ? "No matching notes" : state.scope == .archive ? "Nothing archived" : state.scope == .today ? "Nothing captured today" : "Nothing here yet").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text(!state.search.isEmpty || state.filter != nil || state.dateFilter != .anyTime ? "Try another word or time range." : "Capture something and keep moving.").font(.system(size: 11)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
        } else {
            List(selection: $state.selectedID) {
                if state.scope == .recent {
                    ForEach(CaptureHistory.sections(values, now: context.date)) { section in
                        Section {
                            ForEach(section.ideas) { idea in ideaListRow(idea, now: context.date) }
                        } header: { Text(section.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).textCase(nil) }
                    }
                } else {
                ForEach(values) { idea in
                    ideaListRow(idea, now: context.date)
                }
                }
            }.listStyle(.inset).scrollContentBackground(.hidden)
                .focusable().focused($listFocused)
                .onAppear { if !searchFocused && state.editorFocusID == nil { listFocused = true } }
                .onKeyPress(.downArrow) { state.moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { state.moveSelection(-1); return .handled }
                .onKeyPress(.return) {
                    guard state.selectedID != nil else { return .ignored }
                    listFocused = false
                    if (NSApp.keyWindow?.frame.width ?? 0) < 880 { state.showEditorOnly = true }
                    state.focusEditor()
                    return .handled
                }
        }
        }
    }
    private func ideaListRow(_ idea: Idea, now: Date) -> some View {
        Button {
            state.selectedID = idea.id
            searchFocused = false
            listFocused = true
        } label: {
            IdeaRow(idea: idea, store: state.store, now: now)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).tag(idea.id)
            .contextMenu { IdeaContextMenu(state: state, idea: idea) }
            .onDrag { NSItemProvider(object: "ideadock:\(idea.id.uuidString)" as NSString) }
    }
    private var listFooter: some View {
        HStack { Image(systemName: "lock"); Text("Stored on this Mac"); Spacer(); Button("⌘ K", action: state.palette).buttonStyle(.plain).help("Command palette") }
            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 18).padding(.vertical, 10)
    }
}
struct IdeaRow: View {
    let idea: Idea
    let store: IdeaStore
    var now: Date = .now
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let attachment = idea.attachments.first(where: { $0.kind == "image" }), let path = attachment.relativePath {
                ImageThumbnail(url: store.attachmentURL(path), width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(idea.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    if idea.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color.dockAccent) }
                    if idea.isFavorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                if !idea.content.isEmpty {
                    Text(idea.kind == .link ? (URL(string: idea.sourceURL ?? "")?.host ?? idea.content) : idea.content.replacingOccurrences(of: "\n", with: " "))
                        .font(idea.kind == .code ? .system(size: 11, design: .monospaced) : .system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 5) {
                    if idea.kind != .text { Image(systemName: idea.kind.icon).font(.system(size: 9)) }
                    CaptureTimestamp(date: idea.createdAt, compact: true, now: now)
                    if let tag = idea.tags.first { Text("·"); Text("#\(tag)").lineLimit(1) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }
}
struct IdeaContextMenu: View {
    let state: WorkspaceState
    let idea: Idea
    var body: some View {
        Button("Open") { state.selectedID = idea.id; state.focusEditor() }
        Button(idea.isPinned ? "Unpin" : "Pin") { idea.isPinned.toggle(); state.store.changed(idea) }
        Button(idea.isFavorite ? "Remove Favorite" : "Favorite") { idea.isFavorite.toggle(); state.store.changed(idea) }
        Menu("Change Category") { ForEach(state.store.categories) { category in Button(category.name) { idea.categoryID = category.id; state.store.changed(idea) } } }
        Button("Add Tag…") { state.tagRequestID = idea.id; state.selectedID = idea.id }
        Button("Float on Desktop") { state.floatIdea(idea) }
        Divider()
        Button(idea.kind == .code ? "Copy Code" : "Copy Text") { state.copy(idea.content) }
        if let url = idea.sourceURL { Button("Copy Link") { state.copy(url) } }
        if let attachment = idea.attachments.first {
            Button("Reveal Attachment") { do { try state.attachmentService.reveal(attachment) } catch { state.store.errorMessage = error.localizedDescription } }
        }
        Divider()
        Button(idea.isArchived ? "Restore to Library" : "Archive") { state.store.archive(idea) }
        Button("Delete…", role: .destructive) { state.deleteWithConfirmation(idea) }
    }
}
extension Notification.Name { static let ideaAddTag = Notification.Name("IdeaDock.addTag") }

extension LibraryView {
    /// Human-friendly search result count formatter.
    func formattedResultSummary(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
    }
}
