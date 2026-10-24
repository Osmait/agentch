import SwiftUI

/// Reads Cursor's monthly plan usage from cursor.com, authenticating with the token
/// `cursor-agent login` keeps in the login Keychain.
struct CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let brand = ProviderBrand(name: "Cursor",
                              logo: .asset("CursorLogo"),
                              logoColor: .white,
                              tileColor: .white.opacity(0.1),
                              primary: Color(hex: 0xE8E8ED),
                              secondary: Color(hex: 0xA1A1AA))

    private static let keychainService = "cursor-access-token"
    private static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    func fetch() async throws -> ProviderUsage {
        let token = try Self.loadToken()
        var request = URLRequest(url: Self.summaryURL)
        request.setValue("WorkosCursorSessionToken=\(try token.userID())%3A%3A\(token.raw)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError("Session expired: run cursor-agent login")
        case let status: throw UsageError("Cursor responded \(status)")
        }
        return Self.parse(try JSONDecoder().decode(UsageSummary.self, from: data))
    }

    private static func parse(_ summary: UsageSummary) -> ProviderUsage {
        let cycleEnd = summary.billingCycleEnd.flatMap(ISO8601.parse)
        var windows: [UsageWindow] = []

        if let plan = summary.individualUsage?.plan {
            // Percent fields are already percentages; fall back to cents when they are missing.
            let percent = plan.totalPercentUsed
                ?? plan.limit.flatMap { $0 > 0 ? Double(plan.used ?? 0) / Double($0) * 100 : nil }
                ?? 0
            windows.append(UsageWindow(label: "Monthly", usedPercent: percent, resetsAt: cycleEnd))
        }

        // On-demand spending past the plan, when the user enabled it.
        if let onDemand = summary.individualUsage?.onDemand, onDemand.enabled == true {
            let used = onDemand.used ?? 0
            let percent = onDemand.limit.flatMap { $0 > 0 ? Double(used) / Double($0) * 100 : nil } ?? 0
            let detail = onDemand.limit.map { "\(dollars(used)) of \(dollars($0))" } ?? dollars(used)
            windows.append(UsageWindow(label: "Extra", usedPercent: percent, resetsAt: nil, detail: detail))
        }

        return ProviderUsage(plan: summary.membershipType.map(planName), windows: windows)
    }

    private static func dollars(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    /// "pro_plus" → "Pro Plus"
    private static func planName(_ raw: String) -> String {
        raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: - Token

    private struct Token {
        let raw: String

        /// The JWT subject looks like "auth0|user_01ABC"; cursor.com wants the last part.
        func userID() throws -> String {
            let parts = raw.split(separator: ".")
            guard parts.count >= 2 else { throw UsageError("Unexpected Cursor token") }
            var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            guard let data = Data(base64Encoded: payload),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let subject = json["sub"] as? String,
                  let userID = subject.split(separator: "|").last
            else { throw UsageError("Unexpected Cursor token") }
            return String(userID)
        }
    }

    private static func loadToken() throws -> Token {
        guard let data = try KeychainCLI.password(service: keychainService),
              let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { throw UsageError("Sign in by running cursor-agent login") }
        return Token(raw: raw)
    }

    // MARK: - API response

    private struct UsageSummary: Decodable {
        struct Plan: Decodable {
            /// Cents.
            let used: Int?
            let limit: Int?
            let totalPercentUsed: Double?
        }

        struct OnDemand: Decodable {
            let enabled: Bool?
            /// Cents.
            let used: Int?
            /// Cents; nil when unlimited.
            let limit: Int?
        }

        struct IndividualUsage: Decodable {
            let plan: Plan?
            let onDemand: OnDemand?
        }

        let billingCycleEnd: String?
        let membershipType: String?
        let individualUsage: IndividualUsage?
    }
}
