import SwiftUI

/// The time the idea entered the library. This does not infer a paste time.
struct CaptureTimestamp: View {
    let date: Date
    var updatedAt: Date? = nil
    var compact = false
    var now: Date = .now
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        Text(compact ? compactDate : "Captured \(visibleDate)")
            .monospacedDigit()
            .help(details)
            .accessibilityLabel(details)
    }

    private var visibleDate: String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard,
                                       locale: locale, calendar: localCalendar, timeZone: timeZone))
    }

    private var compactDate: String {
        let dayStart = localCalendar.startOfDay(for: date)
        let todayStart = localCalendar.startOfDay(for: now)
        let day: String
        if dayStart == todayStart { day = "Today" }
        else if let yesterday = localCalendar.date(byAdding: .day, value: -1, to: todayStart),
                dayStart == localCalendar.startOfDay(for: yesterday) { day = "Yesterday" }
        else {
            var style = Date.FormatStyle(locale: locale, calendar: localCalendar, timeZone: timeZone)
                .month(.abbreviated).day()
            if !localCalendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
            day = date.formatted(style)
        }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                                 locale: locale, calendar: localCalendar, timeZone: timeZone))
        return "\(day) · \(time)"
    }

    private var details: String {
        var result = "Captured \(fullDate(date))"
        // Initialization sets these dates separately, so ignore subsecond noise.
        if let updatedAt, abs(updatedAt.timeIntervalSince(date)) >= 1 {
            result += "\nLast changed \(fullDate(updatedAt))"
        }
        return result
    }

    private func fullDate(_ value: Date) -> String {
        let formatted = value.formatted(Date.FormatStyle(date: .complete, time: .complete,
                                                        locale: locale, calendar: localCalendar, timeZone: timeZone))
        return "\(formatted) (\(timeZone.identifier))"
    }

    private var localCalendar: Calendar {
        var value = calendar
        value.timeZone = timeZone
        return value
    }
}
