import AppKit
import SwiftUI

/// A regular window for Settings; the app itself has no Dock icon or menu bar.
@MainActor
final class SettingsWindowController {
    private let store: UsageStore
    private var window: NSWindow?

    init(store: UsageStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
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
