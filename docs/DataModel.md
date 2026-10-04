# SwiftData Schema & Persistence

IdeaDock stores all notes, categories, and attachment metadata using Apple's SwiftData framework.

## Entity Schema

### `Idea`
- `id: UUID`: Unique note identifier.
- `title: String`: Auto-extracted or user-edited title.
- `content: String`: Note markdown body text.
- `createdAt: Date`: Immutable original capture time.
- `updatedAt: Date`: Last modification time.
- `isPinned: Bool`: Pinned note state.
- `isFavorite: Bool`: Starred favorite status.
- `isArchived: Bool`: Soft-deleted / archived status.
- `categoryID: UUID`: Foreign key to `IdeaCategory`.
- `tags: [String]`: Array of hashtag tokens.
- `sourceURL: String?`: Optional detected or associated URL.
- `contentType: String`: Detected type (`text`, `code`, `link`, `image`, `file`).
- `attachments: [Attachment]`: Associated file or image records.

### `IdeaCategory`
- `id: UUID`: Category identifier.
- `name: String`: Display title (e.g. Inbox, Research, Work).
- `icon: String`: SF Symbol name.
- `accent: String`: Semantic tint identifier.
- `sortOrder: Int`: Ordering index in sidebar.
- `isInbox: Bool`: Default capture destination flag.

### `Attachment`
- `id: UUID`: Attachment identifier.
- `name: String`: Original file name.
- `kind: String`: Attachment type (`image`, `file`).
- `byteSize: Int64`: File size.
- `localPath: String?`: Relative disk path inside library folder.
- `bookmarkData: Data?`: Security-scoped bookmark for external items.
