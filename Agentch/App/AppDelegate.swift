import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private lazy var settingsController = SettingsWindowController(store: usageStore)
    private let usageStore = UsageStore(providers: [
        ClaudeUsageProvider(),
        CodexUsageProvider(),
        CursorUsageProvider(),
        CopilotUsageProvider(),
        GrokUsageProvider(),
        MuseUsageProvider(),
        AntigravityUsageProvider(pool: .gemini),
        AntigravityUsageProvider(pool: .thirdParty)
    ])

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        notchController = NotchWindowController(store: usageStore) { [weak self] in
            self?.settingsController.show()
        }
        notchController?.start()
        usageStore.startAutoRefresh()
        // Debug aid: launch with `--args -showSettings YES` to open Settings right away.
        if UserDefaults.standard.bool(forKey: "showSettings") { settingsController.show() }
    }
}
