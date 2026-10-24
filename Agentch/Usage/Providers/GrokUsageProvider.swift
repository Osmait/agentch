import SwiftUI

/// Reads Grok's credit usage for the current billing period. Goes through
/// `grok agent stdio` when the CLI is installed, so the CLI refreshes its own login;
/// otherwise calls the billing endpoint with the token in `~/.grok/auth.json`.
struct GrokUsageProvider: UsageProvider {
    let id = "grok"
    let brand = ProviderBrand(name: "Grok",
                              logo: .monogram("G"),
                              logoColor: .primary,
                              tileColor: .primary.opacity(0.1),
                              primary: .primary.opacity(0.9),
                              secondary: .primary.opacity(0.55))

    private static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    func fetch() async throws -> ProviderUsage {
        guard let grok = CLILocator.find("grok") else { return try await Self.fetchOverHTTP() }
        do {
            return try await Self.fetchThroughCLI(grok)
        } catch let error as UsageError where error.isNotConfigured {
            throw error
        } catch let cliError {
            // The CLI refuses billing for some accounts (e.g. Legacy privacy mode) that
            // the billing endpoint still answers; keep the CLI's reason if both fail.
            do { return try await Self.fetchOverHTTP() } catch { throw cliError }
        }
    }

    private static func fetchThroughCLI(_ grok: URL) async throws -> ProviderUsage {
        guard FileManager.default.fileExists(atPath: authFile.path) else {
            throw UsageError.notConfigured("Sign in by running grok login")
        }
        let agent = JSONLineProcess(executable: grok, arguments: ["agent", "stdio"])
        try agent.start()
        try agent.send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                        "params": ["protocolVersion": "1",
                                   "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false],
                                                          "terminal": false]]])

        return try await agent.read(timeout: 20) { message in
            switch message["id"] as? Int {
            case 1:
                try agent.send(["jsonrpc": "2.0", "id": 2, "method": "_x.ai/billing", "params": [String: Any]()])
                return nil
            case 2:
                if let error = message["error"] as? [String: Any] {
                    // `data` carries the real reason; `message` is often just "Internal error".
                    let reason = (error["data"] as? String)?
                        .components(separatedBy: " [").first?
                        .replacingOccurrences(of: "Billing service error: ", with: "")
                    throw UsageError(reason ?? (error["message"] as? String) ?? "Grok returned an error")
                }
                guard let result = message["result"] as? [String: Any] else {
                    throw UsageError("Unexpected response from Grok")
                }
                return try parse(JSONSerialization.data(withJSONObject: result))
            default:
                return nil
            }
        }
    }

    private static func fetchOverHTTP() async throws -> ProviderUsage {
        var request = URLRequest(url: billingURL)
        request.setValue("Bearer \(try loadToken())", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError("Session expired: run grok to renew it")
        case let status: throw UsageError("Grok responded \(status)")
        }
        return try parse(data)
    }

    /// Current responses carry a `config` with a usage percent; older ones a
    /// monthly limit and total used, in cents.
    private static func parse(_ data: Data) throws -> ProviderUsage {
        let body = try JSONDecoder().decode(BillingResponse.self, from: data)
        let plan = planName(body.config?.subscriptionTier ?? body.subscriptionTier ?? body.subscriptionTierSnake)

        if let config = body.config {
            let end = (config.currentPeriod?.end ?? config.billingPeriodEnd).flatMap(ISO8601.parse)
            let start = (config.currentPeriod?.start ?? config.billingPeriodStart).flatMap(ISO8601.parse)
            let percent = config.creditUsagePercent
                ?? config.onDemandCap?.val.flatMap { cap in cap > 0 ? (config.onDemandUsed?.val ?? 0) / cap * 100 : nil }
                ?? 0
            return ProviderUsage(plan: plan, windows: [UsageWindow(label: periodLabel(from: start, to: end),
                                                                   usedPercent: percent, resetsAt: end)])
        }

        if let limit = body.monthlyLimit?.val, limit > 0 {
            let used = body.usage?.totalUsed?.val ?? 0
            return ProviderUsage(plan: plan, windows: [
                UsageWindow(label: "Monthly",
                            usedPercent: min(100, used / limit * 100),
                            resetsAt: body.billingCycle?.billingPeriodEnd.flatMap(ISO8601.parse)),
            ])
        }
        throw UsageError("Grok reported no usage limits")
    }

    private static func periodLabel(from start: Date?, to end: Date?) -> String {
        guard let start, let end else { return "Credits" }
        let days = end.timeIntervalSince(start) / 86_400
        if days <= 1.5 { return "Daily" }
        if days <= 8 { return UsageWindow.weeklyLabel }
        return "Monthly"
    }

    private static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased().filter(\.isLetter) {
        case "supergrokheavy", "heavy": return "SuperGrok Heavy"
        case "supergrok": return "SuperGrok"
        default: return raw
        }
    }

    // MARK: - Token

    /// `auth.json` maps scopes to credentials; the SuperGrok login lives under the
    /// "https://auth.x.ai::" scope, older logins under the accounts sign-in page.
    private static var authFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
    }

    private static func loadToken() throws -> String {
        guard let data = try? Data(contentsOf: authFile),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw UsageError.notConfigured("Sign in by running grok login") }

        let usable = entries.compactMap { scope, value -> (scope: String, entry: [String: Any])? in
            guard let entry = value as? [String: Any], let key = entry["key"] as? String, !key.isEmpty else { return nil }
            return (scope, entry)
        }
        guard let chosen = usable.first(where: { $0.scope.hasPrefix("https://auth.x.ai::") })
                ?? usable.first(where: { $0.scope.contains("/sign-in") }),
              let key = chosen.entry["key"] as? String
        else { throw UsageError.notConfigured("Sign in by running grok login") }

        return key
    }

    // MARK: - API response

    private struct BillingResponse: Decodable {
        struct Period: Decodable {
            let start: String?
            let end: String?
        }

        /// Amounts come as `{ "val": number }`.
        struct Amount: Decodable {
            let val: Double?
        }

        struct Config: Decodable {
            let creditUsagePercent: Double?
            let currentPeriod: Period?
            let billingPeriodStart: String?
            let billingPeriodEnd: String?
            let onDemandCap: Amount?
            let onDemandUsed: Amount?
            let subscriptionTier: String?
        }

        struct Cycle: Decodable {
            let billingPeriodEnd: String?
        }

        struct Usage: Decodable {
            let totalUsed: Amount?
        }

        let config: Config?
        let subscriptionTier: String?
        let subscriptionTierSnake: String?
        // Older responses.
        let billingCycle: Cycle?
        let monthlyLimit: Amount?
        let usage: Usage?

        enum CodingKeys: String, CodingKey {
            case config, subscriptionTier, billingCycle, monthlyLimit, usage
            case subscriptionTierSnake = "subscription_tier"
        }
    }
}
