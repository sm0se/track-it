import Carbon.HIToolbox
import Foundation

struct HotKeyPreset {
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotKeyPreset] = [
        HotKeyPreset(label: "⌥ T", keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey)),
        HotKeyPreset(label: "⌥ ⇧ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey)),
        HotKeyPreset(label: "⌃ ⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(label: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        HotKeyPreset(label: "⌃ ⌥ T", keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(label: "⌥ `", keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(optionKey)),
    ]
}

/// A single system-wide hotkey registered through Carbon.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.onPress() }
            return noErr
        }, 1, &spec, me, &handlerRef)
    }

    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x5452_4B54), id: 1) // 'TRKT'
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
