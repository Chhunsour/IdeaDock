import Foundation
import SwiftData
import Observation

enum ContentKind: String, Codable, CaseIterable, Identifiable {
    case text, image, link, code, file
    var id: String { rawValue }
    var label: String { switch self { case .text: "Text"; case .image: "Images"; case .link: "Links"; case .code: "Code"; case .file: "Files" } }
    var icon: String { switch self { case .text: "text.alignleft"; case .image: "photo"; case .link: "link"; case .code: "chevron.left.forwardslash.chevron.right"; case .file: "doc" } }
}

final class Idea: PersistentModel {
    var id: UUID {
        get { _$observationRegistrar.access(self, keyPath: \.id); return self.getValue(forKey: \.id) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.id) { self.setValue(forKey: \.id, to: newValue) } }
    }
    var title: String {
        get { _$observationRegistrar.access(self, keyPath: \.title); return self.getValue(forKey: \.title) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.title) { self.setValue(forKey: \.title, to: newValue) } }
    }
    var content: String {
        get { _$observationRegistrar.access(self, keyPath: \.content); return self.getValue(forKey: \.content) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.content) { self.setValue(forKey: \.content, to: newValue) } }
    }
    var createdAt: Date {
        get { _$observationRegistrar.access(self, keyPath: \.createdAt); return self.getValue(forKey: \.createdAt) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.createdAt) { self.setValue(forKey: \.createdAt, to: newValue) } }
    }
    var updatedAt: Date {
        get { _$observationRegistrar.access(self, keyPath: \.updatedAt); return self.getValue(forKey: \.updatedAt) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.updatedAt) { self.setValue(forKey: \.updatedAt, to: newValue) } }
    }
    var isPinned: Bool {
        get { _$observationRegistrar.access(self, keyPath: \.isPinned); return self.getValue(forKey: \.isPinned) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.isPinned) { self.setValue(forKey: \.isPinned, to: newValue) } }
    }
    var isFavorite: Bool {
        get { _$observationRegistrar.access(self, keyPath: \.isFavorite); return self.getValue(forKey: \.isFavorite) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.isFavorite) { self.setValue(forKey: \.isFavorite, to: newValue) } }
    }
    var isArchived: Bool {
        get { _$observationRegistrar.access(self, keyPath: \.isArchived); return self.getValue(forKey: \.isArchived) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.isArchived) { self.setValue(forKey: \.isArchived, to: newValue) } }
    }
    var categoryID: UUID {
        get { _$observationRegistrar.access(self, keyPath: \.categoryID); return self.getValue(forKey: \.categoryID) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.categoryID) { self.setValue(forKey: \.categoryID, to: newValue) } }
    }
    var tags: [String] {
        get { _$observationRegistrar.access(self, keyPath: \.tags); return self.getValue(forKey: \.tags) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.tags) { self.setValue(forKey: \.tags, to: newValue) } }
    }
    var contentType: String {
        get { _$observationRegistrar.access(self, keyPath: \.contentType); return self.getValue(forKey: \.contentType) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.contentType) { self.setValue(forKey: \.contentType, to: newValue) } }
    }
    var sourceURL: String? {
        get { _$observationRegistrar.access(self, keyPath: \.sourceURL); return self.getValue(forKey: \.sourceURL) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.sourceURL) { self.setValue(forKey: \.sourceURL, to: newValue) } }
    }
    var sortOrder: Double {
        get { _$observationRegistrar.access(self, keyPath: \.sortOrder); return self.getValue(forKey: \.sortOrder) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.sortOrder) { self.setValue(forKey: \.sortOrder, to: newValue) } }
    }
    var attachments: [Attachment] {
        get { _$observationRegistrar.access(self, keyPath: \.attachments); return self.getValue(forKey: \.attachments) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.attachments) { self.setValue(forKey: \.attachments, to: newValue) } }
    }
    var kind: ContentKind { ContentKind(rawValue: contentType) ?? .text }
    // Explicit PersistentModel conformance keeps SwiftData available with Apple's
    // command-line tools, which do not ship the SwiftData @Model macro plugin.
    private var _$backingData: any BackingData<Idea> = Idea.createBackingData()
    var persistentBackingData: any BackingData<Idea> {
        get { _$backingData }
        set { _$backingData = newValue }
    }
    private let _$observationRegistrar = ObservationRegistrar()
    required init(backingData: any BackingData<Idea>) { persistentBackingData = backingData }
    static var schemaMetadata: [Schema.PropertyMetadata] { [
        Schema.PropertyMetadata(name: "id", keypath: \Idea.id, defaultValue: nil, metadata: Schema.Attribute(.unique)),
        Schema.PropertyMetadata(name: "title", keypath: \Idea.title, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "content", keypath: \Idea.content, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "createdAt", keypath: \Idea.createdAt, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "updatedAt", keypath: \Idea.updatedAt, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "isPinned", keypath: \Idea.isPinned, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "isFavorite", keypath: \Idea.isFavorite, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "isArchived", keypath: \Idea.isArchived, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "categoryID", keypath: \Idea.categoryID, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "tags", keypath: \Idea.tags, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "contentType", keypath: \Idea.contentType, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "sourceURL", keypath: \Idea.sourceURL, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "sortOrder", keypath: \Idea.sortOrder, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "attachments", keypath: \Idea.attachments, defaultValue: nil, metadata: Schema.Relationship(deleteRule: .cascade)),
    ] }
    init(content: String, categoryID: UUID, title: String? = nil, attachments: [Attachment] = []) {
        // Initialization writes backing values before model-level accessors can
        // observe an old relationship value. Subsequent edits use self.setValue.
        _$backingData.setValue(forKey: \.id, to: UUID())
        _$backingData.setValue(forKey: \.content, to: content)
        _$backingData.setValue(forKey: \.categoryID, to: categoryID)
        _$backingData.setValue(forKey: \.title, to: title ?? ContentAnalysis.title(content, fallback: attachments.first?.name ?? "Untitled idea"))
        _$backingData.setValue(forKey: \.createdAt, to: Date.now)
        _$backingData.setValue(forKey: \.updatedAt, to: Date.now)
        _$backingData.setValue(forKey: \.isPinned, to: false)
        _$backingData.setValue(forKey: \.isFavorite, to: false)
        _$backingData.setValue(forKey: \.isArchived, to: false)
        _$backingData.setValue(forKey: \.tags, to: ContentAnalysis.tags(content))
        _$backingData.setValue(forKey: \.sourceURL, to: ContentAnalysis.url(content))
        _$backingData.setValue(forKey: \.contentType, to: ContentAnalysis.kind(content, attachments: attachments).rawValue)
        _$backingData.setValue(forKey: \.sortOrder, to: Date.now.timeIntervalSince1970)
        _$backingData.setValue(forKey: \.attachments, to: attachments)
    }
}

final class IdeaCategory: PersistentModel {
    var id: UUID {
        get { _$observationRegistrar.access(self, keyPath: \.id); return self.getValue(forKey: \.id) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.id) { self.setValue(forKey: \.id, to: newValue) } }
    }
    var name: String {
        get { _$observationRegistrar.access(self, keyPath: \.name); return self.getValue(forKey: \.name) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.name) { self.setValue(forKey: \.name, to: newValue) } }
    }
    var icon: String {
        get { _$observationRegistrar.access(self, keyPath: \.icon); return self.getValue(forKey: \.icon) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.icon) { self.setValue(forKey: \.icon, to: newValue) } }
    }
    var accent: String {
        get { _$observationRegistrar.access(self, keyPath: \.accent); return self.getValue(forKey: \.accent) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.accent) { self.setValue(forKey: \.accent, to: newValue) } }
    }
    var sortOrder: Int {
        get { _$observationRegistrar.access(self, keyPath: \.sortOrder); return self.getValue(forKey: \.sortOrder) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.sortOrder) { self.setValue(forKey: \.sortOrder, to: newValue) } }
    }
    var isInbox: Bool {
        get { _$observationRegistrar.access(self, keyPath: \.isInbox); return self.getValue(forKey: \.isInbox) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.isInbox) { self.setValue(forKey: \.isInbox, to: newValue) } }
    }
    // Explicit PersistentModel conformance keeps SwiftData available with Apple's
    // command-line tools, which do not ship the SwiftData @Model macro plugin.
    private var _$backingData: any BackingData<IdeaCategory> = IdeaCategory.createBackingData()
    var persistentBackingData: any BackingData<IdeaCategory> {
        get { _$backingData }
        set { _$backingData = newValue }
    }
    private let _$observationRegistrar = ObservationRegistrar()
    required init(backingData: any BackingData<IdeaCategory>) { persistentBackingData = backingData }
    static var schemaMetadata: [Schema.PropertyMetadata] { [
        Schema.PropertyMetadata(name: "id", keypath: \IdeaCategory.id, defaultValue: nil, metadata: Schema.Attribute(.unique)),
        Schema.PropertyMetadata(name: "name", keypath: \IdeaCategory.name, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "icon", keypath: \IdeaCategory.icon, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "accent", keypath: \IdeaCategory.accent, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "sortOrder", keypath: \IdeaCategory.sortOrder, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "isInbox", keypath: \IdeaCategory.isInbox, defaultValue: nil, metadata: nil),
    ] }
    init(name: String, icon: String = "folder", accent: String = "orange", sortOrder: Int = 0, isInbox: Bool = false) {
        _$backingData.setValue(forKey: \.id, to: UUID())
        _$backingData.setValue(forKey: \.name, to: name)
        _$backingData.setValue(forKey: \.icon, to: icon)
        _$backingData.setValue(forKey: \.accent, to: accent)
        _$backingData.setValue(forKey: \.sortOrder, to: sortOrder)
        _$backingData.setValue(forKey: \.isInbox, to: isInbox)
    }
}

final class Attachment: PersistentModel {
    var id: UUID {
        get { _$observationRegistrar.access(self, keyPath: \.id); return self.getValue(forKey: \.id) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.id) { self.setValue(forKey: \.id, to: newValue) } }
    }
    var name: String {
        get { _$observationRegistrar.access(self, keyPath: \.name); return self.getValue(forKey: \.name) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.name) { self.setValue(forKey: \.name, to: newValue) } }
    }
    var kind: String {
        get { _$observationRegistrar.access(self, keyPath: \.kind); return self.getValue(forKey: \.kind) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.kind) { self.setValue(forKey: \.kind, to: newValue) } }
    }
    var relativePath: String? {
        get { _$observationRegistrar.access(self, keyPath: \.relativePath); return self.getValue(forKey: \.relativePath) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.relativePath) { self.setValue(forKey: \.relativePath, to: newValue) } }
    }
    var bookmark: Data? {
        get { _$observationRegistrar.access(self, keyPath: \.bookmark); return self.getValue(forKey: \.bookmark) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.bookmark) { self.setValue(forKey: \.bookmark, to: newValue) } }
    }
    var originalPath: String? {
        get { _$observationRegistrar.access(self, keyPath: \.originalPath); return self.getValue(forKey: \.originalPath) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.originalPath) { self.setValue(forKey: \.originalPath, to: newValue) } }
    }
    var byteCount: Int64 {
        get { _$observationRegistrar.access(self, keyPath: \.byteCount); return self.getValue(forKey: \.byteCount) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.byteCount) { self.setValue(forKey: \.byteCount, to: newValue) } }
    }
    var typeDescription: String {
        get { _$observationRegistrar.access(self, keyPath: \.typeDescription); return self.getValue(forKey: \.typeDescription) }
        set { _$observationRegistrar.withMutation(of: self, keyPath: \.typeDescription) { self.setValue(forKey: \.typeDescription, to: newValue) } }
    }
    // Explicit PersistentModel conformance keeps SwiftData available with Apple's
    // command-line tools, which do not ship the SwiftData @Model macro plugin.
    private var _$backingData: any BackingData<Attachment> = Attachment.createBackingData()
    var persistentBackingData: any BackingData<Attachment> {
        get { _$backingData }
        set { _$backingData = newValue }
    }
    private let _$observationRegistrar = ObservationRegistrar()
    required init(backingData: any BackingData<Attachment>) { persistentBackingData = backingData }
    static var schemaMetadata: [Schema.PropertyMetadata] { [
        Schema.PropertyMetadata(name: "id", keypath: \Attachment.id, defaultValue: nil, metadata: Schema.Attribute(.unique)),
        Schema.PropertyMetadata(name: "name", keypath: \Attachment.name, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "kind", keypath: \Attachment.kind, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "relativePath", keypath: \Attachment.relativePath, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "bookmark", keypath: \Attachment.bookmark, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "originalPath", keypath: \Attachment.originalPath, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "byteCount", keypath: \Attachment.byteCount, defaultValue: nil, metadata: nil),
        Schema.PropertyMetadata(name: "typeDescription", keypath: \Attachment.typeDescription, defaultValue: nil, metadata: nil),
    ] }
    init(name: String, kind: String, relativePath: String? = nil, bookmark: Data? = nil, originalPath: String? = nil, byteCount: Int64 = 0, typeDescription: String = "") {
        _$backingData.setValue(forKey: \.id, to: UUID())
        _$backingData.setValue(forKey: \.name, to: name)
        _$backingData.setValue(forKey: \.kind, to: kind)
        _$backingData.setValue(forKey: \.relativePath, to: relativePath)
        _$backingData.setValue(forKey: \.bookmark, to: bookmark)
        _$backingData.setValue(forKey: \.originalPath, to: originalPath)
        _$backingData.setValue(forKey: \.byteCount, to: byteCount)
        _$backingData.setValue(forKey: \.typeDescription, to: typeDescription)
    }
}
