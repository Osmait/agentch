import SwiftUI

/// Turns subscriptions on and off in the panel.
struct SettingsView: View {
    let store: UsageStore

    var body: some View {
        Form {
            Section {
                ForEach(store.entries) { entry in
                    ProviderToggleRow(entry: entry,
                                      isOn: Binding(get: { store.isEnabled(entry.id) },
                                                    set: { store.setEnabled($0, for: entry.id) }))
                }
            } header: {
                Text("Subscriptions")
            } footer: {
                Text("Turned-off subscriptions are hidden from the notch and never queried. Tools that aren't installed or signed in are hidden automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
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
