import SwiftUI

/// Expanded content: one row per subscription.
struct LimitsView: View {
    let store: UsageStore
    let isOpen: Bool
    let topInset: CGFloat
    let openSettings: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Subscriptions")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let updated = store.lastUpdated {
                        Text(LimitFormatting.time(updated))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    SettingsButton(action: openSettings)
                }
                .padding(.horizontal, 6)

                ForEach(Array(store.visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    ProviderRow(brand: entry.provider.brand,
                                status: entry.status,
                                now: context.date,
                                isOpen: isOpen,
                                index: index)
                }
            }
            .padding(.top, topInset + 6)
            .padding([.horizontal, .bottom], 12)
        }
        .foregroundStyle(.primary)
    }
}

/// Small gear in the header that opens Settings.
private struct SettingsButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(isHovered ? 0.12 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}
