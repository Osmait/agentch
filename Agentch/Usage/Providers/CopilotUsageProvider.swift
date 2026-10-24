import SwiftUI

/// Reads GitHub Copilot's monthly premium request quota. The token comes from the
/// Copilot editor extensions (`~/.config/github-copilot/apps.json`) or from any
/// account signed in to the GitHub CLI, whichever has a Copilot plan.
struct CopilotUsageProvider: UsageProvider {
    let id = "copilot"
    let brand = ProviderBrand(name: "Copilot",
                              logo: .asset("CopilotLogo"),
                              logoColor: .white,
                              tileColor: .white.opacity(0.1),
                              primary: Color(hex: 0x8B9CFF),
                              secondary: Color(hex: 0xC4CCFF))

    private static let userURL = URL(string: "https://api.github.com/copilot_internal/user")!

    func fetch() async throws -> ProviderUsage {
        if let token = await CopilotTokenCache.shared.token,
           let usage = try? await Self.request(token: token) {
            return usage
        }

        let candidates = Self.extensionTokens() + Self.githubCLITokens()
        guard !candidates.isEmpty else {
            throw UsageError.notConfigured("Sign in to Copilot in your editor or run gh auth login")
        }
        for token in candidates {
            if let usage = try? await Self.request(token: token) {
                await CopilotTokenCache.shared.set(token)
                return usage
            }
        }
        throw UsageError.notConfigured("No GitHub account with Copilot on this Mac")
    }

    /// Returns nil when this account has no Copilot quota.
    private static func request(token: String) async throws -> ProviderUsage? {
        var request = URLRequest(url: userURL)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let body = try JSONDecoder().decode(UserResponse.self, from: data)

        let resetsAt = body.quotaResetDate.flatMap(resetFormatter.date)
        var windows: [UsageWindow] = []
        if let premium = body.quotaSnapshots?.premiumInteractions?.window("Premium", resetsAt: resetsAt) {
            windows.append(premium)
        }
        if let chat = body.quotaSnapshots?.chat?.window("Chat", resetsAt: resetsAt) {
            windows.append(chat)
        }
        // Accounts without Copilot still answer 200, just with empty quotas.
        guard !windows.isEmpty else { return nil }
        return ProviderUsage(plan: body.copilotPlan.map { $0.prefix(1).uppercased() + $0.dropFirst() },
                             windows: windows)
    }

    /// "2026-11-01": quotas reset at midnight UTC.
    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Tokens

    private static func extensionTokens() -> [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/github-copilot/apps.json")
        guard let data = try? Data(contentsOf: url),
              let apps = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [] }
        return apps.filter { $0.key.hasPrefix("github.com:") }
            .compactMap { $0.value["oauth_token"] as? String }
    }

    /// One token per account signed in to `gh`, active account first.
    private static func githubCLITokens() -> [String] {
        guard let gh = CLILocator.find("gh"),
              let status = run(gh, ["auth", "status", "--hostname", "github.com", "--json", "hosts"]),
              let json = try? JSONSerialization.jsonObject(with: status) as? [String: Any],
              let accounts = (json["hosts"] as? [String: Any])?["github.com"] as? [[String: Any]]
        else { return [] }

        return accounts
            .sorted { ($0["active"] as? Bool ?? false) && !($1["active"] as? Bool ?? false) }
            .compactMap { $0["login"] as? String }
            .compactMap { login in
                run(gh, ["auth", "token", "--hostname", "github.com", "--user", login])
                    .flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 }
            }
    }

    private static func run(_ executable: URL, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // A token in the environment would shadow the accounts gh keeps in the Keychain.
        var environment = ProcessInfo.processInfo.environment
        environment["GITHUB_TOKEN"] = nil
        environment["GH_TOKEN"] = nil
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    // MARK: - API response

    private struct UserResponse: Decodable {
        struct Snapshots: Decodable {
            let premiumInteractions: Quota?
            let chat: Quota?

            enum CodingKeys: String, CodingKey {
                case premiumInteractions = "premium_interactions"
                case chat
            }
        }

        struct Quota: Decodable {
            let entitlement: Double?
            let remaining: Double?
            let percentRemaining: Double?
            let unlimited: Bool?

            enum CodingKeys: String, CodingKey {
                case entitlement, remaining, unlimited
                case percentRemaining = "percent_remaining"
            }

            /// Unlimited or empty quotas are not limits worth a bar.
            func window(_ label: String, resetsAt: Date?) -> UsageWindow? {
                guard unlimited != true, let entitlement, entitlement > 0 else { return nil }
                let remainingPercent = percentRemaining ?? (remaining ?? entitlement) / entitlement * 100
                let used = max(0, entitlement - (remaining ?? entitlement))
                return UsageWindow(label: label,
                                   usedPercent: 100 - remainingPercent,
                                   resetsAt: resetsAt,
                                   detail: "\(Int(used)) of \(Int(entitlement))")
            }
        }

        let copilotPlan: String?
        let quotaResetDate: String?
        let quotaSnapshots: Snapshots?

        enum CodingKeys: String, CodingKey {
            case copilotPlan = "copilot_plan"
            case quotaResetDate = "quota_reset_date"
            case quotaSnapshots = "quota_snapshots"
        }
    }
}

/// Remembers which token has Copilot so later refreshes skip the others.
private actor CopilotTokenCache {
    static let shared = CopilotTokenCache()
    private(set) var token: String?
    func set(_ token: String) { self.token = token }
}
