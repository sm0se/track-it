import Foundation

enum DraftKind: Equatable {
    case item(ItemKind)
    case note

    var label: String {
        switch self {
        case let .item(kind): kind.label
        case .note: "Note"
        }
    }

    var symbol: String {
        switch self {
        case let .item(kind): kind.symbol
        case .note: "note.text"
        }
    }
}

struct Draft: Equatable {
    var kind: DraftKind
    var title = ""
    var due: Date?
    var hasTime = false
    var priority: Priority = .none
    var tags: [String] = []
    var durationMinutes: Int?
    var recurrence: Recurrence = .none
    var repeatDays: [Int] = []
    var link = ""

    var isEmpty: Bool { title.trimmingCharacters(in: .whitespaces).isEmpty }

    var searchTerms: [String] {
        title.lowercased().split(separator: " ").map(String.init)
    }
}

/// Turns free text like "demo: Acme walkthrough fri 3pm !high #sales" into a Draft.
enum QuickParser {
    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static let prefixes: [(String, DraftKind)] = [
        ("task:", .item(.task)), ("todo:", .item(.task)), ("t:", .item(.task)),
        ("meeting:", .item(.meeting)), ("meet:", .item(.meeting)), ("m:", .item(.meeting)),
        ("demo:", .item(.demo)),
        ("deliverable:", .item(.deliverable)), ("del:", .item(.deliverable)), ("dl:", .item(.deliverable)),
        ("note:", .note), ("memo:", .note), ("n:", .note),
    ]

    private static let recurrencePatterns: [(String, Recurrence)] = [
        (#"\bevery\s*week\s*days?\b|\bweekdays\b"#, .weekdays),
        (#"\bevery\s*day\b|\bdaily\b(?=\s*$)"#, .daily),
        (#"\bevery\s*week\b"#, .weekly),
    ]

    private static let dayToken = #"(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?"#
    /// "every mon wed fri", "every mon/wed/fri", "every tue & thu", "every monday, wednesday and friday"
    private static let dayListPattern = #"\bevery\s+"# + dayToken + #"(?:\s*(?:,|/|&|\+|and)?\s*"# + dayToken + #")*"#
    private static let dayNumbers: [String: Int] = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]

    private static let timeHint = #"\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\b\d{1,2}:\d{2}\b|noon|midnight|morning|afternoon|evening|tonight"#

    static func parse(_ raw: String, defaultKind: DraftKind) -> Draft {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var kind = defaultKind

        let lower = text.lowercased()
        for (prefix, k) in prefixes {
            let slash = "/" + prefix.dropLast() + " "
            if lower.hasPrefix(prefix) {
                kind = k
                text = String(text.dropFirst(prefix.count))
                break
            }
            if lower.hasPrefix(slash) {
                kind = k
                text = String(text.dropFirst(slash.count))
                break
            }
        }
        text = text.trimmingCharacters(in: .whitespaces)

        var draft = Draft(kind: kind)
        guard kind != .note else {
            draft.title = text
            return draft
        }

        let timed = kind == .item(.meeting) || kind == .item(.demo)

        if timed, let r = text.range(of: dayListPattern, options: [.regularExpression, .caseInsensitive]) {
            let phrase = text[r].lowercased().dropFirst("every".count)
            let days = phrase
                .split { !$0.isLetter }
                .compactMap { dayNumbers[String($0.prefix(3))] }
            if !days.isEmpty {
                draft.recurrence = .custom
                draft.repeatDays = Array(Set(days)).sorted()
                text.removeSubrange(r)
            }
        }

        if timed, draft.recurrence == .none {
            for (pattern, rule) in recurrencePatterns {
                if let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    draft.recurrence = rule
                    text.removeSubrange(r)
                    break
                }
            }
        }

        var kept: [String] = []
        for word in text.split(separator: " ").map(String.init) {
            let l = word.lowercased()
            switch l {
            case "!!!", "!high", "!h", "!1", "!p1", "!urgent":
                draft.priority = .high; continue
            case "!!", "!med", "!medium", "!m", "!2", "!p2":
                draft.priority = .medium; continue
            case "!", "!low", "!l", "!3", "!p3":
                draft.priority = .low; continue
            default: break
            }
            if word.hasPrefix("#"), word.count > 1 {
                draft.tags.append(String(word.dropFirst()))
                continue
            }
            if l.hasPrefix("http://") || l.hasPrefix("https://") || URL.meetingHosts.contains(where: { l.contains($0) }) {
                draft.link = word
                continue
            }
            if timed, let minutes = duration(from: l) {
                draft.durationMinutes = minutes
                continue
            }
            kept.append(word)
        }
        text = kept.joined(separator: " ")

        if let detector = dateDetector,
           let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let date = match.date,
           let range = Range(match.range, in: text) {
            let matched = text[range].lowercased()
            draft.hasTime = matched.range(of: timeHint, options: .regularExpression) != nil
            draft.due = draft.hasTime ? date : date.startOfDay

            var before = text[..<range.lowerBound].split(separator: " ").map(String.init)
            if let last = before.last?.lowercased(), ["by", "on", "at", "due", "for", "from", "before"].contains(last) {
                before.removeLast()
            }
            text = (before.joined(separator: " ") + " " + text[range.upperBound...])
        }

        // A repeating item with no date starts today so it shows up right away.
        if draft.recurrence != .none, draft.due == nil {
            draft.due = Date().startOfDay
        }

        draft.title = text.split(separator: " ").joined(separator: " ")
        return draft
    }

    /// "30m", "45min", "1h", "1.5h", "2hrs" → minutes.
    private static func duration(from token: String) -> Int? {
        guard let regex = try? Regex(#"(\d+(?:\.\d+)?)(m|min|mins|h|hr|hrs)"#),
              let match = token.wholeMatch(of: regex),
              let number = match.output[1].substring, let unit = match.output[2].substring,
              let value = Double(number) else { return nil }
        let minutes = unit.hasPrefix("h") ? value * 60 : value
        return minutes > 0 && minutes <= 24 * 60 ? Int(minutes.rounded()) : nil
    }
}
