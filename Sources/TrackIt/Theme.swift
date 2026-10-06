import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    static let violet = Color(hex: 0x7C5CFF)
    static let pink = Color(hex: 0xFF4FA3)
    static let accent = Color(hex: 0x8B6CFF)
    static let accentGradient = LinearGradient(colors: [violet, pink], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let blue = Color(hex: 0x4C9BFF)
    static let teal = Color(hex: 0x1FCFA0)
    static let purple = Color(hex: 0xB76BFF)
    static let orange = Color(hex: 0xFF9A3C)
    static let yellow = Color(hex: 0xFFC53D)
    static let red = Color(hex: 0xFF5A6A)
    static let green = Color(hex: 0x34D399)

    static let panelSize = NSSize(width: 900, height: 600)
}

extension ItemKind {
    var tint: Color {
        switch self {
        case .task: Theme.blue
        case .meeting: Theme.teal
        case .demo: Theme.purple
        case .deliverable: Theme.orange
        }
    }
}

extension DraftKind {
    var tint: Color {
        switch self {
        case let .item(kind): kind.tint
        case .note: Theme.yellow
        }
    }
}

extension Status {
    var tint: Color {
        switch self {
        case .todo: .secondary
        case .inProgress: Theme.blue
        case .review: Theme.purple
        case .blocked: Theme.red
        case .done: Theme.green
        }
    }
}

extension Priority {
    var tint: Color {
        switch self {
        case .none: .secondary
        case .low: Theme.blue
        case .medium: Theme.orange
        case .high: Theme.red
        }
    }
}
