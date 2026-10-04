import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor struct AttachmentPreview: View {
    let attachment: Attachment
    let store: IdeaStore
    let service: AttachmentService
    let onRemove: () -> Void
    let onError: (String) -> Void

    @ViewState private var thumbnail: NSImage?
    @ViewState private var fileIcon: NSImage?
    @ViewState private var loading = true
    @ViewState private var previewError: String?
    @ViewState private var actionError: String?

    private var isImage: Bool { attachment.kind == "image" }
    private var sizeLabel: String? {
        attachment.byteCount > 0 ? ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file) : nil
    }
    private var fileDetails: String {
        let type = attachment.typeDescription.isEmpty ? "File" : attachment.typeDescription
        return ([type] + [sizeLabel].compactMap { $0 }).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if isImage {
                Button(action: open) {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    } else {
                        VStack(spacing: 9) {
                            if loading { ProgressView().controlSize(.small) }
                            else { Image(systemName: "photo").font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary) }
                            Text(loading ? "Loading preview…" : "Preview unavailable").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .buttonStyle(.plain)
                .help(previewError ?? "Open \(attachment.name)")
                .accessibilityLabel("Open image \(attachment.name)")

                HStack(spacing: 8) {
                    Text(attachment.name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(attachment.name)
                    if let sizeLabel { Text(sizeLabel).font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize() }
                    Spacer(minLength: 4)
                    actionsMenu
                }
            } else {
                HStack(spacing: 8) {
                    Button(action: open) {
                        HStack(spacing: 10) {
                            if let fileIcon {
                                Image(nsImage: fileIcon).resizable().scaledToFit().frame(width: 30, height: 30)
                            } else {
                                Image(systemName: attachment.typeDescription == "Folder" ? "folder" : "doc")
                                    .font(.system(size: 23, weight: .light)).foregroundStyle(.secondary).frame(width: 30, height: 30)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(attachment.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(fileDetails).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(attachment.originalPath ?? attachment.name)
                    .accessibilityLabel("Open file \(attachment.name)")
                    actionsMenu
                }
                .padding(11)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            }
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).help(actionError)
            } else if let previewError, !isImage {
                Label("File unavailable", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary).help(previewError)
            }
        }
        .contextMenu { contextActions }
        .task(id: attachment.id) { loadPreview() }
    }

    private var actionsMenu: some View {
        Menu { contextActions } label: {
            Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Attachment actions")
        .accessibilityLabel("Actions for \(attachment.name)")
    }

    @ViewBuilder private var contextActions: some View {
        Button(isImage ? "Open Image" : "Open File", action: open)
        Button("Reveal in Finder", action: reveal)
        Divider()
        Button("Remove Attachment", role: .destructive, action: onRemove)
    }

    private func open() {
        perform { try service.open(attachment) }
    }

    private func reveal() {
        perform { try service.reveal(attachment) }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            actionError = nil
        } catch {
            let message = error.localizedDescription
            actionError = message
            onError(message)
        }
    }

    private func loadPreview() {
        loading = true
        thumbnail = nil
        fileIcon = nil
        previewError = nil
        defer { loading = false }
        do {
            let url = try service.url(for: attachment)
            if isImage {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= AttachmentService.maximumImageBytes else { throw AttachmentError.imageTooLarge }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw ThumbnailError.unavailable }
                let pixelsWide = width.intValue, pixelsHigh = height.intValue
                guard pixelsWide > 0, pixelsHigh > 0 else { throw ThumbnailError.unavailable }
                guard pixelsWide <= AttachmentService.maximumImageDimension, pixelsHigh <= AttachmentService.maximumImageDimension,
                      pixelsWide <= AttachmentService.maximumImagePixels / pixelsHigh else { throw AttachmentError.imageTooLarge }
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 900,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { throw ThumbnailError.unavailable }
                thumbnail = NSImage(cgImage: image, size: .zero)
            } else {
                fileIcon = NSWorkspace.shared.icon(forFile: url.path)
            }
        } catch {
            previewError = error.localizedDescription
            if !isImage {
                let type: UTType = attachment.typeDescription == "Folder" ? .folder :
                    (UTType(filenameExtension: (attachment.name as NSString).pathExtension) ?? .data)
                fileIcon = NSWorkspace.shared.icon(for: type)
            }
        }
    }
}

private enum ThumbnailError: LocalizedError {
    case unavailable
    var errorDescription: String? { "A thumbnail could not be generated for this image. Open the attachment to view it in its default app." }
}
