import AppKit
import SwiftUI

/// The big search/quick-add field. Implemented with AppKit so arrow keys, Return and Tab
/// can drive the list while the cursor stays in the field (Raycast-style).
struct CommandField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 19, weight: .regular)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.placeholderAttributedString = placeholderString
        state.commandField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderAttributedString?.string != placeholder {
            field.placeholderAttributedString = placeholderString
        }
    }

    private var placeholderString: NSAttributedString {
        NSAttributedString(string: placeholder, attributes: [
            .font: NSFont.systemFont(ofSize: 19, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandField

        init(_ parent: CommandField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let state = parent.state
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                state.move(-1)
            case #selector(NSResponder.moveDown(_:)):
                state.move(1)
            case #selector(NSResponder.insertNewline(_:)):
                state.primary()
            case #selector(NSResponder.insertTab(_:)):
                state.cycleTab(1)
            case #selector(NSResponder.insertBacktab(_:)):
                state.cycleTab(-1)
            case #selector(NSResponder.cancelOperation(_:)):
                state.escape()
            default:
                return false
            }
            return true
        }
    }
}
