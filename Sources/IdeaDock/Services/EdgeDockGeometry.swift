import AppKit
import Foundation

enum DockEdge: String, Codable, CaseIterable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    var isVertical: Bool { self == .left || self == .right }

    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

struct DockPlacement: Equatable {
    var edge: DockEdge
    /// Position along the handle's available travel: bottom to top for vertical
    /// edges, left to right for horizontal edges. Corners ignore this value.
    var fraction: CGFloat
}

/// AppKit screen coordinates have their origin at the bottom left. These pure
/// calculations accept a screen's visibleFrame, without assuming its origin is zero.
enum EdgeDockGeometry {
    static func candidate(for windowFrame: NSRect, in screenFrame: NSRect, threshold: CGFloat = 22) -> DockPlacement? {
        guard isUsable(windowFrame), isUsable(screenFrame) else { return nil }
        let proximity = threshold.isFinite ? max(0, threshold) : 0
        // A dragged window may already extend beyond an edge. Treat that edge as
        // reached, rather than losing the candidate once the pointer overshoots.
        let left = max(0, windowFrame.minX - screenFrame.minX)
        let right = max(0, screenFrame.maxX - windowFrame.maxX)
        let bottom = max(0, windowFrame.minY - screenFrame.minY)
        let top = max(0, screenFrame.maxY - windowFrame.maxY)
        let horizontal: DockEdge? = min(left, right) <= proximity ? (left <= right ? .left : .right) : nil
        let vertical: DockEdge? = min(bottom, top) <= proximity ? (bottom <= top ? .bottom : .top) : nil

        if let horizontal, let vertical {
            switch (horizontal, vertical) {
            case (.left, .top): return DockPlacement(edge: .topLeft, fraction: 0.5)
            case (.right, .top): return DockPlacement(edge: .topRight, fraction: 0.5)
            case (.left, .bottom): return DockPlacement(edge: .bottomLeft, fraction: 0.5)
            default: return DockPlacement(edge: .bottomRight, fraction: 0.5)
            }
        }
        if let horizontal {
            return DockPlacement(edge: horizontal, fraction: fraction(center: windowFrame.midY, origin: screenFrame.minY, length: screenFrame.height, handleLength: min(84, screenFrame.height)))
        }
        if let vertical {
            return DockPlacement(edge: vertical, fraction: fraction(center: windowFrame.midX, origin: screenFrame.minX, length: screenFrame.width, handleLength: min(84, screenFrame.width)))
        }
        return nil
    }

    static func handleFrame(for placement: DockPlacement, in screenFrame: NSRect) -> NSRect {
        guard isUsable(screenFrame) else { return .zero }
        let progress = placement.fraction.isFinite ? clamp(placement.fraction, lower: 0, upper: 1) : 0.5
        let size: NSSize
        if placement.edge.isCorner {
            size = NSSize(width: min(30, screenFrame.width), height: min(30, screenFrame.height))
        } else if placement.edge.isVertical {
            size = NSSize(width: min(22, screenFrame.width), height: min(84, screenFrame.height))
        } else {
            size = NSSize(width: min(84, screenFrame.width), height: min(22, screenFrame.height))
        }
        var origin = NSPoint(x: screenFrame.minX, y: screenFrame.minY)
        switch placement.edge {
        case .left, .right:
            origin.x = placement.edge == .left ? screenFrame.minX : screenFrame.maxX - size.width
            origin.y += progress * (screenFrame.height - size.height)
        case .top, .bottom:
            origin.x += progress * (screenFrame.width - size.width)
            origin.y = placement.edge == .bottom ? screenFrame.minY : screenFrame.maxY - size.height
        case .topLeft:
            origin.y = screenFrame.maxY - size.height
        case .topRight:
            origin = NSPoint(x: screenFrame.maxX - size.width, y: screenFrame.maxY - size.height)
        case .bottomRight:
            origin.x = screenFrame.maxX - size.width
        case .bottomLeft: break
        }
        return NSRect(origin: origin, size: size)
    }

    static func restoredFrame(_ frame: NSRect, in screenFrame: NSRect, margin: CGFloat = 12) -> NSRect {
        guard isUsable(screenFrame) else { return .zero }
        let requestedMargin = margin.isFinite ? max(0, margin) : 0
        // On a screen too small for the requested pair of margins, use its full
        // extent instead of creating a zero or negative available size.
        let horizontalMargin = requestedMargin * 2 < screenFrame.width ? requestedMargin : 0
        let verticalMargin = requestedMargin * 2 < screenFrame.height ? requestedMargin : 0
        let available = screenFrame.insetBy(dx: horizontalMargin, dy: verticalMargin)
        let width = frame.width.isFinite ? clamp(frame.width, lower: min(1, available.width), upper: available.width) : available.width
        let height = frame.height.isFinite ? clamp(frame.height, lower: min(1, available.height), upper: available.height) : available.height
        let x = frame.origin.x.isFinite ? frame.origin.x : available.midX - width / 2
        let y = frame.origin.y.isFinite ? frame.origin.y : available.midY - height / 2
        return NSRect(x: clamp(x, lower: available.minX, upper: available.maxX - width), y: clamp(y, lower: available.minY, upper: available.maxY - height), width: width, height: height)
    }

    static func translatedFrame(_ frame: NSRect, toward edge: DockEdge, distance: CGFloat) -> NSRect {
        guard distance.isFinite else { return frame }
        var translated = frame
        switch edge {
        case .left, .topLeft, .bottomLeft: translated.origin.x -= distance
        case .right, .topRight, .bottomRight: translated.origin.x += distance
        default: break
        }
        switch edge {
        case .top, .topLeft, .topRight: translated.origin.y += distance
        case .bottom, .bottomLeft, .bottomRight: translated.origin.y -= distance
        default: break
        }
        return translated
    }

    private static func fraction(center: CGFloat, origin: CGFloat, length: CGFloat, handleLength: CGFloat) -> CGFloat {
        let travel = length - handleLength
        guard travel > 0 else { return 0.5 }
        return clamp((center - origin - handleLength / 2) / travel, lower: 0, upper: 1)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat { min(max(value, lower), upper) }

    private static func isUsable(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0 && frame.maxX.isFinite && frame.maxY.isFinite
    }
}
