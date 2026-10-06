import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            CommandBar()
            TabStrip()
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            Divider().opacity(0.5)

            Group {
                if state.showSettings {
                    SettingsView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    MainContent()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.5)
            FooterBar()
        }
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        .ignoresSafeArea()
        .tint(Theme.accent)
    }
}

private struct MainContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let sections = state.sections
        let selection = state.selection(in: sections)
        HStack(spacing: 0) {
            ListPane(sections: sections, selection: selection)
                .frame(width: state.tab == .notes ? 290 : 480)
            Divider().opacity(0.5)
            DetailPane(selection: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CommandBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let draft = state.draft
        let tint = draft.map(\.kind.tint) ?? Color.secondary

        HStack(spacing: 12) {
            Image(systemName: draft.map(\.kind.symbol) ?? "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))

            CommandField(text: $state.query, placeholder: state.tab.placeholder, state: state)
                .frame(height: 28)

            if let draft, !draft.isEmpty {
                HStack(spacing: 6) {
                    Text("New \(draft.kind.label)")
                        .font(.system(size: 11.5, weight: .semibold))
                    KeyCap("↵")
                }
                .foregroundStyle(tint)
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(0.14)))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .animation(.snappy(duration: 0.18), value: draft?.kind)
        .animation(.snappy(duration: 0.18), value: draft?.isEmpty)
    }
}

struct TabStrip: View {
    @Environment(AppState.self) private var state
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases) { tab in
                let selected = state.tab == tab
                Button {
                    withAnimation(.snappy(duration: 0.25)) { state.tab = tab }
                    state.focusCommandField()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(selected ? tab.tint : Color.secondary)
                        Text(tab.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        if let count = state.badge(for: tab) {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(tab == .today ? Theme.red : (selected ? tab.tint : Color.secondary))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill((tab == .today ? Theme.red : tab.tint).opacity(selected || tab == .today ? 0.18 : 0.08)))
                        }
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.primary.opacity(0.09))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07)))
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("⌘\(tab.rawValue + 1)")
            }
            Spacer()
        }
    }
}

struct FooterBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 14) {
            if let toast = state.toast {
                HStack(spacing: 7) {
                    Image(systemName: toast.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(toast.text)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    if toast.undo {
                        Button { state.undoDelete() } label: {
                            HStack(spacing: 4) {
                                Text("Undo").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent)
                                KeyCap("⌘Z")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 7) {
                    AppGlyph(size: 17)
                    Text("TrackIt")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    KeyCap(state.settings.hotKey.label)
                }
                .transition(.opacity)
            }

            Spacer()

            ForEach(state.footerHints) { hint in
                HStack(spacing: 5) {
                    Text(hint.label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    KeyCap(hint.key)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.primary.opacity(0.025))
    }
}
