import Foundation

enum CaptureDateFilter: Hashable, CaseIterable, Identifiable {
    case anyTime, today, yesterday, last7Days, last30Days

    var id: Self { self }

    var label: String {
        switch self {
        case .anyTime: return "Any time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        }
    }

    func matches(_ createdAt: Date, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        if self == .anyTime { return true }
        guard let today = calendar.dateInterval(of: .day, for: now) else { return false }
        switch self {
        case .anyTime: return true
        case .today:
            return createdAt >= today.start && createdAt < today.end
        case .yesterday:
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: today.start),
                  let yesterday = calendar.dateInterval(of: .day, for: previousDay) else { return false }
            return createdAt >= yesterday.start && createdAt < yesterday.end
        case .last7Days, .last30Days:
            let precedingDays = self == .last7Days ? 6 : 29
            guard let start = calendar.date(byAdding: .day, value: -precedingDays, to: today.start) else { return false }
            return createdAt >= start && createdAt <= now
        }
    }
}

struct CaptureDaySection: Identifiable {
    let id: Date
    let title: String
    let ideas: [Idea]
}

@MainActor enum CaptureHistory {
    static func sections(_ ideas: [Idea], now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> [CaptureDaySection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today).map { calendar.startOfDay(for: $0) }
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        let days = Dictionary(grouping: ideas) { calendar.startOfDay(for: $0.createdAt) }
        return days.keys.sorted(by: >).map { day in
            let title: String
            if day == today { title = "Today" }
            else if let yesterday, day == yesterday { title = "Yesterday" }
            else { title = formatter.string(from: day) }
            return CaptureDaySection(id: day, title: title, ideas: days[day, default: []].sorted { newestFirst($0, $1) })
        }
    }

    static func newestFirst(_ lhs: Idea, _ rhs: Idea) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
