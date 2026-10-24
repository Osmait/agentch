import AppKit
import SwiftUI

/// Blurs whatever is behind the window (the desktop and other apps).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var colorScheme: ColorScheme = .dark

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appearance
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = appearance
    }

    private var appearance: NSAppearance? {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
