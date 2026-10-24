import SwiftUI

struct ProviderRow: View {
    let brand: ProviderBrand
    let status: ProviderStatus
    let now: Date
    let isOpen: Bool
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            identity
                .frame(width: 122, alignment: .leading)

            VStack(spacing: 6) {
                switch status {
                case .loading:
                    message("Loading…")
                case .failed(let error):
                    message(error)
                case .loaded(let usage):
                    LimitBar(label: "5 hours",
                             window: usage.fiveHour?.current(at: now),
                             color: brand.primary,
                             now: now,
                             isOpen: isOpen,
                             delay: 0.18 + Double(index) * 0.07)
                    LimitBar(label: "Weekly",
                             window: usage.weekly?.current(at: now),
                             color: brand.secondary,
                             now: now,
                             isOpen: isOpen,
                             delay: 0.23 + Double(index) * 0.07)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.045))
                .strokeBorder(.white.opacity(0.07))
        }
    }

    private var identity: some View {
        HStack(spacing: 8) {
            logo
                .frame(width: 28, height: 28)
                .accessibilityLabel(brand.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(brand.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if case .loaded(let usage) = status, let plan = usage.plan {
                    Text(plan)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var logo: some View {
        switch brand.logo {
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(brand.logoColor)
                .frame(width: 28, height: 28)
                .background(brand.tileColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .appIcon(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }
}
