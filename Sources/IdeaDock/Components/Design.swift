import SwiftUI

extension Color {
    static let dockCanvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.067, green: 0.071, blue: 0.078, alpha: 1)
            : NSColor(calibratedWhite: 0.985, alpha: 1)
    })
    static let dockListSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.095, green: 0.099, blue: 0.110, alpha: 1)
            : NSColor(calibratedWhite: 0.965, alpha: 1)
    })
    static let dockAccent = Color(red: 0.988, green: 0.431, blue: 0)
    static func categoryAccent(_ name: String) -> Color {
        switch name { case "blue": return .blue; case "green": return .green; case "purple": return .purple; case "rose": return .pink; case "gray": return .secondary; default: return .dockAccent }
    }
}
struct QuietIconButton: View {
    let icon: String
    let label: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(active ? Color.dockAccent : .secondary).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
struct EmptyLibraryView: View {
    let searching: Bool
    let title: String
    var hasNotes = false
    let action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: searching ? "magnifyingglass" : "tray").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(searching ? "No matching notes." : title).font(.system(size: 16, weight: .medium))
            Text(searching ? "Try a different word or time range." : hasNotes ? "Use ↑ ↓ and Return to open it." : "Press ⌥ Space anywhere to capture it.").font(.system(size: 12)).foregroundStyle(.secondary)
            if !searching && !hasNotes { Button("Capture an idea", action: action).buttonStyle(.bordered).padding(.top, 5) }
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// SDK 27 introduces an optional State macro. This alias explicitly selects the
// native property wrapper, so command-line builds do not require SwiftUIMacros.
typealias ViewState<Value> = SwiftUI.State<Value>

/// Standardized corner radius tokens across IdeaDock panels and cards.
enum DockRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
}
