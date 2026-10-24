import SwiftUI

/// One Antigravity quota pool. Antigravity splits its limits into a Gemini pool
/// and a Claude/GPT pool, each with its own 5 hour and weekly windows, so each
/// pool is shown as its own row. Both rows share a single `agy` run.
struct AntigravityUsageProvider: UsageProvider {
    enum Pool: String, Sendable {
        case gemini
        case thirdParty
    }

    let pool: Pool

    var id: String { "antigravity-\(pool.rawValue)" }

    var brand: ProviderBrand {
        switch pool {
        case .gemini:
            ProviderBrand(name: "Antigravity",
                          logo: .appIcon("/Applications/Antigravity.app"),
                          logoColor: .white,
                          tileColor: .clear,
                          primary: Color(hex: 0x60A5FA),
                          secondary: Color(hex: 0xC4A7F5))
        case .thirdParty:
            ProviderBrand(name: "Antigravity",
                          logo: .appIcon("/Applications/Antigravity.app"),
                          logoColor: .white,
                          tileColor: .clear,
                          primary: Color(hex: 0x2DD4BF),
                          secondary: Color(hex: 0x99F6E4))
        }
    }

    var title: String {
        pool == .gemini ? "Antigravity · Gemini" : "Antigravity · Claude & GPT"
    }

    func fetch() async throws -> ProviderUsage {
        let report = try await AntigravityReportLoader.shared.load()
        let group = report.first { classify($0.name) == pool }
        guard let group else { throw UsageError("No data for this group") }

        var fiveHour: UsageWindow?
        var weekly: UsageWindow?
        for bucket in group.buckets {
            switch windowKind(bucket) {
            case .fiveHour: fiveHour = bucket.window(UsageWindow.fiveHourLabel)
            case .weekly: weekly = bucket.window(UsageWindow.weeklyLabel)
            case nil: continue
            }
        }
        return ProviderUsage(plan: pool == .gemini ? "Gemini" : "Claude & GPT",
                             windows: [fiveHour, weekly].compactMap { $0 })
    }

    /// "Gemini Models" → gemini, "Claude and GPT models" → thirdParty.
    /// Versioned groups such as "Gemini 4 Argon" are separate quotas and are skipped.
    private func classify(_ name: String) -> Pool? {
        let lower = name.lowercased()
        if lower.contains("claude") || lower.contains("gpt") { return .thirdParty }
        if lower.contains("gemini"), !lower.contains(where: \.isNumber) { return .gemini }
        return nil
    }

    private enum WindowKind { case fiveHour, weekly }

    private func windowKind(_ bucket: AntigravityReportLoader.Bucket) -> WindowKind? {
        let text = [bucket.windowLabel, bucket.id].compactMap { $0?.lowercased() }.joined(separator: " ")
        if text.contains("weekly") { return .weekly }
        if ["5h", "session", "5-hour", "five hour", "five-hour"].contains(where: text.contains) { return .fiveHour }
        return nil
    }
}

/// Runs `agy -p /usage --output-format json` (Antigravity CLI print mode) and caches
/// the result briefly so the two pool rows reuse one run.
actor AntigravityReportLoader {
    static let shared = AntigravityReportLoader()

    struct Bucket {
        let id: String?
        let windowLabel: String?
        let remainingFraction: Double?
        let resetTime: String?
    }

    struct Group {
        let name: String
        let buckets: [Bucket]
    }

    private var cached: (date: Date, groups: [Group])?
    private var inFlight: Task<[Group], Error>?
    private let cacheLifetime: TimeInterval = 20

    func load() async throws -> [Group] {
        if let cached, Date().timeIntervalSince(cached.date) < cacheLifetime {
            return cached.groups
        }
        if let inFlight { return try await inFlight.value }

        let task = Task.detached(priority: .utility) { try Self.runUsageCommand() }
        inFlight = task
        defer { inFlight = nil }
        let groups = try await task.value
        cached = (Date(), groups)
        return groups
    }

    private static func runUsageCommand() throws -> [Group] {
        guard let agy = CLILocator.find("agy") else {
            throw UsageError.notConfigured("Antigravity CLI (agy) not found")
        }

        // Fresh private directory with `open` stubs so a lapsed login never pops a browser.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentch-agy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        for stub in ["open", "xdg-open"] {
            let url = directory.appendingPathComponent(stub)
            try Data("#!/bin/sh\nexit 1\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }

        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = [directory.path, agy.deletingLastPathComponent().path, "/opt/homebrew/bin",
                               "/usr/local/bin", "\(home)/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
        environment["BROWSER"] = directory.appendingPathComponent("open").path
        environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"

        let process = Process()
        process.executableURL = agy
        process.arguments = ["-p", "/usage", "--output-format", "json", "--print-timeout", "60s"]
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 75, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "SUCCESS",
              let command = json["command"] as? [String: Any],
              command["name"] as? String == "usage",
              let payload = command["data"] as? [String: Any],
              let rawGroups = payload["groups"] as? [[String: Any]] else {
            throw UsageError("Sign in by running agy in a terminal")
        }

        return rawGroups.map { group in
            let buckets = (group["buckets"] as? [[String: Any]] ?? []).map { bucket in
                Bucket(id: bucket["id"] as? String,
                       windowLabel: bucket["window"] as? String,
                       remainingFraction: (bucket["remaining_fraction"] as? NSNumber)?.doubleValue,
                       resetTime: bucket["reset_time"] as? String)
            }
            return Group(name: group["name"] as? String ?? "", buckets: buckets)
        }
    }
}

extension AntigravityReportLoader.Bucket {
    /// A bucket without `remaining_fraction` is unknown, not full.
    func window(_ label: String) -> UsageWindow? {
        guard let remainingFraction else { return nil }
        let used = 100 - max(0, min(100, remainingFraction * 100))
        return UsageWindow(label: label, usedPercent: used, resetsAt: resetTime.flatMap(ISO8601.parse))
    }
}
