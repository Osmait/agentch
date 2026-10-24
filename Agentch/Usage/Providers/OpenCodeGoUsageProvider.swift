import SwiftUI

/// Reads OpenCode Go's rolling 5 hour, weekly and monthly limits, authenticating
/// with the API key `opencode auth login` stores for the "opencode-go" provider.
struct OpenCodeGoUsageProvider: UsageProvider {
    let id = "opencode-go"
    let brand = ProviderBrand(name: "OpenCode Go",
                              logo: .asset("OpenCodeLogo"),
                              logoColor: .primary,
                              tileColor: .primary.opacity(0.1),
                              primary: Color(hex: 0x34D399),
                              secondary: Color(hex: 0x6EE7B7))

    private static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    func fetch() async throws -> ProviderUsage {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(try Self.loadKey())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError("API key rejected: run opencode auth login")
        case let status: throw UsageError("OpenCode responded \(status)")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any]
        else { throw UsageError("No OpenCode Go subscription on this key") }

        let now = Date()
        let windows = [
            Self.window(usage["rolling"], label: UsageWindow.fiveHourLabel, now: now),
            Self.window(usage["weekly"], label: UsageWindow.weeklyLabel, now: now),
            Self.window(usage["monthly"], label: "Monthly", now: now),
        ]
        return ProviderUsage(plan: "Go", windows: windows.compactMap { $0 })
    }

    /// Windows look like `{"percent": 3, "resetInSec": 18100}`; some responses
    /// give an ISO `resetsAt` instead of the seconds left.
    private static func window(_ raw: Any?, label: String, now: Date) -> UsageWindow? {
        guard let raw = raw as? [String: Any] else { return nil }
        let percent = ["percent", "usagePercent", "usedPercent"].lazy
            .compactMap { (raw[$0] as? NSNumber)?.doubleValue }.first
        guard let percent else { return nil }

        let resetsAt = (raw["resetInSec"] as? NSNumber).map { now.addingTimeInterval($0.doubleValue) }
            ?? ["resetsAt", "resetAt"].lazy.compactMap { (raw[$0] as? String).flatMap(ISO8601.parse) }.first
        return UsageWindow(label: label, usedPercent: min(max(percent, 0), 100), resetsAt: resetsAt)
    }

    private static func loadKey() throws -> String {
        let dataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        let url = dataHome.appendingPathComponent("opencode/auth.json")
        guard let data = try? Data(contentsOf: url),
              let providers = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = providers["opencode-go"] as? [String: Any],
              let key = (entry["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { throw UsageError.notConfigured("Run opencode auth login and pick OpenCode Go") }
        return key
    }
}
