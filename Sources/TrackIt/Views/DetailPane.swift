import SwiftUI

struct DetailPane: View {
    let selection: RowID?

    var body: some View {
        switch selection {
        case .create?:
            CheatSheet(title: "Quick add syntax")
        case let .item(id)?:
            ItemDetail(id: id, row: .item(id)).id(id)
        case let .occurrence(id, start)?:
            ItemDetail(id: id, row: .occurrence(id, start), occurrenceStart: start).id(id)
        case let .note(id)?:
            NoteEditor(id: id).id(id)
        case nil:
            CheatSheet(title: "Get going")
        }
    }
}

// MARK: Item detail

struct ItemDetail: View {
    let id: UUID
    let row: RowID
    var occurrenceStart: Date?

    @Environment(AppState.self) private var state
    @FocusState private var titleFocused: Bool

    var body: some View {
        if let item = state.store.item(id) {
            let binding = Binding<Item>(
                get: { state.store.item(id) ?? item },
                set: { new in state.store.update(id) { $0 = new } }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(item, binding)

                    TextField("Title", text: binding.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19, weight: .semibold))
                        .focused($titleFocused)
                        .onSubmit { state.focusCommandField() }

                    if item.kind == .meeting || item.hasTime, let start = occurrenceStart ?? item.nextStart(after: state.now) {
                        timeBanner(item, start: start)
                    }

                    properties(item, binding)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        TextEditor(text: binding.notes)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }

                    Text(footerText(item))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
            }
            .onAppear { applyFocus(delayed: true) }
            .onChange(of: state.focusRequest) { _, _ in applyFocus(delayed: false) }
        }
    }

    private func applyFocus(delayed: Bool) {
        guard let request = state.focusRequest, request.target.itemID == id else { return }
        if delayed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { titleFocused = true }
        } else {
            titleFocused = true
        }
        state.focusRequest = nil
    }

    private func header(_ item: Item, _ binding: Binding<Item>) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ItemKind.allCases) { kind in
                    Button { binding.wrappedValue.kind = kind } label: { Label(kind.label, systemImage: kind.symbol) }
                }
            } label: {
                Chip(symbol: item.kind.symbol, text: item.kind.label, tint: item.kind.tint, filled: true)
            }
            .chipMenu()

            Spacer()

            if item.kind != .meeting {
                IconButton(symbol: item.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle",
                           tint: item.isDone ? .secondary : Theme.green,
                           help: item.isDone ? "Reopen" : "Mark done") {
                    withAnimation(.snappy(duration: 0.25)) { state.store.toggleDone(id) }
                }
            }
            IconButton(symbol: "trash", tint: .secondary, help: "Delete (⌘⌫)") { state.deleteItem(id) }
        }
    }

    private func timeBanner(_ item: Item, start: Date) -> some View {
        let end = start.addingTimeInterval(TimeInterval(item.effectiveDuration * 60))
        let live = start <= state.now && end > state.now
        return HStack(spacing: 10) {
            Image(systemName: live ? "dot.radiowaves.left.and.right" : "clock.fill")
                .foregroundStyle(item.kind.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.hasTime ? "\(Fmt.dayHeader(start)) · \(Fmt.timeRange(start, end))" : Fmt.dayHeader(start))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(live ? "Happening now" : (end < state.now ? "Ended" : Fmt.countdown(to: start, from: state.now).capitalized))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.joinURL != nil {
                PillButton(title: "Join", symbol: "video.fill", prominent: true) { state.join(item) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(item.kind.tint.opacity(0.10)))
    }

    @ViewBuilder
    private func properties(_ item: Item, _ binding: Binding<Item>) -> some View {
        VStack(spacing: 0) {
            if item.kind != .meeting {
                PropRow(label: "Status", symbol: "circle.dashed") {
                    Menu {
                        ForEach(Status.allCases) { s in
                            Button { binding.wrappedValue.status = s } label: { Label(s.label, systemImage: s.symbol) }
                        }
                    } label: {
                        Chip(symbol: item.status.symbol, text: item.status.label,
                             tint: item.status == .todo ? .primary : item.status.tint, filled: true)
                    }
                    .chipMenu()
                }
                PropRow(label: "Priority", symbol: "flag") {
                    HStack(spacing: 4) {
                        ForEach(Priority.allCases) { p in
                            let selected = item.priority == p
                            Button { binding.wrappedValue.priority = p } label: {
                                Text(p.label)
                                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? (p == .none ? Color.primary : p.tint) : Color.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(selected ? (p == .none ? Color.primary : p.tint).opacity(0.15) : Color.clear))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            PropRow(label: item.kind == .meeting ? "When" : "Due", symbol: "calendar") {
                DueEditor(item: item, binding: binding)
            }

            if item.kind == .meeting || item.hasTime {
                PropRow(label: "Duration", symbol: "hourglass") {
                    Menu {
                        ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { m in
                            Button(Fmt.duration(m)) { binding.wrappedValue.durationMinutes = m }
                        }
                    } label: {
                        Chip(text: Fmt.duration(item.durationMinutes), tint: .primary, filled: true)
                    }
                    .chipMenu()
                }
            }

            if item.kind == .meeting || item.kind == .demo {
                PropRow(label: "Repeats", symbol: "repeat") {
                    Menu {
                        ForEach(Recurrence.allCases) { r in
                            Button(r == .custom ? "Specific days…" : r.label) { setRecurrence(r, item, binding) }
                        }
                    } label: {
                        Chip(text: item.recurrence == .custom ? "Specific days" : item.recurrence.label,
                             tint: item.recurrence == .none ? .secondary : Theme.teal, filled: true)
                    }
                    .chipMenu()
                }
                if item.recurrence == .custom {
                    PropRow(label: "On", symbol: "calendar.day.timeline.left") {
                        WeekdayPicker(days: binding.repeatDays)
                    }
                }
            }

            PropRow(label: item.kind.personLabel, symbol: "person") {
                TextField("Add…", text: binding.person).textFieldStyle(.plain)
            }

            PropRow(label: "Link", symbol: "link") {
                HStack {
                    TextField("https://…", text: binding.link).textFieldStyle(.plain)
                    if let url = item.joinURL {
                        IconButton(symbol: "arrow.up.right", tint: Theme.accent, help: "Open link") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            PropRow(label: "Tags", symbol: "number", last: true) {
                TextField("Add tags…", text: Binding(
                    get: { binding.wrappedValue.tags.joined(separator: ", ") },
                    set: { binding.wrappedValue.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty } }
                ))
                .textFieldStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func setRecurrence(_ rule: Recurrence, _ item: Item, _ binding: Binding<Item>) {
        binding.wrappedValue.recurrence = rule
        if rule == .custom, item.repeatDays.isEmpty {
            // Seed with the weekday the item is currently on.
            binding.wrappedValue.repeatDays = [Calendar.current.component(.weekday, from: item.due ?? Date())]
        }
        if rule != .none, item.due == nil {
            binding.wrappedValue.due = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())
            binding.wrappedValue.hasTime = true
        }
    }

    private func footerText(_ item: Item) -> String {
        var parts = ["Created \(Fmt.relative(item.createdAt, now: state.now))"]
        if let done = item.completedAt { parts.append("completed \(Fmt.relative(done, now: state.now))") }
        return parts.joined(separator: " · ")
    }
}

private struct PropRow<Content: View>: View {
    let label: String
    let symbol: String
    var last = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label {
                    Text(label)
                } icon: {
                    Image(systemName: symbol).frame(width: 14)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
                content
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            if !last {
                Divider().opacity(0.5).padding(.leading, 12)
            }
        }
    }
}

/// Seven round toggles (M T W T F S S) for choosing repeat days.
private struct WeekdayPicker: View {
    @Binding var days: [Int]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.mondayFirst, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on {
                        guard days.count > 1 else { return } // keep at least one day
                        days.removeAll { $0 == day }
                    } else {
                        days = (days + [day]).sorted()
                    }
                } label: {
                    Text(Weekday.initial(day))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(on ? Color.white : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(on ? AnyShapeStyle(Theme.teal.gradient) : AnyShapeStyle(Color.primary.opacity(0.08))))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Calendar.current.weekdaySymbols[day - 1])
            }
        }
    }
}

private struct DueEditor: View {
    let item: Item
    let binding: Binding<Item>

    var body: some View {
        if let due = item.due {
            HStack(spacing: 6) {
                DatePicker("", selection: Binding(get: { due }, set: { binding.wrappedValue.due = $0 }),
                           displayedComponents: item.hasTime ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
                IconButton(symbol: item.hasTime ? "clock.fill" : "clock", tint: item.hasTime ? Theme.accent : .secondary,
                           help: item.hasTime ? "Remove time" : "Add a time") {
                    toggleTime(due)
                }
                if item.kind != .meeting {
                    IconButton(symbol: "xmark.circle", help: "Clear date") {
                        binding.wrappedValue.due = nil
                        binding.wrappedValue.hasTime = false
                    }
                }
            }
        } else {
            HStack(spacing: 4) {
                quick("Today", Date().startOfDay)
                quick("Tomorrow", Date().startOfDay.adding(days: 1))
                quick("Next week", nextMonday)
            }
        }
    }

    private var nextMonday: Date {
        let cal = Calendar.current
        let start = Date().startOfDay
        return cal.nextDate(after: start, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? start.adding(days: 7)
    }

    private func quick(_ title: String, _ date: Date) -> some View {
        Button {
            binding.wrappedValue.due = item.kind == .meeting
                ? Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date)
                : date
            binding.wrappedValue.hasTime = item.kind == .meeting
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleTime(_ due: Date) {
        if item.hasTime {
            binding.wrappedValue.hasTime = false
            binding.wrappedValue.due = due.startOfDay
        } else {
            binding.wrappedValue.hasTime = true
            binding.wrappedValue.due = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: due)
        }
    }
}

// MARK: Notes

struct NoteEditor: View {
    let id: UUID
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    var body: some View {
        if let note = state.store.note(id) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    KindBadge(symbol: "note.text", tint: Theme.yellow, size: 20)
                    Text("Edited \(Fmt.relative(note.updatedAt, now: state.now))")
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(note.wordCount) words").foregroundStyle(.tertiary)
                    Spacer()
                    IconButton(symbol: note.pinned ? "pin.fill" : "pin",
                               tint: note.pinned ? Theme.yellow : .secondary,
                               help: note.pinned ? "Unpin" : "Pin") {
                        withAnimation(.snappy(duration: 0.2)) { state.store.updateNote(id) { $0.pinned.toggle() } }
                    }
                    IconButton(symbol: "trash", help: "Delete note") { state.deleteNote(id) }
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 14)
                .frame(height: 40)

                Divider().opacity(0.5)

                TextEditor(text: Binding(
                    get: { state.store.note(id)?.body ?? "" },
                    set: { text in
                        state.store.updateNote(id) { note in
                            guard note.body != text else { return }
                            note.body = text
                            note.updatedAt = Date()
                        }
                    }
                ))
                .font(.system(size: 14))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onAppear { applyFocus(delayed: true) }
            .onChange(of: state.focusRequest) { _, _ in applyFocus(delayed: false) }
        }
    }

    private func applyFocus(delayed: Bool) {
        guard state.focusRequest?.target == .note(id) else { return }
        if delayed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        } else {
            focused = true
        }
        state.focusRequest = nil
    }
}

// MARK: Help

struct CheatSheet: View {
    let title: String
    @Environment(AppState.self) private var state

    private let syntax: [(String, String)] = [
        ("task:  meet:  demo:  del:  note:", "Pick the type"),
        ("tomorrow 3pm · next fri · oct 12", "Date & time"),
        ("!high   !!   !low", "Priority"),
        ("#client", "Tag"),
        ("30m · 1h", "Meeting length"),
        ("every weekday · every mon wed fri", "Repeat"),
        ("https://meet.google.com/…", "Join link"),
    ]

    private let keys: [(String, String)] = [
        ("↑ ↓", "Move"), ("↵", "Complete · join · open"), ("⌘↵", "Edit details"),
        ("⌘S / ⌘P", "Status / priority"), ("⌘⌫ · ⌘Z", "Delete · undo"),
        ("⌘1–6 · Tab", "Switch tabs"), ("⌘N", "New note"), ("esc", "Back · clear · hide"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let draft = state.draft, !draft.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WILL CREATE")
                            .font(.system(size: 10.5, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            KindBadge(symbol: draft.kind.symbol, tint: draft.kind.tint, size: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                DraftChips(draft: draft)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(draft.kind.tint.opacity(0.10)))
                    }
                } else {
                    HStack(spacing: 10) {
                        AppGlyph(size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.system(size: 15, weight: .semibold))
                            Text("Everything starts in the bar above.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                }

                table("QUICK ADD", syntax, mono: true)
                table("KEYBOARD", keys, mono: false)
            }
            .padding(18)
        }
    }

    private func table(_ heading: String, _ rows: [(String, String)], mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading).font(.system(size: 10.5, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Text(rows[i].0)
                            .font(mono ? .system(size: 11.5, design: .monospaced) : .system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(mono ? Theme.accent : Color.primary)
                        Spacer()
                        Text(rows[i].1).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    if i < rows.count - 1 { Divider().opacity(0.4).padding(.leading, 12) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }
}
