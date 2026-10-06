import AppKit
import Observation
import ServiceManagement

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

@Observable
final class Settings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored var onHotKeyChange: (() -> Void)?
    @ObservationIgnored var onAppearanceChange: (() -> Void)?

    var hotKeyIndex: Int {
        didSet {
            defaults.set(hotKeyIndex, forKey: "hotKeyIndex")
            onHotKeyChange?()
        }
    }

    var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            onAppearanceChange?()
        }
    }

    var hideOnBlur: Bool { didSet { defaults.set(hideOnBlur, forKey: "hideOnBlur") } }
    var alertLeadMinutes: Int { didSet { defaults.set(alertLeadMinutes, forKey: "alertLeadMinutes") } }
    var systemNotifications: Bool { didSet { defaults.set(systemNotifications, forKey: "systemNotifications") } }
    var menuBarCountdown: Bool { didSet { defaults.set(menuBarCountdown, forKey: "menuBarCountdown") } }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("TrackIt: launch-at-login change failed: \(error)")
            }
        }
    }

    var hotKey: HotKeyPreset {
        HotKeyPreset.all.indices.contains(hotKeyIndex) ? HotKeyPreset.all[hotKeyIndex] : HotKeyPreset.all[0]
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "hotKeyIndex": 0,
            "appearance": AppearanceMode.system.rawValue,
            "hideOnBlur": true,
            "alertLeadMinutes": 10,
            "systemNotifications": true,
            "menuBarCountdown": true,
        ])
        hotKeyIndex = d.integer(forKey: "hotKeyIndex")
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        hideOnBlur = d.bool(forKey: "hideOnBlur")
        alertLeadMinutes = d.integer(forKey: "alertLeadMinutes")
        systemNotifications = d.bool(forKey: "systemNotifications")
        menuBarCountdown = d.bool(forKey: "menuBarCountdown")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
