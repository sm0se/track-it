import Foundation

enum Fmt {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let weekdayFormatter = formatter("EEE")
    private static let monthDayFormatter = formatter("MMMd")
    private static let fullDayFormatter = formatter("EEEEMMMMd")
    private static let headerDayFormatter = formatter("EEEEMMMd")
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    static func timeRange(_ start: Date, _ end: Date) -> String { "\(time(start)) – \(time(end))" }

    static func fullDate(_ date: Date) -> String { fullDayFormatter.string(from: date) }

    static func day(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: now.startOfDay, to: date.startOfDay).day ?? 0
        return (2..<7).contains(days) ? weekdayFormatter.string(from: date) : monthDayFormatter.string(from: date)
    }

    static func due(_ date: Date, hasTime: Bool, now: Date = Date()) -> String {
        let d = day(date, now: now)
        return hasTime ? "\(d) \(time(date))" : d
    }

    static func dayHeader(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return headerDayFormatter.string(from: date)
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 30 else { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        if h < 24 { return m == 0 ? "in \(h)h" : "in \(h)h \(m)m" }
        return "in \(h / 24)d"
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if abs(date.timeIntervalSince(now)) < 60 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
