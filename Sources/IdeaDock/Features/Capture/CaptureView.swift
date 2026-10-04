import SwiftUI
import UniformTypeIdentifiers

struct CaptureView: View {
    @Bindable var draft: CaptureDraft
    let preferences: Preferences
    var quick = true
    var collapsed = false
    var onClose: () -> Void = {}
    var onExpand: () -> Void = {}
    var onCollapse: () -> Void = {}
    var onLibrary: () -> Void = {}
    var onOpen: (UUID) -> Void = { _ in }
    var onSaved: (Idea) -> Void = { _ in }
    @ViewState private var dropTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if collapsed { collapsedBar }
            else {
                HStack(spacing: 8) {
                    WindowDragRegion(label: quick ? "Drag quick capture" : "Drag capture note", allowsDocking: !quick)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.dockAccent)
                                Text(quick ? "Quick capture" : "IdeaDock").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            }.allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity).frame(height: 28)
                    if !quick {
                        QuietIconButton(icon: preferences.alwaysOnTop ? "pin.fill" : "pin", label: "Keep floating capture on top", active: preferences.alwaysOnTop) { preferences.alwaysOnTop.toggle(); NotificationCenter.default.post(name: .ideaApplyPreferences, object: nil) }
                        QuietIconButton(icon: "minus", label: "Collapse capture", action: onCollapse)
                    }
                    QuietIconButton(icon: "xmark", label: "Close capture", action: onClose)
                }.padding(.horizontal, 19).padding(.top, 12).padding(.bottom, 4)
                ZStack(alignment: .topLeading) {
                    if draft.text.isEmpty { VStack(alignment: .leading, spacing: 8) { Text("What’s on your mind?").font(.system(size: quick ? 23 : 20, weight: .medium)); Text("Type, paste, or drop anything.").font(.system(size: 12)).foregroundStyle(.tertiary) }.padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                    CaptureTextView(text: $draft.text, onSubmit: save, onEscape: onClose, onPasteAttachments: draft.pasteClipboard, submitWithReturn: quick, focusToken: draft.focusToken)
                }.padding(.horizontal, 20).padding(.top, 9).frame(minHeight: quick ? 120 : 110)
                if !draft.attachments.isEmpty { attachmentStrip.padding(.horizontal, 22).padding(.vertical, 9) }
                if let error = draft.error { Text(error).font(.system(size: 11)).foregroundStyle(.red).padding(.horizontal, 22).padding(.bottom, 8).fixedSize(horizontal: false, vertical: true) }
                if dropTargeted { Label("Drop to attach", systemImage: "arrow.down.doc").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.dockAccent).frame(maxWidth: .infinity).padding(.vertical, 7) }
                if !quick, !draft.canSave, !draft.isLoading,
                   let idea = draft.store.ideas.first(where: { $0.id == draft.lastSavedID && !$0.isArchived }) {
                    Button { onOpen(idea.id) } label: {
                        HStack(spacing: 6) {
                            Text("Last saved")
                            CaptureTimestamp(date: idea.createdAt, compact: true)
                            Text(idea.title).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 9))
                        }.font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.horizontal, 22).padding(.bottom, 10)
                        .accessibilityLabel("Open last saved note: \(idea.title)").help("Saved at \(idea.createdAt.formatted(date: .abbreviated, time: .shortened)). Click to reopen.")
                }
                Divider().opacity(0.5)
                HStack(spacing: 4) {
                    Menu {
                        ForEach(draft.store.categories) { category in Button { draft.categoryID = category.id } label: { Label(category.name, systemImage: category.icon) } }
                    } label: { Label(draft.store.categoryName(draft.categoryID ?? draft.store.inboxID), systemImage: "tray") }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).foregroundStyle(.secondary).help("Optional category. New captures use your default destination.")
                    Spacer(minLength: 8)
                    if draft.saved { Label("Saved", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(.secondary) }
                    if draft.isLoading { ProgressView().controlSize(.small) }
                    QuietIconButton(icon: "doc.on.clipboard", label: "Paste Clipboard", action: draft.pasteClipboard)
                    QuietIconButton(icon: "paperclip", label: "Attach file", action: draft.attachFiles)
                    if !quick { QuietIconButton(icon: "rectangle.split.3x1", label: "Open library", action: onLibrary) }
                    Button(action: save) { HStack(spacing: 5) { Text("Save"); Text(quick ? "↵" : "⌘ ↵").foregroundStyle(.secondary) }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6) }
                        .buttonStyle(.plain).background(draft.canSave ? Color.dockAccent.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5)).foregroundStyle(draft.canSave ? Color.dockAccent : .secondary).disabled(!draft.canSave).help(quick ? "Return saves · Shift Return adds a line" : "Command Return saves")
                }.padding(.horizontal, 19).padding(.vertical, 11)
            }
        }
        .background {
            if preferences.translucent { Rectangle().fill(.regularMaterial).overlay(Color.dockCanvas.opacity(0.65)) }
            else { Color.dockCanvas }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 11).stroke(Color.dockAccent.opacity(0.6), lineWidth: 2).padding(2) } }
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .tint(.dockAccent)
        .preferredColorScheme(preferences.preferredColorScheme)
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier, UTType.url.identifier, UTType.plainText.identifier], isTargeted: $dropTargeted) { providers in if collapsed { onExpand() }; draft.drop(providers); return true }
    }
    private var collapsedBar: some View {
        HStack(spacing: 9) {
            WindowDragRegion(label: "Drag capture note")
                .overlay { Image(systemName: "circle.grid.2x3.fill").font(.system(size: 10)).foregroundStyle(.tertiary).allowsHitTesting(false) }
                .frame(width: 18, height: 26)
            Button(action: onExpand) {
                Text(draft.canSave ? "Continue your idea" : "Capture an idea")
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
            QuietIconButton(icon: "plus", label: "Expand capture", action: onExpand)
        }.padding(.horizontal, 17).padding(.vertical, 10)
    }
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) { ForEach(draft.attachments) { attachment in
                HStack(spacing: 6) {
                    if attachment.kind == "image", let path = attachment.relativePath { ImageThumbnail(url: draft.store.attachmentURL(path), width: 36, height: 30) }
                    else { Image(systemName: "doc").foregroundStyle(.secondary) }
                    Text(attachment.name).lineLimit(1).frame(maxWidth: 150)
                    Button { draft.remove(attachment) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).accessibilityLabel("Remove \(attachment.name)")
                }.font(.system(size: 11)).padding(5).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            } }
        }.frame(height: 40)
    }
    private func save() { if let idea = draft.save(detectTags: preferences.detectTags) { onSaved(idea) } }
}
extension Notification.Name { static let ideaApplyPreferences = Notification.Name("IdeaDock.applyPreferences") }
