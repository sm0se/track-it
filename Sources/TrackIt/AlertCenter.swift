import AppKit
import SwiftUI
import UserNotifications

/// Shows stacked heads-up cards in the top-right corner of the screen (on every Space),
/// and mirrors them to Notification Center when enabled.
final class AlertCenter {
    private final class AlertPanel: NSPanel {
        init(size: NSSize) {
            super.init(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(button)?.isHidden = true
            }
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            hidesOnDeactivate = false
            isReleasedWhenClosed = false
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            animationBehavior = .none
        }

        override var canBecomeKey: Bool { false }
    }

    private let state: AppState
    private var panels: [NSPanel] = []
    var onSnooze: (Occurrence) -> Void = { _ in }
    var onOpen: (Occurrence) -> Void = { _ in }

    private static let size = NSSize(width: 360, height: 118)

    init(state: AppState) {
        self.state = state
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func show(_ occ: Occurrence, _ moment: AlertMoment) {
        NSSound(named: "Glass")?.play()

        let panel = AlertPanel(size: Self.size)
        let card = AlertCard(
            occurrence: occ,
            moment: moment,
            onJoin: { [weak self, weak panel] in
                if let url = occ.item.joinURL { NSWorkspace.shared.open(url) }
                if let panel { self?.dismiss(panel) }
            },
            onSnooze: { [weak self, weak panel] in
                self?.onSnooze(occ)
                if let panel { self?.dismiss(panel) }
            },
            onOpen: { [weak self, weak panel] in
                self?.onOpen(occ)
                if let panel { self?.dismiss(panel) }
            },
            onDismiss: { [weak self, weak panel] in
                if let panel { self?.dismiss(panel) }
            }
        )
        panel.contentView = makeGlassContent(card, size: Self.size)
        panel.appearance = state.settings.appearance.nsAppearance

        guard let screen = NSScreen.main else { return }
        let target = frame(at: panels.count, on: screen)
        panel.setFrame(target.offsetBy(dx: 40, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panels.append(panel)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }

        let lifetime: TimeInterval = if case .now = moment { 300 } else { 120 }
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak self, weak panel] in
            if let panel { self?.dismiss(panel) }
        }

        if state.settings.systemNotifications { postSystemNotification(occ, moment) }
    }

    private func frame(at index: Int, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let y = visible.maxY - 14 - Self.size.height - CGFloat(index) * (Self.size.height + 10)
        return NSRect(x: visible.maxX - Self.size.width - 14, y: y, width: Self.size.width, height: Self.size.height)
    }

    private func dismiss(_ panel: NSPanel) {
        guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: index)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
        restack()
    }

    private func restack() {
        guard let screen = NSScreen.main else { return }
        for (i, panel) in panels.enumerated() {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                panel.animator().setFrame(frame(at: i, on: screen), display: true)
            }
        }
    }

    private func postSystemNotification(_ occ: Occurrence, _ moment: AlertMoment) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = occ.item.title
        let when = Fmt.timeRange(occ.start, occ.end)
        content.body = switch moment {
        case let .soon(minutes): "\(occ.item.kind.label) in \(minutes) min · \(when)"
        case .now: "\(occ.item.kind.label) starting now · \(when)"
        }
        let request = UNNotificationRequest(identifier: occ.id + "\(moment)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct AlertCard: View {
    let occurrence: Occurrence
    let moment: AlertMoment
    let onJoin: () -> Void
    let onSnooze: () -> Void
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var item: Item { occurrence.item }

    private var headline: String {
        switch moment {
        case let .soon(minutes): "IN \(minutes) MIN"
        case .now: "STARTING NOW"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle().fill(item.kind.tint.gradient)
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(headline)
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(item.kind.tint)
                        if case .now = moment {
                            PulseDot(color: item.kind.tint)
                        }
                    }
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text([Fmt.timeRange(occurrence.start, occurrence.end), item.person]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                if item.joinURL != nil {
                    PillButton(title: "Join", symbol: "video.fill", prominent: true, action: onJoin)
                }
                PillButton(title: "Snooze 5m", symbol: "moon.zzz.fill", action: onSnooze)
                PillButton(title: "Open", symbol: "arrow.up.forward.app", action: onOpen)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
