import SwiftUI

/// The 28 pt provider logo tile used in the panel and in Settings.
struct ProviderLogoView: View {
    let brand: ProviderBrand

    var body: some View {
        logo
            .frame(width: 28, height: 28)
            .accessibilityLabel(brand.name)
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
}
