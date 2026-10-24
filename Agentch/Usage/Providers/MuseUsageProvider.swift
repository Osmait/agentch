import SwiftUI

/// Reads Muse Code's subscription limits from Meta's API, authenticating with the
/// device token `muse login` keeps in the login Keychain.
struct MuseUsageProvider: UsageProvider {
    let id = "muse"
    let brand = ProviderBrand(name: "Muse Code",
                              logo: .asset("MetaLogo"),
                              logoColor: Color(hex: 0x4A9DFF),
                              tileColor: Color(hex: 0x0081FB, opacity: 0.16),
                              primary: Color(hex: 0x4A9DFF),
                              secondary: Color(hex: 0xA78BFA))

    private static let keyURL = URL(string: "https://api.meta.ai/muse-code/key")!

    func fetch() async throws -> ProviderUsage {
        var request = URLRequest(url: Self.keyURL)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(try Self.loadToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1.0.0", forHTTPHeaderField: "x-api-version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError("Session expired: run muse login")
        case 429: throw UsageError("Rate limited, retrying later")
        case let status: throw UsageError("Muse responded \(status)")
        }

        let body = try JSONDecoder().decode(KeyResponse.self, from: data)
        if body.requirePayment == true { throw UsageError("Finish billing at dev.meta.ai") }
        guard body.isSubsActive == true else { throw UsageError.notConfigured("No active Muse Code subscription") }

        // The response omits usage while the 5 hour window is idle.
        let usage = body.subsUsage
        let windows = [
            UsageWindow(label: UsageWindow.fiveHourLabel,
                        usedPercent: usage?.window?.usedPercent ?? 0,
                        resetsAt: usage?.window?.resetDate),
            usage?.weekly.map {
                UsageWindow(label: UsageWindow.weeklyLabel, usedPercent: $0.usedPercent ?? 0, resetsAt: $0.resetDate)
            },
        ]
        return ProviderUsage(plan: body.subsTierName, windows: windows.compactMap { $0 })
    }

    private static func loadToken() throws -> String {
        guard let data = try KeychainCLI.password(service: "ai.meta.dev.credentials", account: "meta"),
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data),
              let token = stored.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              token.hasPrefix("dca:")
        else { throw UsageError.notConfigured("Sign in by running muse login") }
        return token
    }

    private struct StoredCredentials: Decodable {
        let accessToken: String?
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }

    // MARK: - API response

    private struct KeyResponse: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            /// Seconds since 1970.
            let resetsAt: Double?

            var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: $0) } }

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetsAt = "resets_at"
            }
        }

        struct SubsUsage: Decodable {
            let window: Window?
            let weekly: Window?
        }

        let requirePayment: Bool?
        let isSubsActive: Bool?
        let subsTierName: String?
        let subsUsage: SubsUsage?

        enum CodingKeys: String, CodingKey {
            case requirePayment = "require_payment"
            case isSubsActive = "is_subs_active"
            case subsTierName = "subs_tier_name"
            case subsUsage = "subs_usage"
        }
    }
}
