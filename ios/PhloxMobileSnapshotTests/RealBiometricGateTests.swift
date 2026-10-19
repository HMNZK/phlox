import Foundation
import SwiftUI
import UIKit
import Testing
import PhloxCore
import PhloxSecurity
@testable import Features
@testable import PhloxMobile

/// 実OS認証は専用Simulatorと親CUAで行う。既存fixtureと製品は変更しない。
@MainActor
@Suite(.serialized)
struct RealBiometricGateTests {
    @Test func realOSCancelThenMatchingFaceUnlocksTheActualRoot() async throws {
        try #require(bioEnvironment("PHLOX_REAL_BIOMETRIC_PROBE") == "1", "Explicit dedicated-Simulator opt-in is required")
        try #require(UITestingSupport.isEnabled)
        let run = try BioRun()
        let probe = BioAuthenticator()
        let api = BioAPI()
        let failure = ConnectFailure(title: "認証後に戻る接続情報", message: "接続先と失敗情報は保持されています")
        let model = AppModel(authState: .locked, hasConnectionConfig: true, reachability: .online,
                             isConnecting: true, connectFailure: failure)
        let environment = AppEnvironment(
            tokenStore: InMemoryTokenStore(), authenticator: probe, apiClient: api,
            reachability: StubReachability(.online), sessionRepository: StubSessionRepository(states: [.empty]),
            auditLog: InMemoryAuditLog()
        )
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let host = UIHostingController(rootView: AppRoot(pushCoordinator: PushCoordinator(), model: model).environment(environment))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        do {
            try await bioWait { await probe.snapshot.pendingCount == 1 }
            #expect(model.state == .locked && !model.showsConnectingOverlay)
            let cancellation = try await run.waitForAck(
                step: "os-cancel", state: await probe.snapshot,
                instruction: "実Face ID認証画面なら撮影してOS Cancel。初回利用許可なら許可せず取消しpermissionBlockedでack。実生体/パスコードは設定しない。"
            )
            try await bioWait { await probe.snapshot.pendingCount == 0 }
            let cancelled = await probe.snapshot
            #expect(cancelled.callCount == 1 && cancelled.completedCount == 1 && cancelled.latestSuccess != true)
            #expect(model.authState == .locked && model.isConnecting && model.connectFailure == failure)
            if cancellation == "permissionBlocked" {
                try await run.record(status: "blocked", probe: probe, model: model, api: api)
                throw BioProbeError.blockedByInitialPermission
            }
            try #require(cancellation == "authenticationCancelled")
            try await bioWait { bioLabels(window).contains(where: { $0.contains("認証できませんでした") }) }
            #expect(!bioLabels(window).contains(where: { $0.contains(failure.title) }))
            let matching = try await run.waitForAck(
                step: "retry-match", state: await probe.snapshot,
                instruction: "アプリ『もう一度 Face ID』を1回押す。実OS認証画面を撮影し、専用SimulatorのFeatures > Face ID > Matching Faceを送ってauthenticationMatchedでack。利用許可が出たら許可せず取消しpermissionBlocked。"
            )
            try await bioWait { await probe.snapshot.pendingCount == 0 }
            if matching == "permissionBlocked" {
                try await run.record(status: "blocked", probe: probe, model: model, api: api)
                throw BioProbeError.blockedByInitialPermission
            }
            try #require(matching == "authenticationMatched")
            try await bioWait { model.authState == .unlocked }
            let matched = await probe.snapshot
            #expect(matched.callCount == 2 && matched.completedCount == 2 && matched.latestSuccess == true)
            #expect(model.isConnecting && model.connectFailure == failure && model.showsConnectingOverlay)
            try await bioWait { bioLabels(window).contains(where: { $0.contains(failure.title) }) }
            #expect(await api.writeCalls == 0)
            try await run.record(status: "passed", probe: probe, model: model, api: api)
        } catch {
            while await probe.snapshot.pendingCount > 0 {
                do {
                    let outcome = try await run.waitForAck(
                        step: "cleanup-cancel", state: await probe.snapshot,
                        instruction: "検査の後片付け。実OS認証画面を撮影してCancelし、authenticationCancelledでack。評価が終わるまでhostを閉じない。"
                    )
                    try #require(outcome == "authenticationCancelled" || outcome == "permissionBlocked")
                    try await bioWait { await probe.snapshot.pendingCount == 0 }
                } catch {
                    Issue.record(error)
                    do {
                        try await run.record(status: "cleanup-still-pending", probe: probe, model: model, api: api)
                    } catch {
                        Issue.record(error)
                    }
                    // OS評価が残る間は新nonceでCancelを再要求し、hostを先に閉じない。
                }
            }
            try await run.record(status: "failed-or-blocked", probe: probe, model: model, api: api)
            throw error
        }
    }
}

private struct BioState: Sendable, Codable {
    let callCount: Int
    let completedCount: Int
    let pendingCount: Int
    let latestSuccess: Bool?
    let events: [String]
}

/// 成否を差し替えず、本物BiometricGateの開始・完了だけを記録する。
private actor BioAuthenticator: Authenticating {
    private var calls = 0
    private var completed = 0
    private var pending = 0
    private var latestSuccess: Bool?
    private var events: [String] = []
    var snapshot: BioState { BioState(callCount: calls, completedCount: completed, pendingCount: pending, latestSuccess: latestSuccess, events: events) }

    func authenticate(reason: String) async throws -> Bool {
        calls += 1
        pending += 1
        events.append("evaluatePolicy started")
        defer { pending -= 1; completed += 1 }
        do {
            let result = try await BiometricGate().authenticate(reason: reason)
            latestSuccess = result
            events.append("evaluatePolicy returned \(result)")
            return result
        } catch {
            latestSuccess = false
            events.append("evaluatePolicy threw \(String(describing: error))")
            throw error
        }
    }
}

private actor BioAPI: PhloxAPI {
    private(set) var writeCalls = 0
    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session { writeCalls += 1; throw PhloxError.unsupported }
    func waitUntilReady(sessionID: String) async throws -> Bool { false }
    func send(_ request: SendRequest) async throws -> SendResult { writeCalls += 1; throw PhloxError.unsupported }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws { writeCalls += 1; throw PhloxError.unsupported }
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws { writeCalls += 1; throw PhloxError.unsupported }
}

@MainActor
private struct BioRun {
    private let scene = "RealBiometricGate"
    private let directory: URL
    init() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = bioEnvironment("PHLOX_REAL_BIOMETRIC_OUTPUT") ?? root.appendingPathComponent(".verification/ios-redesign-stage8b/remaining/real-biometric").path
        directory = URL(fileURLWithPath: path).appendingPathComponent("ios\(UIDevice.current.systemVersion)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func waitForAck(step: String, state: BioState, instruction: String) async throws -> String {
        let nonce = UUID().uuidString
        let ack = directory.appendingPathComponent("\(step)-\(nonce)-ack.json")
        let requestedAt = Date().timeIntervalSince1970
        let pid = ProcessInfo.processInfo.processIdentifier
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        let stateObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        let payload: [String: Any] = [
            "scene": scene, "step": step, "phase": "awaitingCUA", "nonce": nonce,
            "pid": pid, "udid": udid, "requestedAt": requestedAt, "ackFile": ack.path,
            "instruction": instruction, "state": stateObject,
            "windowTitle": bioEnvironment("PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE") ?? "unknown",
            "session": "ios_root_transitions", "executable": CommandLine.arguments.first ?? "unknown",
            "output": directory.path,
        ]
        let ready = directory.appendingPathComponent("\(step)-ready.json")
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: ready)
        print("real biometric awaitingCUA: \(ready.path)")
        let deadline = ContinuousClock.now + .seconds(180)
        while !FileManager.default.fileExists(atPath: ack.path), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        try #require(FileManager.default.fileExists(atPath: ack.path), "Real OS authentication needs a CUA acknowledgement")
        let reply = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ack)) as? [String: Any])
        try #require(reply["nonce"] as? String == nonce && reply["scene"] as? String == scene && reply["step"] as? String == step)
        try #require((reply["pid"] as? NSNumber)?.int32Value == pid && reply["udid"] as? String == udid)
        try #require(reply["phase"] as? String == "reviewed" && reply["confirmed"] as? Bool == true)
        let capturedAt = try #require(reply["capturedAt"] as? Double)
        try #require(capturedAt >= requestedAt && capturedAt <= Date().timeIntervalSince1970 + 5)
        let screenshot = try #require(reply["screenshotFile"] as? String)
        try #require(screenshot.hasPrefix("/") && FileManager.default.fileExists(atPath: screenshot), "A real external OS screenshot is required")
        let outcome = try #require(reply["outcome"] as? String)
        try JSONSerialization.data(withJSONObject: reply, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("\(step)-reviewed.json"))
        return outcome
    }
    func record(status: String, probe: BioAuthenticator, model: AppModel, api: BioAPI) async throws {
        let payload: [String: Any] = [
            "status": status, "authentication": try JSONSerialization.jsonObject(with: JSONEncoder().encode(await probe.snapshot)),
            "authState": String(describing: model.authState), "isConnecting": model.isConnecting,
            "showsConnectingOverlay": model.showsConnectingOverlay, "apiWriteCalls": await api.writeCalls,
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(status)-result.json"))
    }
}

private func bioEnvironment(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_\(key)"]
}

@MainActor
private func bioWait(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    repeat {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(30))
    } while ContinuousClock.now < deadline
    throw BioProbeError.stateTimeout
}

@MainActor
private func bioLabels(_ window: UIWindow) -> [String] {
    var labels: [String] = []
    var visited: Set<ObjectIdentifier> = []
    func visit(_ object: NSObject) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        if let label = object.accessibilityLabel { labels.append(label) }
        for child in object.accessibilityElements ?? [] { if let child = child as? NSObject { visit(child) } }
        let count = object.accessibilityElementCount()
        if count != NSNotFound && count > 0 {
            for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) } }
        }
        if let view = object as? UIView { for child in view.subviews where !child.isHidden { visit(child) } }
    }
    visit(window)
    return labels
}

private enum BioProbeError: Error { case blockedByInitialPermission, stateTimeout }
