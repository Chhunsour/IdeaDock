import SwiftUI

struct CommandPaletteView: View {
    let state: WorkspaceState
    let contextIdea: Idea?
    let close: () -> Void
    @ViewState private var query = ""
    @ViewState private var selected = 0
    @FocusState private var focused: Bool
    private struct Command: Identifiable {
        let id: String
        let title: String
        let icon: String
        let action: () -> Void
    }
    private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsRecentFirst: Bool { searchQuery.isEmpty }
    private var commands: [Command] {
        var values = [
            Command(id: "new", title: "New Idea", icon: "square.and.pencil", action: state.capture),
            Command(id: "search", title: "Search Ideas", icon: "magnifyingglass", action: state.focusSearch),
            Command(id: "today", title: "Open Today", icon: "calendar", action: { state.openScope(.today) }),
            Command(id: "all", title: "Open All Notes", icon: "text.alignleft", action: { state.openScope(.recent) }),
            Command(id: "inbox", title: "Open Inbox", icon: "tray", action: { state.openScope(.inbox) }),
            Command(id: "pinned", title: "Open Pinned", icon: "pin", action: { state.openScope(.pinned) }),
            Command(id: "floating", title: "Toggle Floating Window", icon: "rectangle.on.rectangle", action: state.toggleFloating),
            Command(id: "clipboard", title: "Capture Clipboard", icon: "doc.on.clipboard", action: state.pasteClipboard),
            Command(id: "settings", title: "Open Settings", icon: "gearshape", action: state.settings)
        ]
        if let idea = contextIdea {
            values.insert(Command(id: "pin", title: idea.isPinned ? "Unpin Idea" : "Pin Idea", icon: "pin", action: { idea.isPinned.toggle(); state.store.changed(idea) }), at: 2)
            values.insert(Command(id: "archive", title: idea.isArchived ? "Restore Idea" : "Archive Idea", icon: "archivebox", action: { state.store.archive(idea); state.selectedID = nil }), at: 3)
            values.append(contentsOf: state.store.categories.map { category in Command(id: category.id.uuidString, title: "Move to \(category.name)", icon: category.icon, action: { idea.categoryID = category.id; state.store.changed(idea) }) })
        }
        return values.filter { searchQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }
    private var notes: [Idea] {
        let matches = state.store.filtered(scope: .recent, query: searchQuery, kind: nil).sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
        return Array(matches.prefix(showsRecentFirst ? 3 : 8))
    }
    private var resultCount: Int { commands.count + notes.count }
    private var commandStartIndex: Int { showsRecentFirst ? notes.count : 0 }
    private var noteStartIndex: Int { showsRecentFirst ? 0 : commands.count }
    private var selectedIsNote: Bool { notes.indices.contains(selected - noteStartIndex) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search notes or commands…", text: $query).textFieldStyle(.plain).font(.system(size: 17)).focused($focused).onSubmit(runSelected); Text("esc").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(21)
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if showsRecentFirst { notesSection; commandsSection }
                        else { commandsSection; notesSection }
                        if resultCount == 0 {
                            Text("No matching notes or commands").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 25)
                        }
                    }.padding(10)
                }.frame(maxHeight: 360).onChange(of: selected) { _, value in reader.scrollTo(value) }
            }
            Divider()
            HStack { Text("↑ ↓ to navigate"); Spacer(); Text(selectedIsNote ? "↵ to open" : "↵ to run") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 21).padding(.vertical, 10)
        }.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 11)).tint(.dockAccent)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selected = 0 }
        .onChange(of: resultCount) { _, count in selected = min(selected, max(0, count - 1)) }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(0, resultCount - 1)); return .handled }
        .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
        .onExitCommand(perform: close)
    }
    @ViewBuilder private var commandsSection: some View {
        if !commands.isEmpty {
            sectionHeading("Commands", first: !showsRecentFirst || notes.isEmpty)
            ForEach(Array(commands.enumerated()), id: \.element.id) { offset, command in
                let index = commandStartIndex + offset
                Button { close(); command.action() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: command.icon).frame(width: 18).foregroundStyle(index == selected ? Color.dockAccent : .secondary)
                        Text(command.title)
                        Spacer()
                        if index == selected { Image(systemName: "return").foregroundStyle(.tertiary) }
                    }.font(.system(size: 13)).padding(.horizontal, 13).padding(.vertical, 11).contentShape(Rectangle())
                }.buttonStyle(.plain).background(index == selected ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6)).id(index)
            }
        }
    }
    @ViewBuilder private var notesSection: some View {
        if !notes.isEmpty {
            sectionHeading(showsRecentFirst ? "Recent captures" : "Notes", first: showsRecentFirst || commands.isEmpty)
            ForEach(Array(notes.enumerated()), id: \.element.id) { offset, idea in
                let index = noteStartIndex + offset
                Button { close(); state.openIdea(idea.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: idea.kind.icon).frame(width: 18).foregroundStyle(index == selected ? Color.dockAccent : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(idea.title).font(.system(size: 13)).lineLimit(1)
                            Text(snippet(for: idea)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            Text(idea.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 6)
                        if index == selected { Image(systemName: "return").foregroundStyle(.tertiary) }
                    }.padding(.horizontal, 13).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).background(index == selected ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6)).id(index)
            }
        }
    }
    private func sectionHeading(_ title: String, first: Bool) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.top, first ? 5 : 13).padding(.bottom, 5)
    }
    private func snippet(for idea: Idea) -> String {
        let value = idea.content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return value.isEmpty ? idea.attachments.first?.name ?? idea.kind.label : String(value.prefix(140))
    }
    private func runSelected() {
        if selectedIsNote {
            let id = notes[selected - noteStartIndex].id; close(); state.openIdea(id)
        } else {
            let index = selected - commandStartIndex
            guard commands.indices.contains(index) else { return }
            let action = commands[index].action; close(); action()
        }
    }
}
