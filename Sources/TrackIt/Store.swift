import Foundation
import Observation

/// Owns all user data and persists it as JSON in Application Support.
@Observable
final class Store {
    var items: [Item] = [] { didSet { scheduleSave() } }
    var notes: [Note] = [] { didSet { scheduleSave() } }

    enum Deleted {
        case item(Item, Int)
        case note(Note, Int)
    }

    @ObservationIgnored private(set) var lastDeleted: Deleted?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored let fileURL: URL

    private struct Payload: Codable {
        var version = 1
        var items: [Item]
        var notes: [Note]
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = support.appendingPathComponent("TrackIt", isDirectory: true)
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["TRACKIT_DATA_DIR"] {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        load()
    }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            seed()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Payload.self, from: data)
            items = payload.items
            notes = payload.notes
        } catch {
            // Keep the unreadable file around rather than overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("data.corrupt-\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("TrackIt: failed to load data (\(error)); backed up to \(backup.path)")
        }
    }

    private func seed() {
        notes = [Note(body: Self.welcomeNote)]
        var sample = Item(kind: .task, title: "Try quick add — type a task above and press ↵")
        sample.due = Date().startOfDay
        sample.priority = .medium
        items = [sample]
        saveNow()
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(Payload(items: items, notes: notes))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("TrackIt: failed to save data: \(error)")
        }
    }

    // MARK: Items

    func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    func add(_ item: Item) { items.append(item) }

    func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var copy = items[i]
        change(&copy)
        if copy != items[i] { items[i] = copy }
    }

    func toggleDone(_ id: UUID) {
        update(id) { $0.status = $0.status == .done ? .todo : .done }
    }

    func cycleStatus(_ id: UUID) { update(id) { $0.status = $0.status.next } }

    func cyclePriority(_ id: UUID) { update(id) { $0.priority = $0.priority.next } }

    func deleteItem(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        lastDeleted = .item(items[i], i)
        items.remove(at: i)
    }

    // MARK: Notes

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func addNote(_ body: String) -> Note {
        let note = Note(body: body)
        notes.insert(note, at: 0)
        return note
    }

    func updateNote(_ id: UUID, _ change: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var copy = notes[i]
        change(&copy)
        if copy != notes[i] { notes[i] = copy }
    }

    func deleteNote(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        lastDeleted = .note(notes[i], i)
        notes.remove(at: i)
    }

    // MARK: Undo

    var canUndoDelete: Bool { lastDeleted != nil }

    /// Restores the most recently deleted item or note and returns its row.
    func undoDelete() -> RowID? {
        guard let deleted = lastDeleted else { return nil }
        lastDeleted = nil
        switch deleted {
        case let .item(item, index):
            items.insert(item, at: min(index, items.count))
            return .item(item.id)
        case let .note(note, index):
            notes.insert(note, at: min(index, notes.count))
            return .note(note.id)
        }
    }

    static let welcomeNote = """
    Welcome to TrackIt 👋

    Press ⌥T anywhere to summon this window. Esc hides it.

    QUICK ADD — type in the bar at the top and press ↵
      • Ship invoice fix tomorrow !high #billing
      • meet: Standup 10am 15m every weekday https://meet.google.com/abc
      • demo: Acme walkthrough fri 3pm #sales
      • del: Q4 board deck by oct 20
      • note: Ideas for onboarding

    Prefixes: task:  meet:  demo:  del:  note:
    Otherwise new entries take the type of the tab you're on.

    KEYBOARD
      ↑ ↓      move               ↵    complete / join / open
      ⌘↵       edit details       ⌘S   cycle status
      ⌘P       cycle priority     ⌘J   join meeting
      ⌘⌫       delete             ⌘Z   undo delete
      ⌘1–6     switch tabs        Tab  next tab
      ⌘N       new note           ⌘,   settings

    Meetings and timed demos pop a heads-up card before they start.
    """
}
