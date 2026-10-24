import SwiftUI

/// A limit shown as one bar, such as the 5 hour session, the weekly limit or a monthly budget.
struct UsageWindow: Equatable {
    var label: String
    /// 0...100
    var usedPercent: Double
    var resetsAt: Date?
    /// Shown instead of the time remaining, e.g. "$3.20 of $50".
    var detail: String? = nil

    /// Once the reset time has passed the window is empty again,
    /// even if the source has not been refreshed yet.
    func current(at now: Date) -> UsageWindow {
        guard let resetsAt, resetsAt <= now else { return self }
        return UsageWindow(label: label, usedPercent: 0, resetsAt: nil)
    }
}

extension UsageWindow {
    static let fiveHourLabel = "5 hours"
    static let weeklyLabel = "Weekly"
}

struct ProviderUsage: Equatable {
    var plan: String?
    /// In display order; the first bar uses the brand's primary color.
    var windows: [UsageWindow] = []
}

enum ProviderLogo {
    /// Monochrome vector logo from the asset catalog, tinted with `logoColor`.
    case asset(String)
    /// The icon of an installed app, shown as is.
    case appIcon(String)
    /// A letter on the tile, for brands without a usable vector logo.
    case monogram(String)
}

/// Visual identity of a provider in the panel.
struct ProviderBrand {
    let name: String
    let logo: ProviderLogo
    let logoColor: Color
    let tileColor: Color
    /// Bar colors for the first window and the ones after it.
    let primary: Color
    let secondary: Color
}

enum ProviderStatus: Equatable {
    case loading
    case loaded(ProviderUsage)
    case failed(String)
    /// The tool is not installed or signed in on this Mac; the row is hidden.
    case notConfigured(String)

    var isNotConfigured: Bool {
        if case .notConfigured = self { return true }
        return false
    }
}

protocol UsageProvider: Sendable {
    var id: String { get }
    var brand: ProviderBrand { get }
    /// Name in Settings, where providers sharing a brand need telling apart.
    var title: String { get }
    func fetch() async throws -> ProviderUsage
}

extension UsageProvider {
    var title: String { brand.name }
}

struct UsageError: LocalizedError {
    let message: String
    /// True when the user simply doesn't use this tool, as opposed to a broken session.
    let isNotConfigured: Bool

    init(_ message: String) {
        self.message = message
        isNotConfigured = false
    }

    private init(message: String, isNotConfigured: Bool) {
        self.message = message
        self.isNotConfigured = isNotConfigured
    }

    /// Missing CLI or login: hides the provider instead of showing an error.
    static func notConfigured(_ message: String) -> UsageError {
        UsageError(message: message, isNotConfigured: true)
    }

    var errorDescription: String? { message }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
