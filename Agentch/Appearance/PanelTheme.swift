import SwiftUI

/// A look for the expanded panel: the tint laid over the background blur and
/// whether text and controls are drawn light or dark.
struct PanelTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let tint: Color
    let colorScheme: ColorScheme

    static let midnight = PanelTheme(id: "midnight", name: "Midnight", tint: .black, colorScheme: .dark)

    static let all: [PanelTheme] = [
        midnight,
        PanelTheme(id: "graphite", name: "Graphite", tint: Color(hex: 0x2A2A2E), colorScheme: .dark),
        PanelTheme(id: "ocean", name: "Ocean", tint: Color(hex: 0x0A2342), colorScheme: .dark),
        PanelTheme(id: "aurora", name: "Aurora", tint: Color(hex: 0x24104A), colorScheme: .dark),
        PanelTheme(id: "forest", name: "Forest", tint: Color(hex: 0x0C2B1E), colorScheme: .dark),
        PanelTheme(id: "daylight", name: "Daylight", tint: Color(hex: 0xF5F5F7), colorScheme: .light),
    ]
}

/// Theme and opacity chosen in Settings, applied live to the panel.
@MainActor
@Observable
final class AppearanceSettings {
    static let opacityRange: ClosedRange<Double> = 0.15...1
    static let defaultOpacity = 0.74

    var themeID: String {
        didSet { UserDefaults.standard.set(themeID, forKey: Self.themeKey) }
    }

    /// Opacity of the theme tint over the blur when the panel is open.
    var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Self.opacityKey) }
    }

    /// Blur what's behind the panel. Off, low opacities make it see-through.
    var blur: Bool {
        didSet { UserDefaults.standard.set(blur, forKey: Self.blurKey) }
    }

    var theme: PanelTheme {
        PanelTheme.all.first { $0.id == themeID } ?? .midnight
    }

    private static let themeKey = "panelTheme"
    private static let opacityKey = "panelOpacity"
    private static let blurKey = "panelBlur"

    init() {
        let defaults = UserDefaults.standard
        themeID = defaults.string(forKey: Self.themeKey) ?? PanelTheme.midnight.id
        let stored = defaults.object(forKey: Self.opacityKey) as? Double ?? Self.defaultOpacity
        opacity = min(max(stored, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        blur = defaults.object(forKey: Self.blurKey) as? Bool ?? true
    }
}
