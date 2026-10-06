import SwiftUI

struct ListPane: View {
    let sections: [RowSection]
    let selection: RowID?
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    Color.clear.frame(height: 0).id("top")

                    if state.tab == .today && state.query.isEmpty {
                        TodayHeader()
                            .padding(.bottom, 4)
                    }

                    if sections.isEmpty {
                        EmptyList(tab: state.tab)
                    }

                    ForEach(sections) { section in
                        if !section.title.isEmpty {
                            SectionHeader(title: section.title, count: section.rows.count, tint: section.tint)
                        }
                        ForEach(section.rows, id: \.self) { row in
                            RowView(row: row, isSelected: row == selection)
                                .id(row)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: selection) { _, new in
                guard let new else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    if new == sections.first?.rows.first {
                        proxy.scrollTo("top", anchor: .top)
                    } else {
                        proxy.scrollTo(new)
                    }
                }
            }
        }
    }
}

private struct EmptyList: View {
    let tab: Tab

    private var message: (String, String) {
        switch tab {
        case .today: ("All clear", "Nothing due today. Type above to add something.")
        case .tasks: ("No tasks yet", "Type a task above and press ↵")
        case .meetings: ("No meetings", "Try “Standup 10am 15m every weekday”")
        case .demos: ("No demos lined up", "Try “Acme walkthrough fri 3pm #sales”")
        case .deliverables: ("No deliverables", "Try “Q4 board deck by oct 20”")
        case .notes: ("No notes", "Press ⌘N or type a title and press ↵")
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            KindBadge(symbol: tab.symbol, tint: tab.tint, size: 40)
            Text(message.0).font(.system(size: 14, weight: .semibold))
            Text(message.1).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, tab == .today ? 30 : 110)
    }
}

struct RowView: View {
    let row: RowID
    let isSelected: Bool
    @Environment(AppState.self) private var state

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.10) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule().fill(Theme.accentGradient).frame(width: 3, height: 16).offset(x: -1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { state.select(row) }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                state.select(row)
                state.primary()
            })
            .contextMenu { menu }
    }

    @ViewBuilder
    private var content: some View {
        switch row {
        case .create:
            if let draft = state.draft { CreateRow(draft: draft) }
        case let .item(id):
            if let item = state.store.item(id) {
                if item.kind == .meeting {
                    TimedRow(item: item, start: item.nextStart(after: state.now), now: state.now)
                } else {
                    ItemRow(item: item, showKind: state.tab == .today)
                }
            }
        case let .occurrence(id, start):
            if let item = state.store.item(id) {
                TimedRow(item: item, start: start, now: state.now)
            }
        case let .note(id):
            if let note = state.store.note(id) { NoteRow(note: note, now: state.now) }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let id = row.itemID, let item = state.store.item(id) {
            if item.joinURL != nil {
                Button("Join") { state.join(item) }
            }
            if item.kind != .meeting {
                Button(item.isDone ? "Mark as Not Done" : "Mark as Done") { state.store.toggleDone(id) }
                Menu("Status") {
                    ForEach(Status.allCases) { s in
                        Button(s.label) { state.store.update(id) { $0.status = s } }
                    }
                }
            }
            Menu("Priority") {
                ForEach(Priority.allCases) { p in
                    Button(p.label) { state.store.update(id) { $0.priority = p } }
                }
            }
            Divider()
            Button("Edit") { state.select(row); state.requestFocus(row) }
            Button("Delete", role: .destructive) { state.deleteItem(id) }
        } else if case let .note(id) = row, let note = state.store.note(id) {
            Button(note.pinned ? "Unpin" : "Pin") { state.store.updateNote(id) { $0.pinned.toggle() } }
            Button("Delete", role: .destructive) { state.deleteNote(id) }
        }
    }
}

// MARK: Rows

struct StatusButton: View {
    let item: Item
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { state.store.toggleDone(item.id) }
        } label: {
            Image(systemName: item.status.symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch item.status {
        case .done: item.kind.tint
        case .todo: Color.secondary.opacity(0.7)
        default: item.status.tint
        }
    }
}

struct ItemRow: View {
    let item: Item
    var showKind = false
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 11) {
            StatusButton(item: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                meta
            }
            Spacer(minLength: 6)
            if item.priority != .none && !item.isDone {
                Text(item.priority.bangs)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(item.priority.tint)
            }
        }
        .opacity(item.isDone ? 0.75 : 1)
    }

    @ViewBuilder
    private var meta: some View {
        let today = state.now.startOfDay
        let parts = metaParts(today: today)
        if !parts.isEmpty {
            HStack(spacing: 8) {
                ForEach(parts.indices, id: \.self) { i in parts[i] }
            }
        }
    }

    private func metaParts(today: Date) -> [AnyView] {
        var parts: [AnyView] = []
        if showKind {
            parts.append(AnyView(Chip(symbol: item.kind.symbol, text: item.kind.label, tint: item.kind.tint)))
        }
        if let due = item.due {
            let overdue = !item.isDone && due < (item.hasTime ? state.now : today)
            let isToday = Calendar.current.isDateInToday(due)
            let tint: Color = overdue ? Theme.red : (isToday && !item.isDone ? Theme.orange : .secondary)
            parts.append(AnyView(Chip(symbol: item.hasTime ? "clock" : "calendar",
                                      text: Fmt.due(due, hasTime: item.hasTime, now: state.now), tint: tint)))
        }
        if [.inProgress, .review, .blocked].contains(item.status) {
            parts.append(AnyView(Chip(text: item.status.label, tint: item.status.tint, filled: true)))
        }
        if !item.person.isEmpty {
            parts.append(AnyView(Chip(symbol: "person.fill", text: item.person)))
        }
        for tag in item.tags.prefix(3) {
            parts.append(AnyView(Text("#\(tag)").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)))
        }
        if !item.notes.isEmpty {
            parts.append(AnyView(Image(systemName: "text.alignleft").font(.system(size: 9.5)).foregroundStyle(.tertiary)))
        }
        if item.joinURL != nil {
            parts.append(AnyView(Image(systemName: "link").font(.system(size: 9.5)).foregroundStyle(.tertiary)))
        }
        return parts
    }
}

/// A row for something that happens at a time: meetings and scheduled demos.
struct TimedRow: View {
    let item: Item
    let start: Date?
    let now: Date

    private var end: Date? { start?.addingTimeInterval(TimeInterval(item.effectiveDuration * 60)) }
    private var isLive: Bool { if let start, let end { start <= now && end > now } else { false } }
    private var isPast: Bool { end.map { $0 <= now } ?? false }

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .trailing, spacing: 1) {
                if let start, item.hasTime {
                    Text(Fmt.time(start))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text(Fmt.duration(item.durationMinutes))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text(start == nil ? "—" : "All day")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(item.kind.tint.gradient)
                .frame(width: 3.5, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(item.isDone, color: .secondary)
                HStack(spacing: 8) {
                    if item.kind != .meeting {
                        Chip(symbol: item.kind.symbol, text: item.kind.label, tint: item.kind.tint)
                    }
                    if let start, !Calendar.current.isDate(start, inSameDayAs: now) {
                        Chip(symbol: "calendar", text: Fmt.day(start, now: now))
                    }
                    if item.recurrence != .none {
                        Chip(symbol: "repeat", text: item.recurrenceLabel)
                    }
                    if !item.person.isEmpty {
                        Chip(symbol: "person.2.fill", text: item.person)
                    }
                    if item.joinURL != nil {
                        Chip(symbol: "video.fill", text: "Link", tint: Theme.teal)
                    }
                }
            }

            Spacer(minLength: 6)

            if isLive {
                HStack(spacing: 5) {
                    PulseDot(color: Theme.green)
                    Text("NOW").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.green.opacity(0.14)))
            } else if let start, item.hasTime, start > now, start.timeIntervalSince(now) < 3 * 3600 {
                Text(Fmt.countdown(to: start, from: now))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(item.kind.tint)
            }
        }
        .opacity(isPast ? 0.45 : 1)
    }
}

struct NoteRow: View {
    let note: Note
    let now: Date

    var body: some View {
        HStack(spacing: 11) {
            KindBadge(symbol: note.pinned ? "pin.fill" : "note.text", tint: Theme.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Fmt.relative(note.updatedAt, now: now))
                        .foregroundStyle(.tertiary)
                    if !note.preview.isEmpty {
                        Text(note.preview).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
    }
}

struct CreateRow: View {
    let draft: Draft

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(draft.kind.tint.gradient)
                Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Create \(draft.kind.label)").foregroundStyle(.secondary)
                    Text(draft.title).fontWeight(.semibold).lineLimit(1)
                }
                .font(.system(size: 13.5))
                DraftChips(draft: draft)
            }
            Spacer(minLength: 0)
        }
    }
}

struct DraftChips: View {
    let draft: Draft

    var body: some View {
        HStack(spacing: 8) {
            if let due = draft.due {
                Chip(symbol: draft.hasTime ? "clock" : "calendar", text: Fmt.due(due, hasTime: draft.hasTime), tint: Theme.orange, filled: true)
            }
            if let minutes = draft.durationMinutes {
                Chip(symbol: "hourglass", text: Fmt.duration(minutes), tint: Theme.teal, filled: true)
            }
            if draft.recurrence != .none {
                Chip(symbol: "repeat", text: draft.recurrence.label(days: draft.repeatDays), tint: Theme.teal, filled: true)
            }
            if draft.priority != .none {
                Chip(symbol: "flag.fill", text: draft.priority.label, tint: draft.priority.tint, filled: true)
            }
            ForEach(draft.tags, id: \.self) { tag in
                Chip(text: "#\(tag)", tint: Theme.accent, filled: true)
            }
            if !draft.link.isEmpty {
                Chip(symbol: "link", text: "Link", tint: Theme.blue, filled: true)
            }
        }
    }
}
