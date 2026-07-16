import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

public enum LiveActivityTokenType: String, Codable, Sendable {
    case pushToStart = "liveactivity-push-to-start"
    case update = "liveactivity-update"
}

public struct LiveActivityTokenRegistration: Codable, Equatable, Sendable {
    public let deviceToken: String
    public let bundleId: String
    public let environment: String
    public let tokenType: LiveActivityTokenType
    public let activityId: String?
    public let sessionId: String?

    public init(
        deviceToken: String,
        bundleId: String,
        environment: String,
        tokenType: LiveActivityTokenType,
        activityId: String? = nil,
        sessionId: String? = nil
    ) {
        self.deviceToken = deviceToken
        self.bundleId = bundleId
        self.environment = environment
        self.tokenType = tokenType
        self.activityId = activityId
        self.sessionId = sessionId
    }
}

public protocol LiveActivityTokenRegistering: Sendable {
    func registerLiveActivityToken(_ registration: LiveActivityTokenRegistration) async throws
}

@available(iOS 17.2, *)
public actor LiveActivityCoordinator {
    private var isStarted = false
    private var observationTasks: [Task<Void, Never>] = []
    private var sessionIndex = LiveActivitySessionIndex()

    public init() {}

    public func start(
        registrar: any LiveActivityTokenRegistering,
        bundleId: String,
        environment: String
    ) async {
        guard !isStarted else { return }
        isStarted = true

        for activity in Activity<SessionActivityAttributes>.activities {
            track(
                activity,
                registrar: registrar,
                bundleId: bundleId,
                environment: environment
            )
        }

        observationTasks.append(Task {
            for await token in Activity<SessionActivityAttributes>.pushToStartTokenUpdates {
                try? await registrar.registerLiveActivityToken(.init(
                    deviceToken: token.hexEncodedString,
                    bundleId: bundleId,
                    environment: environment,
                    tokenType: .pushToStart
                ))
            }
        })

        observationTasks.append(Task {
            for await activity in Activity<SessionActivityAttributes>.activityUpdates {
                track(
                    activity,
                    registrar: registrar,
                    bundleId: bundleId,
                    environment: environment
                )
            }
        })
    }

    private func track(
        _ activity: Activity<SessionActivityAttributes>,
        registrar: any LiveActivityTokenRegistering,
        bundleId: String,
        environment: String
    ) {
        switch sessionIndex.claim(
            sessionId: activity.attributes.sessionId,
            activityId: activity.id
        ) {
        case .accepted:
            observeUpdateTokens(
                for: activity,
                registrar: registrar,
                bundleId: bundleId,
                environment: environment
            )
        case .alreadyTracked:
            break
        case .duplicate:
            endDuplicate(activity)
        }
    }

    private func endDuplicate(
        _ activity: sending Activity<SessionActivityAttributes>
    ) {
        observationTasks.append(Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        })
    }

    private func observeUpdateTokens(
        for activity: sending Activity<SessionActivityAttributes>,
        registrar: any LiveActivityTokenRegistering,
        bundleId: String,
        environment: String
    ) {
        observationTasks.append(Task {
            for await token in activity.pushTokenUpdates {
                try? await registrar.registerLiveActivityToken(.init(
                    deviceToken: token.hexEncodedString,
                    bundleId: bundleId,
                    environment: environment,
                    tokenType: .update,
                    activityId: activity.id,
                    sessionId: activity.attributes.sessionId
                ))
            }
        })
    }
}
#endif

struct LiveActivitySessionIndex: Sendable {
    enum Claim: Equatable, Sendable {
        case accepted
        case alreadyTracked
        case duplicate
    }

    private var activityIDBySessionID: [String: String] = [:]

    mutating func claim(sessionId: String, activityId: String) -> Claim {
        guard let existingActivityId = activityIDBySessionID[sessionId] else {
            activityIDBySessionID[sessionId] = activityId
            return .accepted
        }
        return existingActivityId == activityId ? .alreadyTracked : .duplicate
    }
}
