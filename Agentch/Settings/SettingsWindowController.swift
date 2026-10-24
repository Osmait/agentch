import AppKit
import SwiftUI

/// A regular window for Settings; the app itself has no Dock icon or menu bar.
@MainActor
final class SettingsWindowController {
    private let store: UsageStore
    private let appearance: AppearanceSettings
    private var window: NSWindow?

    init(store: UsageStore, appearance: AppearanceSettings) {
        self.store = store
        self.appearance = appearance
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, appearance: appearance)))
            window.title = "Agentch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
