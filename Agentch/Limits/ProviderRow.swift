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
                case .loading, .notConfigured:
                    message("Loading…")
                case .failed(let error):
                    message(error)
                case .loaded(let usage) where usage.windows.isEmpty:
                    message("No limits reported")
                case .loaded(let usage):
                    ForEach(Array(usage.windows.enumerated()), id: \.offset) { position, window in
                        LimitBar(window: window.current(at: now),
                                 color: position == 0 ? brand.primary : brand.secondary,
                                 now: now,
                                 isOpen: isOpen,
                                 delay: 0.18 + Double(position) * 0.05 + Double(index) * 0.07)
                    }
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
        case .monogram(let letter):
            Text(letter)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(brand.logoColor)
                .frame(width: 28, height: 28)
                .background(brand.tileColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }
}
