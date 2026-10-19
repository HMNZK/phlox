import Foundation
import Observation
import PhloxCore

/// アプリ全体で共有するアカウント単位の CLI 使用量。
@MainActor
@Observable
public final class UsageViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private let api: PhloxAPI
    private let now: () -> Date

    public private(set) var state: State = .idle
    public private(set) var agents: [CLIUsage] = []
    private var lastSuccessfulAt: Date?

    public init(api: PhloxAPI) {
        self.api = api
        self.now = Date.init
    }

    init(
        api: PhloxAPI,
        agents: [CLIUsage],
        state: State,
        lastSuccessfulAt: Date?,
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.agents = agents
        self.state = state
        self.lastSuccessfulAt = lastSuccessfulAt
        self.now = now
    }

    public var shouldShowRow: Bool {
        !presentationAgents.isEmpty
    }

    var presentationAgents: [UsageRingAgent] {
        UsageRingPresentation.agents(from: agents)
    }

    public var isRefreshing: Bool {
        state == .loading
    }

    public var isStale: Bool {
        state == .failed && shouldShowRow
    }

    public var asOfDate: Date? {
        guard shouldShowRow else { return nil }
        return agents.compactMap { $0.dataAsOf ?? $0.updatedAt }.min() ?? lastSuccessfulAt
    }

    public var currentDate: Date { now() }

    public func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            agents = try await api.cliUsage()
            lastSuccessfulAt = now()
            state = .loaded
        } catch {
            agents = []
            state = .failed
        }
    }
}
