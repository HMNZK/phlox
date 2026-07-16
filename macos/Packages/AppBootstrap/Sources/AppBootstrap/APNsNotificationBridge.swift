import Foundation
import os
import APNsClient
import AgentDomain
import DashboardFeature
import SessionFeature

public protocol APNsNotificationSending: Sendable {
    func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data
    ) async throws -> APNsSendResult

    func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data,
        pushType: APNsPushType
    ) async throws -> APNsSendResult
}

public extension APNsNotificationSending {
    func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data,
        pushType: APNsPushType
    ) async throws -> APNsSendResult {
        try await send(registration: registration, collapseID: collapseID, payload: payload)
    }
}

public struct APNsNotificationBridgeSender: APNsNotificationSending {
    private let sandboxSender: APNsSender
    private let productionSender: APNsSender

    public init(authKeyPEM: String, keyID: String, teamID: String) throws {
        let authKey = try APNsAuthKey(pem: authKeyPEM)
        let sandboxConfiguration = APNsConfiguration(keyID: keyID, teamID: teamID, environment: .sandbox)
        let productionConfiguration = APNsConfiguration(keyID: keyID, teamID: teamID, environment: .production)
        self.sandboxSender = APNsSender(
            configuration: sandboxConfiguration,
            signer: APNsProviderTokenSigner(configuration: sandboxConfiguration, authKey: authKey)
        )
        self.productionSender = APNsSender(
            configuration: productionConfiguration,
            signer: APNsProviderTokenSigner(configuration: productionConfiguration, authKey: authKey)
        )
    }

    public func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data
    ) async throws -> APNsSendResult {
        let sender = switch registration.environment {
        case .sandbox: sandboxSender
        case .production: productionSender
        }
        return try await sender.send(
            deviceToken: registration.deviceToken,
            topic: registration.bundleId,
            collapseID: collapseID,
            payload: payload
        )
    }

    public func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data,
        pushType: APNsPushType
    ) async throws -> APNsSendResult {
        let sender = switch registration.environment {
        case .sandbox: sandboxSender
        case .production: productionSender
        }
        return try await sender.send(
            deviceToken: registration.deviceToken,
            topic: registration.bundleId,
            collapseID: collapseID,
            payload: payload,
            pushType: pushType
        )
    }
}

public struct APNsNotificationBridge: RemoteSessionNotifier, Sendable {
    static let keyIDEnvironmentKey = "PHLOX_APNS_KEY_ID"
    static let teamIDEnvironmentKey = "PHLOX_APNS_TEAM_ID"
    static let authKeyPEMEnvironmentKey = "PHLOX_APNS_AUTH_KEY_PEM"
    static let authKeyPathEnvironmentKey = "PHLOX_APNS_AUTH_KEY_PATH"

    /// 運用時の切り分け用ログ。デバイストークンは先頭 8 桁のみ・鍵素材は一切出さない。
    private static let logger = Logger(subsystem: "com.phlox.Phlox", category: "APNs")

    enum NotificationEvent: Sendable {
        case sessionCompleted(sessionId: String, sessionName: String)
        case approvalPending(sessionId: String, sessionName: String)

        var type: String {
            switch self {
            case .sessionCompleted: "session_completed"
            case .approvalPending: "approval_pending"
            }
        }

        var body: String {
            switch self {
            case .sessionCompleted: "Session completed"
            case .approvalPending: "Approval pending"
            }
        }

        var sessionId: String {
            switch self {
            case .sessionCompleted(let sessionId, _), .approvalPending(let sessionId, _):
                sessionId
            }
        }

        var sessionName: String {
            switch self {
            case .sessionCompleted(_, let sessionName), .approvalPending(_, let sessionName):
                sessionName
            }
        }

        var collapseID: String {
            "\(sessionId):\(type)"
        }
    }

    private let deviceTokenStore: any DeviceTokenStore
    private let sender: (any APNsNotificationSending)?
    private let clock: @Sendable () -> Date
    private let liveActivityStarts: LiveActivityStartRegistry

    public init(
        deviceTokenStore: any DeviceTokenStore,
        sender: (any APNsNotificationSending)?,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.deviceTokenStore = deviceTokenStore
        self.sender = sender
        self.clock = clock
        self.liveActivityStarts = LiveActivityStartRegistry()
    }

    public static func configuredFromEnvironment(
        deviceTokenStore: any DeviceTokenStore,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileLoader: @escaping @Sendable (String) throws -> String = {
            try String(contentsOfFile: $0, encoding: .utf8)
        }
    ) -> APNsNotificationBridge {
        guard let keyID = nonEmpty(environment[keyIDEnvironmentKey]),
              let teamID = nonEmpty(environment[teamIDEnvironmentKey]),
              let authKeyPEM = loadAuthKeyPEM(environment: environment, fileLoader: fileLoader)
        else {
            logger.info("APNs notifier disabled: credentials not configured (no-op mode)")
            return APNsNotificationBridge(deviceTokenStore: deviceTokenStore, sender: nil)
        }

        do {
            let bridge = APNsNotificationBridge(
                deviceTokenStore: deviceTokenStore,
                sender: try APNsNotificationBridgeSender(
                    authKeyPEM: authKeyPEM,
                    keyID: keyID,
                    teamID: teamID
                )
            )
            logger.info("APNs notifier configured (sandbox + production senders ready)")
            return bridge
        } catch {
            logger.error("APNs notifier disabled: auth key rejected (\(String(describing: error), privacy: .public))")
            return APNsNotificationBridge(deviceTokenStore: deviceTokenStore, sender: nil)
        }
    }

    public func sessionCompleted(sessionId: String, sessionName: String) {
        enqueue(.sessionCompleted(sessionId: sessionId, sessionName: sessionName))
    }

    public func approvalPending(sessionId: String, sessionName: String) {
        enqueue(.approvalPending(sessionId: sessionId, sessionName: sessionName))
    }

    func notify(_ event: NotificationEvent) async {
        guard let sender else { return }
        let registrations: [DeviceTokenRegistration]
        do {
            registrations = try deviceTokenStore.loadAll()
        } catch {
            Self.logger.error("APNs notify skipped: device token load failed (\(String(describing: error), privacy: .public))")
            return
        }

        let alertPayload: Data
        do {
            alertPayload = try makePayload(for: event)
        } catch {
            Self.logger.error("APNs notify skipped: payload encoding failed (\(String(describing: error), privacy: .public))")
            return
        }

        for registration in registrations where registration.tokenType == .device {
            let tokenPrefix = String(registration.deviceToken.prefix(8))
            do {
                let result = try await sender.send(
                    registration: registration,
                    collapseID: event.collapseID,
                    payload: alertPayload
                )
                switch result {
                case .success:
                    break
                case .unregistered(let reason):
                    Self.logger.notice("APNs token \(tokenPrefix, privacy: .public)… unregistered (\(reason, privacy: .public)); removing")
                    try? deviceTokenStore.remove(deviceToken: registration.deviceToken)
                case .failure(let statusCode, let reason):
                    Self.logger.error("APNs send failed for token \(tokenPrefix, privacy: .public)…: HTTP \(statusCode) \(reason, privacy: .public)")
                }
            } catch {
                Self.logger.error("APNs send failed for token \(tokenPrefix, privacy: .public)…: \(String(describing: error), privacy: .public)")
                continue
            }
        }
        let matchingUpdates = registrations.filter {
            $0.tokenType == .liveActivityUpdate && $0.sessionId == event.sessionId
        }
        if matchingUpdates.isEmpty {
            for registration in registrations where registration.tokenType == .liveActivityPushToStart {
                let reserved = await liveActivityStarts.reserve(
                    sessionId: event.sessionId,
                    deviceToken: registration.deviceToken
                )
                guard reserved else { continue }
                let started = await sendLiveActivity(
                    event,
                    registration: registration,
                    apnsEvent: "start",
                    sender: sender
                )
                if !started {
                    await liveActivityStarts.release(
                        sessionId: event.sessionId,
                        deviceToken: registration.deviceToken
                    )
                }
            }
        } else {
            let apnsEvent = event.type == "session_completed" ? "end" : "update"
            for registration in matchingUpdates {
                _ = await sendLiveActivity(
                    event,
                    registration: registration,
                    apnsEvent: apnsEvent,
                    sender: sender
                )
            }
        }
    }

    private func enqueue(_ event: NotificationEvent) {
        guard sender != nil else { return }
        Task.detached(priority: .utility) {
            await notify(event)
        }
    }

    private func makePayload(for event: NotificationEvent) throws -> Data {
        let payload = Payload(
            aps: APS(
                alert: Alert(title: event.sessionName, body: event.body),
                sound: "default",
                threadID: event.sessionId
            ),
            phlox: Phlox(
                v: 1,
                type: event.type,
                sessionId: event.sessionId,
                sessionName: event.sessionName
            )
        )
        let encoder = JSONEncoder()
        return try encoder.encode(payload)
    }

    private func sendLiveActivity(
        _ event: NotificationEvent,
        registration: DeviceTokenRegistration,
        apnsEvent: String,
        sender: any APNsNotificationSending
    ) async -> Bool {
        let tokenPrefix = String(registration.deviceToken.prefix(8))
        do {
            let payload = try makeLiveActivityPayload(for: event, apnsEvent: apnsEvent)
            let result = try await sender.send(
                registration: registration,
                collapseID: "\(event.sessionId):liveactivity",
                payload: payload,
                pushType: .liveactivity
            )
            switch result {
            case .success:
                return true
            case .unregistered(let reason):
                Self.logger.notice("APNs live activity token \(tokenPrefix, privacy: .public)… unregistered (\(reason, privacy: .public)); removing")
                try? deviceTokenStore.remove(deviceToken: registration.deviceToken)
                return false
            case .failure(let statusCode, let reason):
                Self.logger.error("APNs live activity send failed for token \(tokenPrefix, privacy: .public)…: HTTP \(statusCode) \(reason, privacy: .public)")
                return false
            }
        } catch {
            Self.logger.error("APNs live activity send failed for token \(tokenPrefix, privacy: .public)…: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func makeLiveActivityPayload(for event: NotificationEvent, apnsEvent: String) throws -> Data {
        let timestamp = Int(clock().timeIntervalSince1970)
        let contentState = LiveActivityContentState(
            sessionId: event.sessionId,
            sessionName: event.sessionName,
            status: event.type,
            summary: event.body
        )
        let isStart = apnsEvent == "start"
        let payload = LiveActivityPayload(aps: LiveActivityAPS(
            timestamp: timestamp,
            event: apnsEvent,
            contentState: contentState,
            staleDate: timestamp + (event.type == "approval_pending" ? 900 : 60),
            dismissalDate: apnsEvent == "end" ? timestamp : nil,
            attributesType: isStart ? "SessionActivityAttributes" : nil,
            attributes: isStart ? LiveActivityAttributes(
                sessionId: event.sessionId,
                sessionName: event.sessionName
            ) : nil
        ))
        return try JSONEncoder().encode(payload)
    }

    private static func loadAuthKeyPEM(
        environment: [String: String],
        fileLoader: @Sendable (String) throws -> String
    ) -> String? {
        if let pem = nonEmpty(environment[authKeyPEMEnvironmentKey]) {
            return pem
        }
        guard let path = nonEmpty(environment[authKeyPathEnvironmentKey]) else {
            return nil
        }
        return try? fileLoader(path)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

@MainActor
public enum DashboardSessionSpawnHooks {
    public typealias Handler = (AgentRef) -> Void

    public static let analyticsHookID = "app.analytics"
    public static let remoteSessionNotifierHookID = "app.remoteSessionNotifier"

    private static var multiplexers: [ObjectIdentifier: SessionDidSpawnHookMultiplexer] = [:]

    public static func setHandler(
        id: String,
        on dashboard: DashboardViewModel,
        handler: @escaping Handler
    ) {
        let dashboardID = ObjectIdentifier(dashboard)
        var multiplexer = multiplexers[dashboardID] ?? SessionDidSpawnHookMultiplexer(
            legacyHandler: dashboard.sessionDidSpawn
        )
        multiplexer.setHandler(id: id, handler)
        multiplexers[dashboardID] = multiplexer
        dashboard.sessionDidSpawn = { [weak dashboard] ref in
            guard let dashboard else { return }
            DashboardSessionSpawnHooks.dispatch(ref, on: dashboard)
        }
    }

    public static func clearHandlers(on dashboard: DashboardViewModel) {
        multiplexers.removeValue(forKey: ObjectIdentifier(dashboard))
        dashboard.sessionDidSpawn = nil
    }

    private static func dispatch(_ ref: AgentRef, on dashboard: DashboardViewModel) {
        multiplexers[ObjectIdentifier(dashboard)]?.dispatch(ref)
    }
}

@MainActor
struct SessionDidSpawnHookMultiplexer {
    typealias Handler = DashboardSessionSpawnHooks.Handler

    private let legacyHandler: Handler?
    private var orderedIDs: [String] = []
    private var handlers: [String: Handler] = [:]

    init(legacyHandler: Handler? = nil) {
        self.legacyHandler = legacyHandler
    }

    mutating func setHandler(id: String, _ handler: @escaping Handler) {
        if handlers[id] == nil {
            orderedIDs.append(id)
        }
        handlers[id] = handler
    }

    func dispatch(_ ref: AgentRef) {
        legacyHandler?(ref)
        for id in orderedIDs {
            handlers[id]?(ref)
        }
    }
}

private struct Payload: Encodable {
    let aps: APS
    let phlox: Phlox
}

private struct APS: Encodable {
    let alert: Alert
    let sound: String
    let threadID: String

    enum CodingKeys: String, CodingKey {
        case alert
        case sound
        case threadID = "thread-id"
    }
}

private struct Alert: Encodable {
    let title: String
    let body: String
}

private struct Phlox: Encodable {
    let v: Int
    let type: String
    let sessionId: String
    let sessionName: String
}

private struct LiveActivityPayload: Encodable {
    let aps: LiveActivityAPS
}

private struct LiveActivityAPS: Encodable {
    let timestamp: Int
    let event: String
    let contentState: LiveActivityContentState
    let staleDate: Int
    let dismissalDate: Int?
    let attributesType: String?
    let attributes: LiveActivityAttributes?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case event
        case contentState = "content-state"
        case staleDate = "stale-date"
        case dismissalDate = "dismissal-date"
        case attributesType = "attributes-type"
        case attributes
    }
}

private struct LiveActivityContentState: Encodable {
    let sessionId: String
    let sessionName: String
    let status: String
    let summary: String
}

private struct LiveActivityAttributes: Encodable {
    let sessionId: String
    let sessionName: String
}

private actor LiveActivityStartRegistry {
    private struct Key: Hashable {
        let sessionId: String
        let deviceToken: String
    }

    private var startedOrStarting: Set<Key> = []

    func reserve(sessionId: String, deviceToken: String) -> Bool {
        startedOrStarting.insert(.init(sessionId: sessionId, deviceToken: deviceToken)).inserted
    }

    func release(sessionId: String, deviceToken: String) {
        startedOrStarting.remove(.init(sessionId: sessionId, deviceToken: deviceToken))
    }
}
