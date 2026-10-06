import AppKit
import Observation
import SwiftUI

enum Tab: Int, CaseIterable, Identifiable {
    case today, tasks, meetings, demos, deliverables, notes

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .tasks: "Tasks"
        case .meetings: "Meetings"
        case .demos: "Demos"
        case .deliverables: "Deliverables"
        case .notes: "Notes"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .tasks: "checkmark.circle.fill"
        case .meetings: "video.fill"
        case .demos: "play.rectangle.fill"
        case .deliverables: "shippingbox.fill"
        case .notes: "note.text"
        }
    }

    var tint: Color {
        switch self {
        case .today: Theme.pink
        case .tasks: Theme.blue
        case .meetings: Theme.teal
        case .demos: Theme.purple
        case .deliverables: Theme.orange
        case .notes: Theme.yellow
        }
    }

    var draftKind: DraftKind {
        switch self {
        case .today, .tasks: .item(.task)
        case .meetings: .item(.meeting)
        case .demos: .item(.demo)
        case .deliverables: .item(.deliverable)
        case .notes: .note
        }
    }

    var placeholder: String {
        switch self {
        case .today: "Search or add…  “Prep Acme demo fri 3pm !high #sales”"
        case .tasks: "Add a task…  “Ship invoice fix tomorrow !high”"
        case .meetings: "Add a meeting…  “Standup 10am 15m every weekday meet.google.com/x”"
        case .demos: "Add a demo…  “Acme walkthrough thu 4pm #sales”"
        case .deliverables: "Add a deliverable…  “Q4 board deck by friday”"
        case .notes: "Search notes, or type a title and press ↵"
        }
    }
}

enum RowID: Hashable {
    case create
    case item(UUID)
    case occurrence(UUID, Date)
    case note(UUID)

    var itemID: UUID? {
        switch self {
        case let .item(id), let .occurrence(id, _): id
        default: nil
        }
    }
}

struct RowSection: Identifiable {
    let id: String
    let title: String
    var tint: Color? = nil
    let rows: [RowID]
}

struct Toast: Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    var undo = false
}

struct FocusRequest: Equatable {
    let target: RowID
    let token: Int
}

struct KeyHint: Identifiable {
    let label: String
    let key: String
    var id: String { label + key }
}

@Observable
final class AppState {
    let store: Store
    let settings: Settings

    var tab: Tab = .today {
        didSet {
            guard tab != oldValue else { return }
            rawSelection = nil
            showSettings = false
        }
    }

    var query = "" {
        didSet { if query != oldValue { rawSelection = nil } }
    }

    var rawSelection: RowID?
    var showSettings = false
    var now = Date()
    var toast: Toast?
    var focusRequest: FocusRequest?

    @ObservationIgnored weak var commandField: NSTextField?
    @ObservationIgnored var hidePanel: () -> Void = {}
    @ObservationIgnored var previewAlert: () -> Void = {}
    @ObservationIgnored private var focusCounter = 0
    @ObservationIgnored private var toastWork: DispatchWorkItem?

    init(store: Store, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    // MARK: Derived data

    var draft: Draft? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return QuickParser.parse(q, defaultKind: tab.draftKind)
    }

    func occurrences(from: Date, to: Date, kinds: Set<ItemKind> = [.meeting]) -> [Occurrence] {
        store.items
            .filter { kinds.contains($0.kind) && $0.due != nil && ($0.kind == .meeting || ($0.hasTime && !$0.isDone)) }
            .flatMap { item in item.occurrenceStarts(from: from, to: to).map { Occurrence(item: item, start: $0) } }
            .sorted { $0.start < $1.start }
    }

    /// The next timed meeting or demo that hasn't ended yet, within 24 hours.
    func nextUp() -> Occurrence? {
        occurrences(from: now, to: now.addingTimeInterval(86_400), kinds: [.meeting, .demo])
            .first { $0.item.hasTime }
    }

    var sections: [RowSection] {
        var out: [RowSection] = []
        let d = draft
        if let d, !d.isEmpty { out.append(RowSection(id: "create", title: "", rows: [.create])) }

        let terms = d?.searchTerms ?? []
        let tags = d?.tags.map { $0.lowercased() } ?? []
        let searching = !(terms.isEmpty && tags.isEmpty)
        let items = searching ? store.items.filter { matches($0, terms: terms, tags: tags) } : store.items

        switch tab {
        case .today: out += searching ? searchSections(items, terms: terms) : todaySections()
        case .tasks: out += taskSections(items.filter { $0.kind == .task }, searching: searching)
        case .meetings: out += meetingSections(items.filter { $0.kind == .meeting }, searching: searching)
        case .demos: out += demoSections(items.filter { $0.kind == .demo }, searching: searching)
        case .deliverables: out += deliverableSections(items.filter { $0.kind == .deliverable }, searching: searching)
        case .notes: out += noteSections(terms: terms)
        }
        return out.filter { !$0.rows.isEmpty }
    }

    func selection(in sections: [RowSection]) -> RowID? {
        let rows = sections.flatMap(\.rows)
        if let s = rawSelection, rows.contains(s) { return s }
        return rows.first
    }

    var currentSelection: RowID? { selection(in: sections) }

    private func matches(_ item: Item, terms: [String], tags: [String]) -> Bool {
        let hay = [item.title, item.notes, item.person, item.tags.joined(separator: " ")]
            .joined(separator: " ").lowercased()
        let itemTags = item.tags.map { $0.lowercased() }
        return terms.allSatisfy(hay.contains) && tags.allSatisfy(itemTags.contains)
    }

    private static func byDue(_ a: Item, _ b: Item) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        if a.priority != b.priority { return a.priority > b.priority }
        return a.createdAt < b.createdAt
    }

    private static func byPriority(_ a: Item, _ b: Item) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        return a.createdAt > b.createdAt
    }

    private static func byCompletion(_ a: Item, _ b: Item) -> Bool {
        (a.completedAt ?? .distantPast) > (b.completedAt ?? .distantPast)
    }

    private func todaySections() -> [RowSection] {
        let today = now.startOfDay
        let tomorrow = today.adding(days: 1)
        let week = today.adding(days: 8)
        let work = store.items.filter { $0.kind != .meeting }
        var seen = Set<UUID>()
        func rows(_ list: [Item]) -> [RowID] {
            list.filter { seen.insert($0.id).inserted }.map { .item($0.id) }
        }

        let schedule = occurrences(from: today, to: tomorrow, kinds: [.meeting, .demo])
        schedule.forEach { if $0.item.kind != .meeting { seen.insert($0.item.id) } }

        let overdue = work.filter { !$0.isDone && ($0.due.map { $0 < today } ?? false) }.sorted(by: Self.byDue)
        let dueToday = work
            .filter { item in
                guard let due = item.due, due >= today, due < tomorrow else { return false }
                return !item.isDone || (item.completedAt.map { $0 >= today } ?? false)
            }
            .sorted { a, b in a.isDone != b.isDone ? !a.isDone : Self.byDue(a, b) }
        let active: Set<Status> = [.inProgress, .review, .blocked]
        let inProgress = work.filter { !$0.isDone && active.contains($0.status) }.sorted(by: Self.byDue)
        let upcoming = work.filter { !$0.isDone && ($0.due.map { $0 >= tomorrow && $0 < week } ?? false) }
            .sorted(by: Self.byDue)

        return [
            RowSection(id: "overdue", title: "Overdue", tint: Theme.red, rows: rows(overdue)),
            RowSection(id: "schedule", title: "Schedule", tint: Theme.teal,
                       rows: schedule.map { .occurrence($0.item.id, $0.start) }),
            RowSection(id: "due", title: "Due Today", tint: Theme.orange, rows: rows(dueToday)),
            RowSection(id: "progress", title: "In Progress", tint: Theme.blue, rows: rows(inProgress)),
            RowSection(id: "upcoming", title: "Next 7 Days", rows: rows(upcoming)),
        ]
    }

    private func searchSections(_ items: [Item], terms: [String]) -> [RowSection] {
        var out = ItemKind.allCases.map { kind in
            RowSection(id: "search-\(kind.rawValue)", title: kind.label + "s",
                       rows: items.filter { $0.kind == kind }.sorted(by: Self.byDue).map { .item($0.id) })
        }
        out += noteSections(terms: terms).map { RowSection(id: "search-" + $0.id, title: "Notes", rows: $0.rows) }
        return out
    }

    private func taskSections(_ tasks: [Item], searching: Bool) -> [RowSection] {
        let today = now.startOfDay, tomorrow = today.adding(days: 1)
        let open = tasks.filter { !$0.isDone }
        let done = tasks.filter(\.isDone).sorted(by: Self.byCompletion)
        return [
            RowSection(id: "overdue", title: "Overdue", tint: Theme.red,
                       rows: open.filter { ($0.due ?? .distantFuture) < today }.sorted(by: Self.byDue).map { .item($0.id) }),
            RowSection(id: "today", title: "Today", tint: Theme.orange,
                       rows: open.filter { $0.due.map { $0 >= today && $0 < tomorrow } ?? false }
                           .sorted(by: Self.byDue).map { .item($0.id) }),
            RowSection(id: "upcoming", title: "Upcoming",
                       rows: open.filter { $0.due.map { $0 >= tomorrow } ?? false }.sorted(by: Self.byDue).map { .item($0.id) }),
            RowSection(id: "someday", title: "No Date",
                       rows: open.filter { $0.due == nil }.sorted(by: Self.byPriority).map { .item($0.id) }),
            RowSection(id: "done", title: "Completed", tint: Theme.green,
                       rows: (searching ? done : Array(done.prefix(15))).map { .item($0.id) }),
        ]
    }

    private func meetingSections(_ meetings: [Item], searching: Bool) -> [RowSection] {
        let today = now.startOfDay
        let horizon = today.adding(days: 14)
        let ids = Set(meetings.map(\.id))
        let upcoming = occurrences(from: today, to: horizon).filter { ids.contains($0.item.id) }
        let byDay = Dictionary(grouping: upcoming) { $0.start.startOfDay }

        var out = byDay.keys.sorted().map { day in
            RowSection(id: "day-\(Int(day.timeIntervalSince1970))", title: Fmt.dayHeader(day),
                       tint: Calendar.current.isDateInToday(day) ? Theme.teal : nil,
                       rows: byDay[day]!.map { .occurrence($0.item.id, $0.start) })
        }
        out.append(RowSection(id: "unscheduled", title: "Unscheduled",
                              rows: meetings.filter { $0.due == nil }.map { .item($0.id) }))
        let past = meetings
            .filter { $0.recurrence == .none && ($0.due.map { $0 < today } ?? false) }
            .sorted { ($0.due ?? .distantPast) > ($1.due ?? .distantPast) }
        out.append(RowSection(id: "past", title: "Earlier",
                              rows: (searching ? past : Array(past.prefix(10))).map { .item($0.id) }))
        return out
    }

    private func demoSections(_ demos: [Item], searching: Bool) -> [RowSection] {
        let today = now.startOfDay
        let open = demos.filter { !$0.isDone }
        let done = demos.filter(\.isDone).sorted(by: Self.byCompletion)
        return [
            RowSection(id: "overdue", title: "Needs Follow-up", tint: Theme.red,
                       rows: open.filter { ($0.due ?? .distantFuture) < today }.sorted(by: Self.byDue).map { .item($0.id) }),
            RowSection(id: "upcoming", title: "Upcoming", tint: Theme.purple,
                       rows: open.filter { ($0.due ?? .distantFuture) >= today }.sorted(by: Self.byDue).map { .item($0.id) }),
            RowSection(id: "done", title: "Delivered", tint: Theme.green,
                       rows: (searching ? done : Array(done.prefix(15))).map { .item($0.id) }),
        ]
    }

    private func deliverableSections(_ list: [Item], searching: Bool) -> [RowSection] {
        let order: [Status] = [.blocked, .review, .inProgress, .todo, .done]
        return order.map { status in
            var group = list.filter { $0.status == status }
            if status == .done {
                group.sort(by: Self.byCompletion)
                if !searching { group = Array(group.prefix(15)) }
            } else {
                group.sort(by: Self.byDue)
            }
            return RowSection(id: status.rawValue, title: status.label,
                              tint: status == .todo ? nil : status.tint, rows: group.map { .item($0.id) })
        }
    }

    private func noteSections(terms: [String]) -> [RowSection] {
        let notes = store.notes
            .filter { note in terms.isEmpty || terms.allSatisfy { note.body.lowercased().contains($0) } }
            .sorted { $0.updatedAt > $1.updatedAt }
        return [
            RowSection(id: "pinned", title: "Pinned", tint: Theme.yellow,
                       rows: notes.filter(\.pinned).map { .note($0.id) }),
            RowSection(id: "notes", title: "Notes", rows: notes.filter { !$0.pinned }.map { .note($0.id) }),
        ]
    }

    // MARK: Header stats & badges

    struct TodayStats {
        var done = 0
        var total = 0
        var dueOpen = 0
        var overdue = 0
        var meetingsLeft = 0
        var demosThisWeek = 0
        var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    var todayStats: TodayStats {
        let today = now.startOfDay, tomorrow = today.adding(days: 1), week = today.adding(days: 7)
        var s = TodayStats()
        for item in store.items where item.kind != .meeting {
            let due = item.due
            if let due, due >= today, due < tomorrow {
                if item.isDone, (item.completedAt ?? .distantPast) >= today { s.done += 1; s.total += 1 }
                if !item.isDone { s.dueOpen += 1; s.total += 1 }
            }
            if !item.isDone, let due, due < today { s.overdue += 1; s.total += 1 }
            if item.kind == .demo, !item.isDone, let due, due >= today, due < week { s.demosThisWeek += 1 }
        }
        s.meetingsLeft = occurrences(from: now, to: tomorrow).count
        return s
    }

    func badge(for tab: Tab) -> Int? {
        let open = { (kind: ItemKind) in self.store.items.filter { $0.kind == kind && !$0.isDone }.count }
        let count: Int = switch tab {
        case .today: todayStats.overdue
        case .tasks: open(.task)
        case .meetings: occurrences(from: now, to: now.startOfDay.adding(days: 1)).count
        case .demos: open(.demo)
        case .deliverables: open(.deliverable)
        case .notes: 0
        }
        return count > 0 ? count : nil
    }

    var footerHints: [KeyHint] {
        if showSettings { return [KeyHint(label: "Close", key: "esc")] }
        switch currentSelection {
        case .create?:
            return [KeyHint(label: "Create", key: "↵"), KeyHint(label: "Create & edit", key: "⌘↵")]
        case .note?:
            return [KeyHint(label: "Write", key: "↵"), KeyHint(label: "New note", key: "⌘N"),
                    KeyHint(label: "Delete", key: "⌘⌫")]
        case let sel?:
            guard let id = sel.itemID, let item = store.item(id) else { return [] }
            if item.kind == .meeting {
                return [KeyHint(label: item.joinURL == nil ? "Edit" : "Join", key: "↵"),
                        KeyHint(label: "Edit", key: "⌘↵"), KeyHint(label: "Delete", key: "⌘⌫")]
            }
            return [KeyHint(label: item.isDone ? "Reopen" : "Complete", key: "↵"),
                    KeyHint(label: "Edit", key: "⌘↵"), KeyHint(label: "Status", key: "⌘S"),
                    KeyHint(label: "Priority", key: "⌘P"), KeyHint(label: "Delete", key: "⌘⌫")]
        case nil:
            return [KeyHint(label: "Settings", key: "⌘,")]
        }
    }

    // MARK: Actions

    func move(_ delta: Int) {
        let rows = sections.flatMap(\.rows)
        guard !rows.isEmpty else { return }
        let current = selection(in: sections).flatMap { rows.firstIndex(of: $0) } ?? 0
        rawSelection = rows[max(0, min(rows.count - 1, current + delta))]
    }

    func cycleTab(_ delta: Int) {
        let count = Tab.allCases.count
        withAnimation(.snappy(duration: 0.22)) {
            tab = Tab(rawValue: (tab.rawValue + delta + count) % count) ?? .today
        }
    }

    func select(_ row: RowID) {
        rawSelection = row
        focusCommandField()
    }

    func primary() {
        guard let sel = currentSelection else { return }
        switch sel {
        case .create:
            commitDraft()
        case let .note(id):
            requestFocus(.note(id))
        case .item, .occurrence:
            guard let id = sel.itemID, let item = store.item(id) else { return }
            if item.kind == .meeting {
                if !join(item) { requestFocus(sel) }
            } else {
                withAnimation(.snappy(duration: 0.25)) { store.toggleDone(id) }
                if let updated = store.item(id), updated.isDone {
                    showToast("Completed “\(updated.title)”", symbol: "checkmark.circle.fill")
                }
            }
        }
    }

    func editSelection() {
        guard let sel = currentSelection else { return }
        if sel == .create {
            if let row = commitDraft() { requestFocus(row) }
        } else {
            requestFocus(sel)
        }
    }

    @discardableResult
    func join(_ item: Item) -> Bool {
        guard let url = item.joinURL else { return false }
        NSWorkspace.shared.open(url)
        hidePanel()
        return true
    }

    func joinSelection() {
        guard let id = currentSelection?.itemID, let item = store.item(id) else { return }
        if !join(item) { showToast("No meeting link on this item", symbol: "link.badge.plus") }
    }

    @discardableResult
    func commitDraft() -> RowID? {
        guard let d = draft, !d.isEmpty else { return nil }
        switch d.kind {
        case .note:
            let note = store.addNote(d.title + "\n")
            query = ""
            tab = .notes
            rawSelection = .note(note.id)
            requestFocus(.note(note.id))
            return .note(note.id)

        case let .item(kind):
            var item = Item(kind: kind, title: d.title)
            item.due = d.due
            item.hasTime = d.hasTime
            item.priority = d.priority
            item.tags = d.tags
            item.link = d.link
            item.recurrence = d.recurrence
            item.repeatDays = d.repeatDays
            if let minutes = d.durationMinutes { item.durationMinutes = minutes }
            withAnimation(.snappy(duration: 0.25)) { store.add(item) }
            query = ""
            let row = sections.flatMap(\.rows).first { $0.itemID == item.id }
            rawSelection = row
            let when = item.due.map { " · " + Fmt.due($0, hasTime: item.hasTime, now: now) } ?? ""
            showToast("\(kind.label) added\(when)", symbol: kind.symbol)
            return row ?? .item(item.id)
        }
    }

    func newNote() {
        let note = store.addNote("")
        query = ""
        tab = .notes
        showSettings = false
        rawSelection = .note(note.id)
        requestFocus(.note(note.id))
    }

    func deleteSelection() {
        let rows = sections.flatMap(\.rows)
        guard let sel = selection(in: sections), sel != .create, let index = rows.firstIndex(of: sel) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            switch sel {
            case .create:
                break
            case let .note(id):
                store.deleteNote(id)
            case .item, .occurrence:
                if let id = sel.itemID { store.deleteItem(id) }
            }
        }
        let remaining = sections.flatMap(\.rows)
        rawSelection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
        showToast("Deleted", symbol: "trash", undo: true)
        focusCommandField()
    }

    func deleteNote(_ id: UUID) {
        rawSelection = .note(id)
        deleteSelection()
    }

    func deleteItem(_ id: UUID) {
        withAnimation(.snappy(duration: 0.22)) { store.deleteItem(id) }
        showToast("Deleted", symbol: "trash", undo: true)
        focusCommandField()
    }

    func undoDelete() {
        guard let row = withAnimation(.snappy(duration: 0.22), { store.undoDelete() }) else { return }
        if case .note = row, tab != .notes { tab = .notes }
        rawSelection = row
        showToast("Restored", symbol: "arrow.uturn.backward")
    }

    func cycleStatus() {
        guard let id = currentSelection?.itemID, let item = store.item(id), item.kind != .meeting else { return }
        withAnimation(.snappy(duration: 0.2)) { store.cycleStatus(id) }
        if let s = store.item(id)?.status { showToast("Status · \(s.label)", symbol: s.symbol) }
    }

    func cyclePriority() {
        guard let id = currentSelection?.itemID, store.item(id) != nil else { return }
        withAnimation(.snappy(duration: 0.2)) { store.cyclePriority(id) }
        if let p = store.item(id)?.priority { showToast("Priority · \(p.label)", symbol: "flag.fill") }
    }

    func escape() {
        if !isCommandFocused {
            focusCommandField()
        } else if showSettings {
            showSettings = false
        } else if !query.isEmpty {
            query = ""
        } else {
            hidePanel()
        }
    }

    // MARK: Focus

    func requestFocus(_ row: RowID) {
        focusCounter += 1
        focusRequest = FocusRequest(target: row, token: focusCounter)
    }

    var isCommandFocused: Bool {
        guard let field = commandField, let editor = field.window?.firstResponder as? NSTextView else {
            return commandField?.window?.firstResponder === commandField?.window
        }
        return (editor.delegate as AnyObject?) === field
    }

    func focusCommandField(selectAll: Bool = false) {
        guard let field = commandField, let window = field.window else { return }
        if !isCommandFocused || window.firstResponder === window {
            window.makeFirstResponder(field)
        }
        if let editor = field.currentEditor() {
            let length = (field.stringValue as NSString).length
            editor.selectedRange = selectAll ? NSRange(location: 0, length: length) : NSRange(location: length, length: 0)
        }
    }

    // MARK: Toast

    func showToast(_ text: String, symbol: String, undo: Bool = false) {
        toastWork?.cancel()
        withAnimation(.snappy(duration: 0.2)) { toast = Toast(text: text, symbol: symbol, undo: undo) }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (undo ? 5 : 2.2), execute: work)
    }
}
