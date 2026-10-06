import Foundation

enum AlertMoment {
    case soon(minutes: Int)
    case now
}

/// Watches upcoming meetings and timed demos and fires heads-up alerts before they start.
final class Reminders {
    private let state: AppState
    private let onAlert: (Occurrence, AlertMoment) -> Void
    private var fired = Set<String>()

    init(state: AppState, onAlert: @escaping (Occurrence, AlertMoment) -> Void) {
        self.state = state
        self.onAlert = onAlert
    }

    func tick(now: Date) {
        let lead = state.settings.alertLeadMinutes
        let window = state.occurrences(
            from: now.addingTimeInterval(-120),
            to: now.addingTimeInterval(TimeInterval(max(lead, 1) * 60 + 60)),
            kinds: [.meeting, .demo]
        )
        for occ in window where occ.item.hasTime {
            let leadKey = occ.id + "#lead"
            let startKey = occ.id + "#start"
            let untilStart = occ.start.timeIntervalSince(now)

            if untilStart <= 60, untilStart > -120, !fired.contains(startKey) {
                fired.insert(startKey)
                fired.insert(leadKey)
                onAlert(occ, .now)
            } else if lead > 0, untilStart <= TimeInterval(lead * 60), untilStart > 60, !fired.contains(leadKey) {
                fired.insert(leadKey)
                onAlert(occ, .soon(minutes: Int((untilStart / 60).rounded(.up))))
            }
        }
        if fired.count > 500 { fired.removeAll() }
    }

    func snooze(_ occ: Occurrence, minutes: Int = 5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60)) { [weak self] in
            guard let self, let item = self.state.store.item(occ.item.id) else { return }
            self.onAlert(Occurrence(item: item, start: occ.start), .now)
        }
    }
}
