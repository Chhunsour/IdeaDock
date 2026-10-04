import Foundation

enum ContentAnalysis {
    static func title(_ text: String, fallback: String = "Untitled idea") -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
        let cleaned = line.replacingOccurrences(of: "^[-#`*\\s]+", with: "", options: .regularExpression)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(90))
    }
    static func tags(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\w/])#([\\p{L}\\p{N}_-]+)") else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return Array(Set(matches.map { ns.substring(with: $0.range(at: 1)).lowercased() })).sorted()
    }
    static func url(_ text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }?.absoluteString
    }
    static func kind(_ text: String, attachments: [Attachment] = []) -> ContentKind {
        if attachments.contains(where: { $0.kind == "image" }) { return .image }
        if !attachments.isEmpty { return .file }
        if text.contains("```") || text.range(of: "(?m)^\\s*(func |function |const |let |var |import |class |struct |def |SELECT |if .*\\{|<[/a-zA-Z].*>)", options: .regularExpression) != nil { return .code }
        if url(text) != nil { return .link }
        return .text
    }
}

enum LibraryScope: Hashable {
    case inbox, pinned, favorites, recent, today, images, links, archive, category(UUID)
    var label: String { switch self { case .inbox: "Inbox"; case .pinned: "Pinned"; case .favorites: "Favorites"; case .recent: "All Notes"; case .today: "Today"; case .images: "Images"; case .links: "Links"; case .archive: "Archive"; case .category: "Category" } }
    var icon: String { switch self { case .inbox: "tray"; case .pinned: "pin"; case .favorites: "star"; case .recent: "clock"; case .today: "calendar"; case .images: "photo"; case .links: "link"; case .archive: "archivebox"; case .category: "folder" } }
}

enum IdeaSearch {
    static func matches(_ idea: Idea, query: String, category: String) -> Bool {
        let haystack = ([idea.title, idea.content, category, idea.sourceURL ?? ""] + idea.tags + idea.attachments.map(\.name)).joined(separator: " ").lowercased()
        return query.lowercased().split(separator: " ").allSatisfy { token in
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                switch parts[0] {
                case "category": return category.lowercased().contains(parts[1])
                case "tag": return idea.tags.contains { $0.contains(parts[1].replacingOccurrences(of: "#", with: "")) }
                case "type": return idea.contentType == parts[1] || idea.kind.label.lowercased() == parts[1]
                default: break
                }
            }
            return haystack.contains(token)
        }
    }
}

extension ContentAnalysis {
    /// Extracts the root host domain from an optional URL string for clean display.
    static func hostDomain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return url.host
    }
}
