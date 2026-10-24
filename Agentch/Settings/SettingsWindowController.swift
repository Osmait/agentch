import AppKit
import SwiftUI

/// A regular Settings window with toolbar tabs, like the system's own settings
/// windows; the app itself has no Dock icon or menu bar.
@MainActor
final class SettingsWindowController {
    private let store: UsageStore
    private let appearance: AppearanceSettings
    private var window: NSWindow?

    private static let width: CGFloat = 540

    init(store: UsageStore, appearance: AppearanceSettings) {
        self.store = store
        self.appearance = appearance
    }

    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(Self.tab("Appearance", symbol: "paintpalette", height: 640,
                                         AppearanceTab(appearance: appearance)))
            tabs.addTabViewItem(Self.tab("Subscriptions", symbol: "switch.2", height: 530,
                                         SubscriptionsTab(store: store)))

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func tab(_ label: String, symbol: String, height: CGFloat, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.frame(width: width, height: height))
        // Each tab reports its size so the window resizes when switching.
        controller.sizingOptions = .preferredContentSize
        // The tab controller shows the selected tab's title in the window title bar.
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
