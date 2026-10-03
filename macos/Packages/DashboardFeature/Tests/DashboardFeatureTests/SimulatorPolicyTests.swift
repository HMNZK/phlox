import AgentDomain
import Foundation
import AppKit
import SimulatorBridgeKit
import Testing
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct SimulatorPolicyTests {
    @Test func 未確認の例外は同じ表示で端末を切り替えると引き継がない() async throws {
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture(states: ["端末A": "Booted", "端末B": "Booted"]).catalog(), refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            connection.policy = SimulatorPolicy(entries: [])
            return connection
        }
        defer { hub.disconnectAll() }
        await hub.refresh()
        let session = SessionID(), display = UUID()
        hub.select(udid: "端末A", for: session)
        hub.setVisible(true, displayID: display, sessionID: session)
        let a = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: a.generation.current)
        hub.tryUnverified(displayID: display)
        fake.complete(udid: "端末A", generation: a.generation.current)
        #expect(hub.support(for: session, displayID: display) == .unverified)
        hub.select(udid: "端末B", for: session)
        let b = try #require(hub.connection(for: session))
        fake.complete(udid: "端末B", generation: b.generation.current)
        #expect(hub.support(for: session, displayID: display) == .unsupported)
        #expect(b.displayInfo == nil)
    }

    @Test func 未確認で実行中の表示は手動再接続中もそのセッションだけに残る() async throws {
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            connection.policy = SimulatorPolicy(entries: [])
            return connection
        }
        defer { hub.disconnectAll() }
        await hub.refresh()
        let session = SessionID(), otherSession = SessionID(), display = UUID(), other = UUID()
        hub.setVisible(true, displayID: display, sessionID: session)
        hub.setVisible(true, displayID: other, sessionID: otherSession)
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        hub.tryUnverified(displayID: display)
        fake.complete(udid: "端末A", generation: connection.generation.current)
        fake.failed?("切断")
        fake.failed?("再接続失敗")
        connection.reconnect()
        #expect(connection.capability == nil)
        #expect(connection.displayInfo == nil)
        #expect(hub.support(for: session, displayID: display) == .unverified)
        #expect(hub.support(for: otherSession, displayID: other) == .unsupported)
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(connection.displayInfo != nil)
        #expect(hub.support(for: session, displayID: display) == .unverified)
    }

    @Test func 許可リストは確認済みの組だけを許可する() {
        let policy = SimulatorPolicy.verified
        #expect(policy.entries.count == 1)
        #expect(policy.support(xcodeBuild: "17C52", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", triesUnverified: false) == .supported)
        #expect(policy.support(xcodeBuild: "17C53", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", triesUnverified: false) == .unsupported)
        #expect(policy.support(xcodeBuild: "17C52", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-3", triesUnverified: false) == .unsupported)
    }

    @Test func 表示のみ対応では例外を押しても入力と画面へのフォーカスを許可しない() async throws {
        let fake = HubTransport()
        let connection = SimulatorDisplayConnection { fake }
        connection.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "17C52", runtimeIdentifier: "表示のみ", supportsInput: false)])
        connection.configure(runtimeIdentifier: "表示のみ", triesUnverified: true)
        connection.attach(udid: "端末A")
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(connection.support == .displayOnly)
        #expect(connection.displayInfo != nil)
        connection.sendTouch(phase: 0, point: .zero)
        connection.sendScroll(dx: 1, dy: 1, point: .zero)
        connection.sendKey(keyCode: 0, modifiers: 0, down: true)
        connection.sendHome()
        let screen = SimulatorScreenNSView()
        screen.connection = connection
        screen.update(connection.displayInfo)
        #expect(!screen.acceptsFirstResponder)
        #expect(fake.inputs == 0)
        #expect(connection.sentKeyCodes.isEmpty)
        connection.disconnect()
    }

    @Test func 未確認の例外は同じセッションの表示で共有し別セッションへ広がらず閉じると消える() async throws {
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            connection.policy = SimulatorPolicy(entries: [])
            return connection
        }
        await hub.refresh()
        let session = SessionID(), other = SessionID()
        let first = UUID(), second = UUID(), third = UUID()
        hub.setVisible(true, displayID: first, sessionID: session)
        hub.setVisible(true, displayID: second, sessionID: session)
        hub.setVisible(true, displayID: third, sessionID: other)
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(fake.attached.isEmpty)
        hub.tryUnverified(displayID: first)
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(connection.displayInfo != nil)
        #expect(fake.attached == ["端末A"])
        #expect(hub.support(for: session, displayID: first) == .unverified)
        #expect(hub.support(for: session, displayID: second) == .unverified)
        #expect(hub.support(for: other, displayID: third) == .unsupported)
        hub.setVisible(false, displayID: first, sessionID: session)
        #expect(connection.displayInfo != nil)
        hub.setVisible(true, displayID: first, sessionID: session)
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(connection.displayInfo != nil)
        hub.removeDisplay(first)
        #expect(connection.displayInfo != nil)
        #expect(hub.support(for: session, displayID: second) == .unverified)
        hub.removeSession(session)
        #expect(connection.displayInfo == nil)
        #expect(hub.support(for: session, displayID: first) == .unsupported)
        hub.disconnectAll()
    }

    @Test(arguments: [false, true])
    func 未確認の例外は読み込み失敗と版不一致を解除しない(versionMismatch: Bool) async throws {
        let fake = HubTransport()
        var attempts = 0
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { attempts += 1; return fake }
        }
        await hub.refresh()
        let session = SessionID(), display = UUID()
        hub.setVisible(true, displayID: display, sessionID: session)
        fake.probeReply?(SimulatorBridgeCapability(protocolVersion: versionMismatch ? 999 : SimulatorBridgeInterfaces.protocolVersion,
                                                  helperBuild: "検証", xcodeBuild: "未確認",
                                                  coreSimulatorLoaded: versionMismatch, simulatorKitLoaded: versionMismatch))
        hub.tryUnverified(displayID: display)
        let connection = try #require(hub.connection(for: session))
        #expect(connection.blocksRetry)
        #expect(hub.support(for: session, displayID: display) == .unsupported)
        #expect(!connection.canReconnect)
        #expect(connection.reason != nil)
        #expect(connection.displayInfo == nil)
        #expect(fake.attached.isEmpty)
        #expect(attempts == 1)
        connection.reconnect()
        #expect(attempts == 1)
        hub.disconnectAll()
    }

    @Test func 未確認で実行中に再接続が版不一致になると実行中扱いをやめる() async throws {
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            let c = SimulatorDisplayConnection { fake }; c.policy = SimulatorPolicy(entries: []); return c
        }
        defer { hub.disconnectAll() }
        await hub.refresh()
        let session = SessionID(), display = UUID()
        hub.setVisible(true, displayID: display, sessionID: session)
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        hub.tryUnverified(displayID: display)
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(hub.support(for: session, displayID: display) == .unverified)
        fake.failed?("補助プロセスが終了しました")
        fake.probeReply?(SimulatorBridgeCapability(protocolVersion: 999, helperBuild: "検証", xcodeBuild: "17C52",
                                                  coreSimulatorLoaded: true, simulatorKitLoaded: true))
        #expect(connection.blocksRetry)
        #expect(hub.support(for: session, displayID: display) == .unsupported)
        #expect(connection.displayInfo == nil)
    }

    @Test func 未確認の例外はビュー再作成後も同じタブで維持し閉じると解除する() async throws {
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            connection.policy = SimulatorPolicy(entries: [])
            return connection
        }
        defer { hub.disconnectAll() }
        await hub.refresh()
        let session = SessionID(), first = UUID(), rebuilt = UUID()
        hub.setVisible(true, displayID: first, sessionID: session)
        let original = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: original.generation.current)
        hub.tryUnverified(displayID: first)
        fake.complete(udid: "端末A", generation: original.generation.current)
        #expect(original.displayInfo != nil)
        hub.removeDisplay(first)
        #expect(hub.connection(for: session) == nil)
        hub.setVisible(true, displayID: rebuilt, sessionID: session)
        let connection = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(connection.displayInfo != nil)
        #expect(hub.support(for: session, displayID: rebuilt) == .unverified)
        hub.removeSession(session)
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        let reopened = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: reopened.generation.current)
        #expect(reopened.displayInfo == nil)
        #expect(reopened.support == .unsupported)
    }

    @Test func 未確認の例外は切替先から元の端末へ戻しても終了後も復活しない() async throws {
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: HubCatalogFixture(states: ["端末A": "Booted", "端末B": "Booted"]).catalog(), refreshInterval: 60) {
            let connection = SimulatorDisplayConnection { fake }
            connection.policy = SimulatorPolicy(entries: [])
            return connection
        }
        defer { hub.disconnectAll() }
        await hub.refresh()
        let session = SessionID(), display = UUID()
        hub.select(udid: "端末A", for: session)
        hub.setVisible(true, displayID: display, sessionID: session)
        hub.tryUnverified(displayID: display)
        let allowed = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: allowed.generation.current)
        hub.select(udid: "端末B", for: session)
        hub.select(udid: "端末A", for: session)
        let returned = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: returned.generation.current)
        #expect(returned.displayInfo == nil)
        #expect(hub.support(for: session, displayID: display) == .unsupported)
        hub.tryUnverified(displayID: display)
        fake.complete(udid: "端末A", generation: returned.generation.current)
        #expect(returned.displayInfo != nil)
        hub.disconnectAll()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        let restarted = try #require(hub.connection(for: session))
        fake.complete(udid: "端末A", generation: restarted.generation.current)
        #expect(restarted.displayInfo == nil)
    }

    @Test func 開く操作と再度開く操作は帯へのフォーカスだけを要求する() async {
        let fixture = HubCatalogFixture(states: ["端末A": "Shutdown"])
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID(), other = SessionID()
        #expect(hub.menuFocusRevision(for: session) == 0)
        hub.requestMenuFocus(for: session)
        #expect(hub.menuFocusRevision(for: session) == 1)
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        hub.requestMenuFocus(for: session)
        #expect(hub.menuFocusRevision(for: session) == 2)
        #expect(hub.menuFocusRevision(for: other) == 0)
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
        hub.disconnectAll()
    }

    @Test(arguments: [false, true])
    func タブを開いて表示しても停止端末を起動せず入力しない(booted: Bool) async throws {
        let fixture = HubCatalogFixture(states: ["端末A": booted ? "Booted" : "Shutdown"])
        let fake = HubTransport()
        var creations = 0
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            creations += 1
            return SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        if booted {
            let connection = try #require(hub.connection(for: session))
            fake.complete(udid: "端末A", generation: connection.generation.current)
        }
        #expect(creations == (booted ? 1 : 0))
        #expect(fake.inputs == 0)
        #expect(await fixture.mutations().isEmpty)
        hub.disconnectAll()
    }
}
