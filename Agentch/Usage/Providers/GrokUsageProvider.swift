import SwiftUI

/// Reads Grok's credit usage for the current billing period, authenticating with the
/// token `grok login` keeps in `~/.grok/auth.json`.
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
        var request = URLRequest(url: Self.billingURL)
        request.setValue("Bearer \(try Self.loadToken())", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError("Session expired: run grok to renew it")
        case let status: throw UsageError("Grok responded \(status)")
        }

        let body = try JSONDecoder().decode(BillingResponse.self, from: data)
        guard let config = body.config else { throw UsageError("Unexpected response from Grok") }

        let end = (config.currentPeriod?.end ?? config.billingPeriodEnd).flatMap(ISO8601.parse)
        let start = (config.currentPeriod?.start ?? config.billingPeriodStart).flatMap(ISO8601.parse)
        let percent = config.creditUsagePercent
            ?? config.onDemandCap?.val.flatMap { cap in cap > 0 ? (config.onDemandUsed?.val ?? 0) / cap * 100 : nil }
            ?? 0

        return ProviderUsage(plan: Self.planName(config.subscriptionTier ?? body.subscriptionTier),
                             windows: [UsageWindow(label: Self.periodLabel(from: start, to: end),
                                                   usedPercent: percent,
                                                   resetsAt: end)])
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
    private static func loadToken() throws -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
        guard let data = try? Data(contentsOf: url),
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

        if let expires = (chosen.entry["expires_at"] as? String).flatMap(ISO8601.parse), expires < Date() {
            throw UsageError("Session expired: run grok to renew it")
        }
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

        let config: Config?
        let subscriptionTier: String?
    }
}
