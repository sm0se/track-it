import SwiftUI

struct TodayHeader: View {
    @Environment(AppState.self) private var state

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: state.now)
        let part = hour < 5 ? "Working late" : hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? part : "\(part), \(first)"
    }

    var body: some View {
        let stats = state.todayStats
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(greeting)
                        .font(.system(size: 19, weight: .bold))
                    Text(Fmt.fullDate(state.now))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressRing(progress: stats.progress, label: "\(stats.done)/\(stats.total)")
                    .help("Completed today")
            }

            if let next = state.nextUp() {
                NextUpCard(occurrence: next, now: state.now)
            }

            HStack(spacing: 6) {
                StatPill(symbol: "video.fill", text: "\(stats.meetingsLeft) meeting\(stats.meetingsLeft == 1 ? "" : "s")", tint: Theme.teal)
                StatPill(symbol: "checkmark.circle.fill", text: "\(stats.dueOpen) due", tint: Theme.orange)
                if stats.overdue > 0 {
                    StatPill(symbol: "exclamationmark.triangle.fill", text: "\(stats.overdue) overdue", tint: Theme.red)
                }
                if stats.demosThisWeek > 0 {
                    StatPill(symbol: "play.rectangle.fill", text: "\(stats.demosThisWeek) demo\(stats.demosThisWeek == 1 ? "" : "s") this week", tint: Theme.purple)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.violet.opacity(0.20), Theme.pink.opacity(0.09), Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

private struct StatPill: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

private struct NextUpCard: View {
    let occurrence: Occurrence
    let now: Date
    @Environment(AppState.self) private var state

    var body: some View {
        let item = occurrence.item
        let live = occurrence.isLive(at: now)
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.kind.tint.gradient)
                .frame(width: 3.5, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if live { PulseDot(color: Theme.green) }
                    Text(live ? "HAPPENING NOW" : "UP NEXT · \(Fmt.countdown(to: occurrence.start, from: now).uppercased())")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(live ? Theme.green : item.kind.tint)
                }
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text([Fmt.timeRange(occurrence.start, occurrence.end), item.person].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.joinURL != nil {
                PillButton(title: "Join", symbol: "video.fill", prominent: true) { state.join(item) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { state.select(.occurrence(item.id, occurrence.start)) }
    }
}
