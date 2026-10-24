import SwiftUI

/// Reads OpenCode Go's rolling 5 hour, weekly and monthly limits the way OpenCode
/// itself does: with the OpenCode Console sign-in (`opencode auth login`), or with
/// an OpenCode Go API key saved by older versions.
struct OpenCodeGoUsageProvider: UsageProvider {
    let id = "opencode-go"
    let brand = ProviderBrand(name: "OpenCode Go",
                              logo: .asset("OpenCodeLogo"),
                              logoColor: .primary,
                              tileColor: .primary.opacity(0.1),
                              primary: Color(hex: 0x34D399),
                              secondary: Color(hex: 0x6EE7B7))

    func fetch() async throws -> ProviderUsage {
        let credential = try Self.consoleCredential() ?? Self.legacyKey()
        guard let credential else {
            throw UsageError.notConfigured("Run opencode auth login and sign in to OpenCode Console")
        }
        if let expires = credential.expiresAt, expires < Date() {
            throw UsageError("Session expired: open opencode to renew it")
        }

        var request = URLRequest(url: credential.origin.appendingPathComponent("zen/go/v1/usage"))
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        if let orgID = credential.orgID { request.setValue(orgID, forHTTPHeaderField: "x-opencode-org-id") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw UsageError("Session expired: open opencode to renew it")
        // OpenCode answers 403 for a workspace without a Go subscription.
        case 403: throw UsageError.notConfigured("No OpenCode Go subscription in this workspace")
        case let status: throw UsageError("OpenCode responded \(status)")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any]
        else { throw UsageError("Unexpected response from OpenCode") }

        let now = Date()
        let windows = [
            Self.window(usage["rolling"], label: UsageWindow.fiveHourLabel, now: now),
            Self.window(usage["weekly"], label: UsageWindow.weeklyLabel, now: now),
            Self.window(usage["monthly"], label: "Monthly", now: now),
        ]
        return ProviderUsage(plan: credential.workspace ?? "Go", windows: windows.compactMap { $0 })
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

    // MARK: - Credentials

    private struct Credential {
        let token: String
        var orgID: String?
        var workspace: String?
        var expiresAt: Date?
        var origin = URL(string: "https://opencode.ai")!
    }

    private static var dataHome: URL {
        ProcessInfo.processInfo.environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
    }

    /// OpenCode 2 keeps the active OpenCode Console connection in its database.
    private static func consoleCredential() throws -> Credential? {
        let database = dataHome.appendingPathComponent("opencode/opencode.db")
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path,
                             "SELECT value FROM credential WHERE integration_id = 'opencode' AND active = 1 "
                                 + "ORDER BY time_updated DESC LIMIT 1;"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let text = rows.first?["value"] as? String,
              let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }

        let token = (value["type"] as? String == "oauth" ? value["access"] : value["key"]) as? String
        guard let token, !token.isEmpty else { return nil }
        let metadata = value["metadata"] as? [String: Any]
        var credential = Credential(token: token,
                                    orgID: metadata?["orgID"] as? String,
                                    workspace: metadata?["orgName"] as? String,
                                    expiresAt: (value["expires"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) })
        if let server = (metadata?["server"] as? String).flatMap(URL.init(string:)),
           let scheme = server.scheme, let host = server.host {
            credential.origin = URL(string: "\(scheme)://\(host)")!
        }
        return credential
    }

    /// OpenCode 1 stored an OpenCode Go API key in auth.json.
    private static func legacyKey() -> Credential? {
        let url = dataHome.appendingPathComponent("opencode/auth.json")
        guard let data = try? Data(contentsOf: url),
              let providers = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = providers["opencode-go"] as? [String: Any],
              let key = (entry["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return Credential(token: key)
    }
}
