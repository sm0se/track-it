import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    AppGlyph(size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Settings").font(.system(size: 17, weight: .bold))
                        Text("TrackIt 1.0").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PillButton(title: "Done", prominent: true) {
                        withAnimation(.snappy(duration: 0.2)) { state.showSettings = false }
                        state.focusCommandField()
                    }
                }

                group("General") {
                    row("Open TrackIt with", "Works from any app, any Space") {
                        Picker("", selection: $settings.hotKeyIndex) {
                            ForEach(HotKeyPreset.all.indices, id: \.self) { i in
                                Text(HotKeyPreset.all[i].label).tag(i)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    row("Appearance") {
                        Picker("", selection: $settings.appearance) {
                            ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    row("Hide when clicking elsewhere") {
                        Toggle("", isOn: $settings.hideOnBlur).toggleStyle(.switch).labelsHidden()
                    }
                    row("Launch at login", "Keeps the hotkey ready after a restart", last: true) {
                        Toggle("", isOn: $settings.launchAtLogin).toggleStyle(.switch).labelsHidden()
                    }
                }

                group("Meetings & alerts") {
                    row("Heads-up before meetings", "A card pops up top-right, plus one at start time") {
                        Picker("", selection: $settings.alertLeadMinutes) {
                            Text("Only at start").tag(0)
                            ForEach([2, 5, 10, 15, 30], id: \.self) { Text("\($0) min before").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    row("Also post macOS notifications") {
                        Toggle("", isOn: $settings.systemNotifications).toggleStyle(.switch).labelsHidden()
                    }
                    row("Countdown in menu bar", "Shows the next meeting within the hour") {
                        Toggle("", isOn: $settings.menuBarCountdown).toggleStyle(.switch).labelsHidden()
                    }
                    row("Preview an alert", last: true) {
                        PillButton(title: "Show", symbol: "bell.fill") { state.previewAlert() }
                    }
                }

                group("Data") {
                    row("Saved automatically to", state.store.fileURL.path, last: true) {
                        PillButton(title: "Reveal", symbol: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([state.store.fileURL])
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.05)))
        }
    }

    private func row<Control: View>(_ title: String, _ subtitle: String? = nil, last: Bool = false,
                                    @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                control()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if !last { Divider().opacity(0.5).padding(.leading, 14) }
        }
    }
}
