import SwiftUI

struct SettingsView: View {
    let store: UsageStore
    let appearance: AppearanceSettings

    var body: some View {
        TabView {
            AppearanceTab(appearance: appearance)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            SubscriptionsTab(store: store)
                .tabItem { Label("Subscriptions", systemImage: "list.bullet") }
        }
        .frame(width: 540, height: 700)
    }
}

// MARK: - Subscriptions

/// Turns subscriptions on and off in the panel.
private struct SubscriptionsTab: View {
    let store: UsageStore

    var body: some View {
        Form {
            Section {
                ForEach(store.entries) { entry in
                    ProviderToggleRow(entry: entry,
                                      isOn: Binding(get: { store.isEnabled(entry.id) },
                                                    set: { store.setEnabled($0, for: entry.id) }))
                }
            } footer: {
                Text("Turned-off subscriptions are hidden from the notch and never queried. Tools that aren't installed or signed in are hidden automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderToggleRow: View {
    let entry: UsageStore.Entry
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                ProviderLogoView(brand: entry.provider.brand)
                    .opacity(isOn ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.provider.title)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.switch)
    }

    private var status: String {
        guard isOn else { return "Off" }
        switch entry.status {
        case .loading: return "Checking…"
        case .loaded(let usage): return usage.plan.map { "Connected · \($0)" } ?? "Connected"
        case .failed(let message): return message
        case .notConfigured(let message): return "Not set up · \(message)"
        }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @Bindable var appearance: AppearanceSettings

    var body: some View {
        Form {
            Section("Preview") {
                ThemePreview(theme: appearance.theme, opacity: appearance.opacity, blur: appearance.blur)
                    .listRowInsets(EdgeInsets())
            }

            Section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(PanelTheme.all) { theme in
                        ThemeSwatch(theme: theme, isSelected: theme.id == appearance.themeID) {
                            appearance.themeID = theme.id
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Blur background", isOn: $appearance.blur)
                LabeledContent("Opacity") {
                    HStack(spacing: 12) {
                        Slider(value: $appearance.opacity, in: AppearanceSettings.opacityRange)
                            .labelsHidden()
                        Text("\(Int((appearance.opacity * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Transparency")
            } footer: {
                HStack {
                    Text("Lower opacity shows more of the desktop. Turn blur off for a clear, glass-like panel.")
                    Spacer()
                    Button("Reset") {
                        appearance.opacity = AppearanceSettings.defaultOpacity
                        appearance.blur = true
                    }
                    .controlSize(.small)
                    .disabled(appearance.opacity == AppearanceSettings.defaultOpacity && appearance.blur)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Colorful stand-in for the desktop, so translucency is visible in the preview.
private struct PreviewBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x54398C), Color(hex: 0x1A2E66), Color(hex: 0x0A0F24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.pink.opacity(0.55)).frame(width: 140).blur(radius: 30).offset(x: -120, y: 10)
            Circle().fill(Color.teal.opacity(0.55)).frame(width: 160).blur(radius: 30).offset(x: 130, y: 30)
            Circle().fill(Color.orange.opacity(0.5)).frame(width: 110).blur(radius: 30).offset(x: 20, y: -50)
        }
    }
}

private struct ThemePreview: View {
    let theme: PanelTheme
    let opacity: Double
    let blur: Bool

    private static let sample = ProviderUsage(plan: "Max", windows: [
        UsageWindow(label: UsageWindow.fiveHourLabel, usedPercent: 42, resetsAt: .now.addingTimeInterval(2 * 3600 + 18 * 60)),
        UsageWindow(label: UsageWindow.weeklyLabel, usedPercent: 84, resetsAt: .now.addingTimeInterval(3 * 86_400)),
    ])

    var body: some View {
        ProviderRow(brand: ClaudeUsageProvider().brand,
                    status: .loaded(Self.sample),
                    now: .now,
                    isOpen: true,
                    index: 0)
            .padding(12)
            .background {
                ZStack {
                    if blur { VisualEffectView(colorScheme: theme.colorScheme) }
                    theme.tint.opacity(opacity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(PreviewBackdrop())
            .clipped()
            .environment(\.colorScheme, theme.colorScheme)
            .foregroundStyle(.primary)
    }
}

private struct ThemeSwatch: View {
    let theme: PanelTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // The backdrop sits in a background so its blobs never widen the cell.
                theme.tint.opacity(0.82)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(Color.primary.opacity(0.85)).frame(width: 34, height: 4)
                            Capsule().fill(Color.primary.opacity(0.35)).frame(width: 52, height: 4)
                        }
                        .padding(8)
                        .environment(\.colorScheme, theme.colorScheme)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(PreviewBackdrop())
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: isSelected ? 2.5 : 1)
                }

                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
