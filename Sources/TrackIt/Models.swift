import Foundation

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case task, meeting, demo, deliverable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .task: "Task"
        case .meeting: "Meeting"
        case .demo: "Demo"
        case .deliverable: "Deliverable"
        }
    }

    var symbol: String {
        switch self {
        case .task: "checkmark.circle.fill"
        case .meeting: "video.fill"
        case .demo: "play.rectangle.fill"
        case .deliverable: "shippingbox.fill"
        }
    }

    var personLabel: String {
        switch self {
        case .task: "With"
        case .meeting: "Attendees"
        case .demo: "Client / audience"
        case .deliverable: "Stakeholder"
        }
    }
}

enum Status: String, Codable, CaseIterable, Identifiable {
    case todo, inProgress, review, blocked, done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .review: "In Review"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .review: "eye.circle"
        case .blocked: "exclamationmark.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    var next: Status {
        switch self {
        case .todo: .inProgress
        case .inProgress: .review
        case .review: .done
        case .blocked: .inProgress
        case .done: .todo
        }
    }
}

enum Priority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case none = 0, low, medium, high

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var bangs: String {
        switch self {
        case .none: ""
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }

    var next: Priority { Priority(rawValue: (rawValue + 1) % 4) ?? .none }

    static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
}

enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Doesn't repeat"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .custom: "Specific days"
        }
    }

    /// Label including the chosen days for `.custom`, e.g. "Mon, Wed, Fri".
    func label(days: [Int]) -> String {
        guard self == .custom, !days.isEmpty else { return label }
        let set = Set(days)
        if set == [2, 3, 4, 5, 6] { return "Every weekday" }
        if set.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return Weekday.mondayFirst.filter(set.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}

/// Calendar weekday numbers (1 = Sunday … 7 = Saturday) in display order.
enum Weekday {
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    static func initial(_ weekday: Int) -> String {
        String(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
    }
}

struct Item: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: ItemKind
    var title: String
    var notes = ""
    var status: Status = .todo {
        didSet {
            guard status != oldValue else { return }
            completedAt = status == .done ? Date() : nil
        }
    }
    var priority: Priority = .none
    var due: Date?
    var hasTime = false
    var durationMinutes = 30
    var recurrence: Recurrence = .none
    /// Weekdays (1 = Sunday … 7 = Saturday) used when `recurrence == .custom`.
    var repeatDays: [Int] = []
    var tags: [String] = []
    var person = ""
    var link = ""
    var createdAt = Date()
    var completedAt: Date?

    init(kind: ItemKind, title: String) {
        self.kind = kind
        self.title = title
    }

    var recurrenceLabel: String { recurrence.label(days: repeatDays) }

    var isDone: Bool { kind != .meeting && status == .done }

    /// Minutes an occurrence lasts; date-only items occupy the whole day.
    var effectiveDuration: Int { hasTime ? max(durationMinutes, 1) : 24 * 60 }

    var joinURL: URL? {
        if !link.trimmingCharacters(in: .whitespaces).isEmpty { return URL.lenient(link) }
        return URL.firstMeetingLink(in: notes)
    }

    /// Start times of this item that overlap [from, to). Non-recurring items yield at most one.
    func occurrenceStarts(from: Date, to: Date) -> [Date] {
        guard let due else { return [] }
        let cal = Calendar.current
        let duration = TimeInterval(effectiveDuration * 60)
        let base = hasTime ? due : cal.startOfDay(for: due)

        guard recurrence != .none else {
            return (base < to && base.addingTimeInterval(duration) > from) ? [base] : []
        }

        let hm = cal.dateComponents([.hour, .minute], from: base)
        let baseWeekday = cal.component(.weekday, from: base)
        var day = max(cal.startOfDay(for: base), cal.startOfDay(for: from.addingTimeInterval(-duration)))
        var out: [Date] = []
        while day < to, out.count < 400 {
            let weekday = cal.component(.weekday, from: day)
            let matches = switch recurrence {
            case .daily: true
            case .weekdays: (2...6).contains(weekday)
            case .weekly: weekday == baseWeekday
            case .custom: repeatDays.isEmpty ? weekday == baseWeekday : repeatDays.contains(weekday)
            case .none: false
            }
            if matches,
               let start = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day),
               start >= base, start < to, start.addingTimeInterval(duration) > from {
                out.append(start)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    func nextStart(after now: Date) -> Date? {
        occurrenceStarts(from: now, to: now.adding(days: 90)).first ?? due
    }

    // Tolerant decoding so older/newer data files never fail to load.
    enum CodingKeys: String, CodingKey {
        case id, kind, title, notes, status, priority, due, hasTime, durationMinutes, recurrence,
             repeatDays,
             tags, person, link, createdAt, completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = (try? c.decodeIfPresent(ItemKind.self, forKey: .kind)) ?? .task
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .todo
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? .none
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        hasTime = try c.decodeIfPresent(Bool.self, forKey: .hasTime) ?? false
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 30
        recurrence = (try? c.decodeIfPresent(Recurrence.self, forKey: .recurrence)) ?? .none
        repeatDays = try c.decodeIfPresent([Int].self, forKey: .repeatDays) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        person = try c.decodeIfPresent(String.self, forKey: .person) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// One concrete instance of a (possibly recurring) timed item.
struct Occurrence: Identifiable, Equatable {
    let item: Item
    let start: Date

    var end: Date { start.addingTimeInterval(TimeInterval(item.effectiveDuration * 60)) }
    var id: String { "\(item.id.uuidString)@\(Int(start.timeIntervalSince1970))" }

    func isLive(at now: Date) -> Bool { start <= now && end > now }
}

struct Note: Identifiable, Equatable, Codable {
    var id = UUID()
    var body = ""
    var pinned = false
    var createdAt = Date()
    var updatedAt = Date()

    init(body: String) {
        self.body = body
    }

    private var lines: [Substring] {
        body.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var title: String {
        guard let first = lines.first else { return "Untitled" }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        let stripped = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Untitled" : stripped
    }

    var preview: String {
        lines.dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    var wordCount: Int { body.split { $0.isWhitespace || $0.isNewline }.count }

    enum CodingKeys: String, CodingKey { case id, body, pinned, createdAt, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

extension URL {
    static func lenient(_ string: String) -> URL? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return s.contains("://") ? URL(string: s) : URL(string: "https://" + s)
    }

    static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                               "webex.com", "whereby.com", "around.co", "chime.aws", "slack.com/huddle"]

    static func firstMeetingLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let urls = matches.compactMap(\.url)
        return urls.first { url in meetingHosts.contains { url.absoluteString.contains($0) } }
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
    func adding(minutes: Int) -> Date { addingTimeInterval(TimeInterval(minutes * 60)) }
}
