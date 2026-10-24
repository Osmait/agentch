import SwiftUI

/// Asks the Codex CLI for the account's live limits through `codex app-server`
/// (JSON-RPC `account/rateLimits/read`). Works no matter where Codex is used
/// (CLI, IDE or the ChatGPT app) because it queries the account, not local logs.
struct CodexUsageProvider: UsageProvider {
    let id = "codex"
    let brand = ProviderBrand(name: "Codex",
                              logo: .asset("OpenAILogo"),
                              logoColor: .white,
                              tileColor: .white.opacity(0.1),
                              primary: Color(hex: 0xE4E4E7),
                              secondary: .white)

    private static let fiveHourMinutes = 300
    private static let weeklyMinutes = 10_080

    func fetch() async throws -> ProviderUsage {
        guard let codex = CLILocator.find("codex") else {
            throw UsageError("Codex CLI not found")
        }

        let server = JSONLineProcess(executable: codex, arguments: ["app-server"])
        try server.start()
        try server.send(["id": 1, "method": "initialize",
                         "params": ["clientInfo": ["name": "agentch", "version": "0.1"]]])

        return try await server.read(timeout: 20) { message in
            switch message["id"] as? Int {
            case 1:
                try server.send(["method": "initialized"])
                try server.send(["id": 2, "method": "account/rateLimits/read"])
                return nil
            case 2:
                if let error = message["error"] as? [String: Any] {
                    throw UsageError((error["message"] as? String) ?? "Codex returned an error")
                }
                guard let result = message["result"] as? [String: Any],
                      let limits = result["rateLimits"] as? [String: Any] else {
                    throw UsageError("Unexpected response from Codex")
                }
                return Self.parse(limits)
            default:
                return nil
            }
        }
    }

    private static func parse(_ limits: [String: Any]) -> ProviderUsage {
        var usage = ProviderUsage(plan: (limits["planType"] as? String).map(Self.planName))
        for key in ["primary", "secondary"] {
            guard let raw = limits[key] as? [String: Any] else { continue }
            let window = UsageWindow(
                usedPercent: (raw["usedPercent"] as? NSNumber)?.doubleValue ?? 0,
                resetsAt: (raw["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            )
            switch raw["windowDurationMins"] as? Int {
            case fiveHourMinutes: usage.fiveHour = window
            case weeklyMinutes: usage.weekly = window
            default: if key == "primary" { usage.fiveHour = window } else { usage.weekly = window }
            }
        }
        return usage
    }

    private static func planName(_ raw: String) -> String {
        raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
