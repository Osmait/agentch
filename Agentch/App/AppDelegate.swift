import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private let usageStore = UsageStore(providers: [
        ClaudeUsageProvider(),
        CodexUsageProvider(),
        CursorUsageProvider(),
        AntigravityUsageProvider(pool: .gemini),
        AntigravityUsageProvider(pool: .thirdParty)
    ])

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        notchController = NotchWindowController(store: usageStore)
        notchController?.start()
        usageStore.startAutoRefresh()
    }
}
