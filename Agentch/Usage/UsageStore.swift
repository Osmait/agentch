import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class UsageStore {
    nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Agentch", category: "usage")

    struct Entry: Identifiable {
        let provider: any UsageProvider
        var status: ProviderStatus = .loading
        var id: String { provider.id }
    }

    private(set) var entries: [Entry]
    private(set) var lastUpdated: Date?

    private var isRefreshing = false
    private var timer: Timer?

    private let refreshInterval: TimeInterval = 120
    private let staleAfter: TimeInterval = 30

    init(providers: [any UsageProvider]) {
        entries = providers.map { Entry(provider: $0) }
    }

    func startAutoRefresh() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Refreshes when the panel opens, unless the data is still fresh.
    func refreshIfStale() {
        guard let lastUpdated else { return refresh() }
        if Date().timeIntervalSince(lastUpdated) > staleAfter { refresh() }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let providers = entries.map(\.provider)

        Task {
            let results = await withTaskGroup(of: (String, ProviderStatus).self) { group in
                for provider in providers {
                    group.addTask {
                        do {
                            let usage = try await provider.fetch()
                            let summary = [usage.fiveHour, usage.weekly]
                                .map { $0.map { "\(Int($0.usedPercent))% → \($0.resetsAt?.description ?? "—")" } ?? "nil" }
                                .joined(separator: " | ")
                            Self.log.info("\(provider.id, privacy: .public): \(summary, privacy: .public)")
                            return (provider.id, .loaded(usage))
                        } catch {
                            Self.log.error("\(provider.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            return (provider.id, .failed(error.localizedDescription))
                        }
                    }
                }
                var collected: [String: ProviderStatus] = [:]
                for await (id, status) in group { collected[id] = status }
                return collected
            }

            for index in entries.indices {
                guard let status = results[entries[index].id] else { continue }
                // Keep the last good data if a refresh fails.
                if case .failed = status, case .loaded = entries[index].status { continue }
                entries[index].status = status
            }
            lastUpdated = Date()
            isRefreshing = false
        }
    }
}
