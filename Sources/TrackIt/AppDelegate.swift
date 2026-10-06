import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = Store()
    private let settings = Settings()
    private lazy var state = AppState(store: store, settings: settings)

    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey!
    private var alerts: AlertCenter!
    private var reminders: Reminders!
    private var keyMonitor: Any?
    private var ticker: Timer?
    private var hideGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()

        hotKey = HotKey { [weak self] in self?.togglePanel() }
        hotKey.register(settings.hotKey)
        settings.onHotKeyChange = { [weak self] in
            guard let self else { return }
            self.hotKey.register(self.settings.hotKey)
        }
        settings.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        applyAppearance()

        alerts = AlertCenter(state: state)
        reminders = Reminders(state: state) { [weak self] occ, moment in self?.alerts.show(occ, moment) }
        alerts.onSnooze = { [weak self] occ in self?.reminders.snooze(occ) }
        alerts.onOpen = { [weak self] occ in
            guard let self else { return }
            self.state.tab = .today
            self.state.query = ""
            self.state.rawSelection = .occurrence(occ.item.id, occ.start)
            self.showPanel()
        }

        state.hidePanel = { [weak self] in self?.hidePanel() }
        state.previewAlert = { [weak self] in
            guard let self else { return }
            var sample = Item(kind: .meeting, title: "Design review with Acme")
            sample.due = Date().adding(minutes: 10)
            sample.hasTime = true
            sample.person = "Priya, Sam"
            sample.link = "https://meet.google.com/"
            self.alerts.show(Occurrence(item: sample, start: sample.due!), .soon(minutes: 10))
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()

        // Open right away on a manual launch, but stay quietly in the menu bar after login.
        if ProcessInfo.processInfo.systemUptime > 180 {
            showPanel()
        }

        #if DEBUG
        runSnapshotIfRequested()
        #endif
    }

    #if DEBUG
    /// Dev aid: TRACKIT_SNAPSHOT=/dir renders each tab of the panel to PNGs, then quits.
    private func runSnapshotIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["TRACKIT_SNAPSHOT"] else { return }
        showPanel()
        var steps: [(String, () -> Void)] = Tab.allCases.map { tab in
            ("\(tab.rawValue + 1)-\(tab.title.lowercased())", { [weak self] in self?.state.tab = tab })
        }
        steps.append(("7-quickadd", { [weak self] in
            self?.state.tab = .today
            self?.state.query = "demo: Acme walkthrough fri 3pm !high #sales"
        }))
        steps.append(("8-settings", { [weak self] in
            self?.state.query = ""
            self?.state.showSettings = true
        }))
        steps.append(("9-alert", { [weak self] in self?.state.previewAlert() }))
        func run(_ index: Int) {
            guard index < steps.count else { NSApp.terminate(nil); return }
            steps[index].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                let view: NSView? = steps[index].0 == "9-alert"
                    ? NSApp.windows.last { $0 !== self.panel && $0.isVisible && $0.level == .statusBar }?.contentView
                    : self.panel.contentView
                if let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent(steps[index].0 + ".png"))
                }
                run(index + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { run(0) }
    }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: Panel

    private func buildPanel() {
        let size = Theme.panelSize
        panel = FloatingPanel(size: size)
        panel.delegate = self
        panel.contentView = makeGlassContent(RootView().environment(state), size: size)
    }

    private func applyAppearance() {
        panel.appearance = settings.appearance.nsAppearance
    }

    func togglePanel() {
        if panel.isVisible && panel.isKeyWindow {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        hideGeneration += 1
        state.now = Date()

        if !panel.isVisible {
            if let screen = NSScreen.underMouse {
                let visible = screen.visibleFrame
                let size = panel.frame.size
                let x = visible.midX - size.width / 2
                let y = min(visible.maxY - size.height - 20, visible.minY + visible.height * 0.6 - size.height / 2)
                panel.setFrameOrigin(NSPoint(x: x.rounded(), y: max(visible.minY, y).rounded()))
            }
            panel.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        state.focusCommandField(selectAll: true)
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        state.showSettings = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        guard settings.hideOnBlur else { return }
        // Popovers (date pickers) inside the panel become key too; only hide when another app took focus.
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.keyWindow == nil, self.panel.isVisible else { return }
            self.hidePanel()
        }
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let inCommand = state.isCommandFocused

        if event.keyCode == 53, flags.isEmpty { // Esc
            state.escape()
            return nil
        }

        if flags == .command {
            if let n = Int(key), let tab = Tab(rawValue: n - 1) {
                withAnimation(.snappy(duration: 0.22)) { state.tab = tab }
                state.focusCommandField()
                return nil
            }
            switch key {
            case ",":
                withAnimation(.snappy(duration: 0.2)) { state.showSettings.toggle() }
                return nil
            case "n":
                state.newNote()
                return nil
            case "w":
                hidePanel()
                return nil
            case "f", "k", "l":
                state.focusCommandField(selectAll: true)
                return nil
            case "q":
                NSApp.terminate(nil)
                return nil
            default:
                break
            }

            if inCommand {
                switch event.keyCode {
                case 36, 76: // Return
                    state.editSelection()
                    return nil
                case 51 where state.query.isEmpty: // Delete
                    state.deleteSelection()
                    return nil
                default:
                    break
                }
                switch key {
                case "s": state.cycleStatus(); return nil
                case "p": state.cyclePriority(); return nil
                case "j": state.joinSelection(); return nil
                case "z" where state.query.isEmpty && store.canUndoDelete:
                    state.undoDelete()
                    return nil
                default: break
                }
            }

            // Standard editing shortcuts (there's no visible main menu to route them).
            let editing: [String: Selector] = [
                "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
                "z": Selector(("undo:")),
            ]
            if let action = editing[key], NSApp.sendAction(action, to: nil, from: nil) {
                return nil
            }
        }

        if flags == [.command, .shift], key == "z", NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) {
            return nil
        }
        return event
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "TrackIt")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open TrackIt  (\(settings.hotKey.label))", action: #selector(menuOpen), keyEquivalent: "")
            menu.addItem(withTitle: "New Note", action: #selector(menuNewNote), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: "")
            let login = menu.addItem(withTitle: "Launch at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
            login.state = settings.launchAtLogin ? .on : .off
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit TrackIt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    @objc private func menuOpen() { showPanel() }
    @objc private func menuNewNote() { showPanel(); state.newNote() }
    @objc private func menuSettings() { showPanel(); state.showSettings = true }
    @objc private func menuToggleLogin() { settings.launchAtLogin.toggle() }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        var title = ""
        if settings.menuBarCountdown, let next = state.nextUp() {
            let until = next.start.timeIntervalSince(state.now)
            if until <= 3600 {
                let name = next.item.title.count > 22 ? String(next.item.title.prefix(21)) + "…" : next.item.title
                let when = next.isLive(at: state.now) ? "now" : Fmt.countdown(to: next.start, from: state.now)
                    .replacingOccurrences(of: "in ", with: "")
                title = " \(name) · \(when)"
            }
        }
        if button.title != title { button.title = title }
    }

    private func tick() {
        state.now = Date()
        reminders.tick(now: state.now)
        updateStatusTitle()
    }
}
