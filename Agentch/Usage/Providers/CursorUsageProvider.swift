import SwiftUI

/// Reads Cursor's monthly plan usage from cursor.com, authenticating with the token
/// `cursor-agent login` keeps in the login Keychain.
struct CursorUsageProvider: UsageProvider {
    let id = "cursor"
    let brand = ProviderBrand(name: "Cursor",
                              logo: .asset("CursorLogo"),
                              logoColor: .primary,
                              tileColor: .primary.opacity(0.1),
                              primary: .primary.opacity(0.9),
                              secondary: .primary.opacity(0.55))

    private static let keychainService = "cursor-access-token"
    private static let base = URL(string: "https://cursor.com")!

    func fetch() async throws -> ProviderUsage {
        let token = try Self.loadToken()
        let cookie = "WorkosCursorSessionToken=\(try token.userID())%3A%3A\(token.raw)"

        async let sand = try? Self.request("api/dashboard/get-sand-usage-status", cookie: cookie, post: true)
        let summaryData = try await Self.request("api/usage-summary", cookie: cookie)
        let summary = try JSONDecoder().decode(UsageSummary.self, from: summaryData)
        let sandStatus = await sand.flatMap { try? JSONDecoder().decode(SandStatus.self, from: $0) }
        return Self.parse(summary, sand: sandStatus)
    }

    private static func request(_ path: String, cookie: String, post: Bool = false) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if post {
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        }
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return data
        case 401, 403: throw UsageError("Session expired: run cursor-agent login")
        case let status: throw UsageError("Cursor responded \(status)")
        }
    }

    private static func parse(_ summary: UsageSummary, sand: SandStatus?) -> ProviderUsage {
        let cycleEnd = summary.billingCycleEnd.flatMap(ISO8601.parse)
        var windows: [UsageWindow] = []
        let grok = sand?.window(now: Date())

        // Accounts unified with Grok spend from a weekly pool shared with Grok; the
        // summary keeps reporting the old monthly plan, which then stays at 0%.
        if let grok, sand?.isUnified == true, grok.resetsAt != nil {
            windows.append(UsageWindow(label: UsageWindow.weeklyLabel, usedPercent: grok.usedPercent, resetsAt: grok.resetsAt))
        } else if let plan = summary.individualUsage?.plan {
            // Percent fields are already percentages; fall back to cents when they are missing.
            let percent = plan.totalPercentUsed
                ?? plan.limit.flatMap { $0 > 0 ? Double(plan.used ?? 0) / Double($0) * 100 : nil }
                ?? 0
            windows.append(UsageWindow(label: "Monthly", usedPercent: percent, resetsAt: cycleEnd))
            // Grok Bot allowance on accounts that aren't unified.
            if let grok { windows.append(grok) }
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
        else { throw UsageError.notConfigured("Sign in by running cursor-agent login") }
        return Token(raw: raw)
    }

    // MARK: - API response

    /// Grok Bot ("Sand") allowance, or the weekly pool shared with Grok on unified accounts.
    private struct SandStatus: Decodable {
        let nextResetTimestampUtc: String?
        let usagePercent: Double?
        let hasNonZeroIncludedLimit: Bool?
        let includedLimitZero: Bool?
        let sandTrialExpiresAt: String?
        let isUnified: Bool?

        func window(now: Date) -> UsageWindow? {
            let hasLimit = includedLimitZero.map { !$0 } ?? hasNonZeroIncludedLimit ?? false
            let inTrial = !hasLimit && (sandTrialExpiresAt.flatMap(ISO8601.parse).map { $0 > now } ?? false)
            guard hasLimit || inTrial || isUnified == true, let usagePercent else { return nil }
            // A trial ends rather than resets.
            let resetsAt = inTrial ? nil : nextResetTimestampUtc.flatMap(ISO8601.parse)
            return UsageWindow(label: "Grok Bot", usedPercent: min(max(usagePercent, 0), 100), resetsAt: resetsAt)
        }
    }

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
