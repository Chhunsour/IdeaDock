# Drag-and-Drop & Pasteboard Pipeline

IdeaDock features a resilient drag-and-drop system handled via `DropReader` and `NSItemProvider`.

## Ingestion Order

When items are dropped or pasted from the clipboard, `DropReader` evaluates representations in strict priority:

1. **Images (`public.image`)**: Decoded via ImageIO, validated against dimension/byte caps, and stored locally in `Attachments/`.
2. **File URLs (`public.file-url`)**: Security-scoped bookmarks are acquired without copying multi-gigabyte external binaries.
3. **Web URLs (`public.url`)**: Parsed, validated, and tagged as link notes.
4. **Plain Text (`public.utf8-plain-text`)**: Ingested directly with markdown and hashtag extraction.

## Safety Guarantees

- No background clipboard listening or polling. Clipboard capture only occurs on explicit user hotkey (⇧⌘V).
- Decompression bomb prevention: ImageIO reads headers before loading full pixel buffers.
- Maximum attachment byte size enforcement (50 MB cap per image).
