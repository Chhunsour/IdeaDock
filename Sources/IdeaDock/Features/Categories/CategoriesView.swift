import SwiftUI

struct CategoriesView: View {
    let store: IdeaStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var icon = "folder"
    @ViewState private var accent = "orange"
    private let icons = ["folder", "app", "globe", "sparkle", "square.on.circle", "ladybug", "magnifyingglass", "text.bubble", "briefcase", "person", "hammer", "terminal", "lightbulb", "bolt", "flag", "book"]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Categories").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            Text("A place for everything, when you’re ready.").foregroundStyle(.secondary).font(.system(size: 12))
            ScrollView {
                VStack(spacing: 9) { ForEach(store.categories) { category in CategoryEditRow(store: store, category: category, icons: icons) } }
            }
            Divider()
            HStack {
                Menu { ForEach(icons, id: \.self) { symbol in Button { icon = symbol } label: { Label(symbol, systemImage: symbol) } } } label: { Image(systemName: icon) }.frame(width: 40)
                TextField("New category", text: $name).onSubmit(add)
                Picker("Accent", selection: $accent) { ForEach(["orange", "blue", "green", "purple", "rose", "gray"], id: \.self) { Text($0.capitalized).tag($0) } }.labelsHidden().frame(width: 95)
                Button("Add", action: add).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 570, height: 520).tint(.dockAccent)
    }
    private func add() { let value = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; store.addCategory(value, icon: icon, accent: accent); name = "" }
}
private struct CategoryEditRow: View {
    let store: IdeaStore
    @Bindable var category: IdeaCategory
    let icons: [String]
    @ViewState private var confirmingDelete = false
    var body: some View {
        HStack {
            Menu { ForEach(icons, id: \.self) { symbol in Button { category.icon = symbol; _ = store.save() } label: { Label(symbol, systemImage: symbol) } } } label: { Image(systemName: category.icon).foregroundStyle(Color.categoryAccent(category.accent)) }.frame(width: 40).disabled(category.isInbox)
            TextField("Category name", text: $category.name).textFieldStyle(.plain).disabled(category.isInbox).onSubmit { _ = store.save() }.onChange(of: category.name) { _, _ in _ = store.save() }
            Picker("Accent", selection: $category.accent) { ForEach(["orange", "blue", "green", "purple", "rose", "gray"], id: \.self) { Text($0.capitalized).tag($0) } }.labelsHidden().frame(width: 90).onChange(of: category.accent) { _, _ in _ = store.save() }
            QuietIconButton(icon: "chevron.up", label: "Move category up") { store.moveCategory(category, offset: -1) }.disabled(category.isInbox)
            QuietIconButton(icon: "chevron.down", label: "Move category down") { store.moveCategory(category, offset: 1) }.disabled(category.isInbox)
            QuietIconButton(icon: "trash", label: "Delete category") { confirmingDelete = true }.disabled(category.isInbox)
        }.padding(.vertical, 4)
        .alert("Delete \(category.name)?", isPresented: $confirmingDelete) { Button("Delete", role: .destructive) { store.deleteCategory(category) }; Button("Cancel", role: .cancel) {} } message: { Text("Its ideas will move to Inbox.") }
    }
}
