import SwiftUI

/// Reads Claude Code's subscription limits from Anthropic's OAuth usage endpoint,
/// authenticating with the token Claude Code keeps in the login Keychain.
struct ClaudeUsageProvider: UsageProvider {
    let id = "claude"
    let brand = ProviderBrand(name: "Claude Code",
                              logo: .asset("ClaudeLogo"),
                              logoColor: Color(hex: 0xD97757),
                              tileColor: Color(hex: 0xD97757, opacity: 0.14),
                              primary: Color(hex: 0xFF8A65),
                              secondary: Color(hex: 0xFFB199))

    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch() async throws -> ProviderUsage {
        let credentials = try await ClaudeTokenCache.shared.credentials()
        do {
            return try await Self.requestUsage(with: credentials)
        } catch ClaudeAPIError.unauthorized {
            // Claude Code rotated its token: read the Keychain again and retry once.
            let fresh = try await ClaudeTokenCache.shared.credentials(forceReload: true)
            do {
                return try await Self.requestUsage(with: fresh)
            } catch ClaudeAPIError.unauthorized {
                throw UsageError("Session expired: open Claude Code to renew it")
            }
        }
    }

    private enum ClaudeAPIError: Error { case unauthorized }

    private static func requestUsage(with credentials: Credentials) async throws -> ProviderUsage {
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401, 403: throw ClaudeAPIError.unauthorized
        default: throw UsageError("The API responded \(status)")
        }

        let body = try JSONDecoder().decode(UsageResponse.self, from: data)
        let windows = [body.fiveHour?.window(UsageWindow.fiveHourLabel),
                       body.sevenDay?.window(UsageWindow.weeklyLabel)]
        return ProviderUsage(plan: credentials.planName, windows: windows.compactMap { $0 })
    }

    // MARK: - Keychain

    struct Credentials: Sendable {
        let accessToken: String
        let planName: String?
        let expiresAt: Date?
    }

    /// The token is kept in memory and only re-read when it expires or is rejected.
    actor ClaudeTokenCache {
        static let shared = ClaudeTokenCache()
        private var cached: Credentials?

        func credentials(forceReload: Bool = false) throws -> Credentials {
            if !forceReload, let cached, (cached.expiresAt ?? .distantFuture) > Date().addingTimeInterval(60) {
                return cached
            }
            let loaded = try ClaudeUsageProvider.loadCredentials()
            cached = loaded
            return loaded
        }
    }

    fileprivate static func loadCredentials() throws -> Credentials {
        guard let data = try KeychainCLI.password(service: keychainService) else {
            throw UsageError.notConfigured("No Claude Code session on this Mac")
        }
        let stored = try JSONDecoder().decode(StoredCredentials.self, from: data)
        guard let oauth = stored.claudeAiOauth else {
            throw UsageError("Claude Code is not using a subscription")
        }
        return Credentials(accessToken: oauth.accessToken,
                           planName: oauth.subscriptionType.map { $0.prefix(1).uppercased() + $0.dropFirst() },
                           expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    private struct StoredCredentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let subscriptionType: String?
            /// Milliseconds since 1970.
            let expiresAt: Double?
        }
        let claudeAiOauth: OAuth?
    }

    // MARK: - API response

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }

            func window(_ label: String) -> UsageWindow {
                UsageWindow(label: label, usedPercent: utilization ?? 0, resetsAt: resetsAt.flatMap(ISO8601.parse))
            }
        }

        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }
}

enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        // ISO8601DateFormatter only understands milliseconds; trim micro- and nanoseconds.
        let trimmed = string.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return withFraction.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}
