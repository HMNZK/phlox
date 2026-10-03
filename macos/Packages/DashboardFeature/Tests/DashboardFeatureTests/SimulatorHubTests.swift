import AgentDomain
import Foundation
import IOSurface
import SimulatorBridgeKit
import TerminalUI
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Suite(.serialized) @MainActor
struct SimulatorHubTests {
    @Test func 切断時は一回だけ自動再接続し古い入力と通知を再送しない() async throws {
        let first = HubTransport(), second = HubTransport(), third = HubTransport(), fourth = HubTransport()
        let transports = [first, second, third, fourth]
        var attempts = 0
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection {
                defer { attempts += 1 }
                return transports[attempts]
            }
        }
        await hub.refresh()
        let session = SessionID()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        let connection = try #require(hub.connection(for: session))
        let old = connection.generation.current
        first.complete(udid: "端末A", generation: old)
        connection.sendKey(keyCode: 0, modifiers: 0, down: true)
        first.failed?("終了")
        #expect(attempts == 2)
        #expect(first.releases > 0)
        #expect(connection.sentKeyCodes.isEmpty)
        second.complete(udid: "端末A", generation: connection.generation.current)
        let current = try #require(connection.displayInfo)
        first.complete(udid: "端末A", generation: old)
        first.failed?("古い切断")
        #expect(connection.displayInfo === current)
        #expect(second.inputs == 0)
        second.failed?("再び終了")
        #expect(attempts == 3)
        third.failed?("復旧前に再び終了")
        #expect(attempts == 3)
        #expect(connection.canReconnect)
        #expect(connection.reason == "復旧前に再び終了")
        #expect(connection.displayInfo == nil)
        connection.reconnect()
        #expect(attempts == 4)
        fourth.complete(udid: "端末A", generation: connection.generation.current)
        #expect(connection.displayInfo != nil)
        #expect(third.inputs == 0)
        #expect(fourth.inputs == 0)
        hub.disconnectAll()
    }

    @Test(arguments: [false, true])
    func probeとattachの期限切れ後の応答は復旧した接続へ混ざらない(attaching: Bool) async throws {
        let first = HubTransport(), second = HubTransport()
        var attempts = 0
        let hub = SimulatorHub(catalog: HubCatalogFixture().catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection(timeout: 0.1) {
                attempts += 1
                return attempts == 1 ? first : second
            }
        }
        await hub.refresh()
        let session = SessionID()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        let connection = try #require(hub.connection(for: session))
        let old = connection.generation.current
        if attaching {
            first.probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
                                                       helperBuild: "検証", xcodeBuild: "17C52",
                                                       coreSimulatorLoaded: true, simulatorKitLoaded: true))
        }
        try await waitUntil { attempts == 2 }
        #expect(first.invalidations == 1)
        second.complete(udid: "端末A", generation: connection.generation.current)
        let current = try #require(connection.displayInfo)
        first.complete(udid: "端末A", generation: old)
        #expect(connection.displayInfo === current)
        #expect(connection.reason == nil)
        #expect(first.attached.count == (attaching ? 1 : 0))
        #expect(second.attached == ["端末A"])
        hub.disconnectAll()
    }

    @Test func 画面の更新診断は静止中だけ表示し古い世代の観測で解除しない() async throws {
        let fake = HubTransport()
        let connection = SimulatorDisplayConnection { fake }
        connection.policy = .verified
        connection.configure(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", triesUnverified: false)
        connection.attach(udid: "端末A")
        fake.complete(udid: "端末A", generation: connection.generation.current)
        let info = try #require(connection.displayInfo)
        let start = try #require(connection.lastFrameUpdate)
        #expect(!connection.hasStaleFrame(at: start.addingTimeInterval(4.9)))
        #expect(connection.hasStaleFrame(at: start.addingTimeInterval(5)))
        connection.observeFrame(info, seed: IOSurfaceGetSeed(info.surface), at: start.addingTimeInterval(6))
        #expect(connection.hasStaleFrame(at: start.addingTimeInterval(6)))
        connection.observeFrame(info, seed: IOSurfaceGetSeed(info.surface) &+ 1, at: start.addingTimeInterval(7))
        #expect(!connection.hasStaleFrame(at: start.addingTimeInterval(7)))
        connection.attach(udid: "端末A")
        fake.complete(udid: "端末A", generation: connection.generation.current)
        let recovered = connection.lastFrameUpdate
        connection.observeFrame(info, seed: 99, at: start.addingTimeInterval(20))
        #expect(connection.lastFrameUpdate == recovered)
        connection.disconnect()
        #expect(!connection.hasStaleFrame(at: start.addingTimeInterval(100)))
    }

    @Test func 停止確認後に選択を変えても確認した端末を停止する() async throws {
        let fixture = HubCatalogFixture(states: ["端末A": "Booted", "端末B": "Booted"])
        let hub = SimulatorHub(catalog: fixture.catalog())
        await hub.refresh()
        let session = SessionID()
        hub.select(udid: "端末A", for: session)
        let requested = try #require(hub.selectedDevice(for: session)?.udid)
        hub.select(udid: "端末B", for: session)
        await hub.shutdown(udid: requested)
        #expect(await fixture.mutations() == [["shutdown", requested]])
        hub.disconnectAll()
    }

    @Test func 起動処理中の端末へ重ねて起動を送らない() async {
        let fixture = HubCatalogFixture(states: ["端末A": "Booting"])
        let hub = SimulatorHub(catalog: fixture.catalog())
        await hub.refresh()
        await hub.boot(for: SessionID())
        #expect(await fixture.mutations().isEmpty)
        hub.disconnectAll()
    }

    @Test func 複数ウィンドウの表示を端末ごとに共有し最後の非表示で取得を止める() async throws {
        let fixture = HubCatalogFixture()
        let fake = HubTransport()
        var creations = 0
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            creations += 1
            return SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let first = SessionID(), second = SessionID()
        let left = UUID(), right = UUID(), otherWindow = UUID()
        hub.setVisible(true, displayID: left, sessionID: first)
        hub.setVisible(true, displayID: right, sessionID: first)
        hub.setVisible(true, displayID: otherWindow, sessionID: second)
        #expect(creations == 1)
        #expect(hub.connection(for: first) === hub.connection(for: second))
        let connection = try #require(hub.connection(for: first))
        fake.complete(udid: "端末A", generation: connection.generation.current)
        #expect(fake.attached == ["端末A"])
        hub.setVisible(false, displayID: left, sessionID: first)
        hub.setVisible(false, displayID: right, sessionID: first)
        #expect(fake.detached.isEmpty)
        hub.setVisible(false, displayID: otherWindow, sessionID: second)
        #expect(fake.detached == ["端末A"])
        #expect(fake.invalidations == 1)
        #expect(hub.connection(for: first) == nil)
        #expect(await fixture.mutations().isEmpty)
    }

    @Test func 端末切替とセッション削除と終了は端末を停止しない() async throws {
        let fixture = HubCatalogFixture(states: ["端末A": "Booted", "端末B": "Booted"])
        let first = HubTransport(), second = HubTransport()
        var transports = [first, second]
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            let fake = transports.removeFirst()
            return SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        let old = try #require(hub.connection(for: session))
        first.complete(udid: "端末A", generation: old.generation.current)
        old.sendKey(keyCode: 0, modifiers: 0, down: true)
        hub.select(udid: "端末B", for: session)
        #expect(first.releases > 0)
        #expect(old.sentKeyCodes.isEmpty)
        #expect(first.detached == ["端末A"])
        #expect(hub.selectedDevice(for: session)?.udid == "端末B")
        hub.removeSession(session)
        #expect(second.invalidations == 1)
        hub.disconnectAll()
        #expect(await fixture.mutations().isEmpty)
    }

    @Test func 外部起動と停止を反映し一覧の並び替えでも選択を保持する() async throws {
        let fixture = HubCatalogFixture(states: ["端末A": "Shutdown", "端末B": "Shutdown"])
        let fake = HubTransport()
        var creations = 0
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 0.01) {
            creations += 1
            return SimulatorDisplayConnection { fake }
        }
        let session = SessionID()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        try await waitUntil { hub.devices.count == 2 }
        #expect(hub.selectedDevice(for: session)?.udid == "端末A")
        #expect(creations == 0)
        await fixture.setState("Booted", udid: "端末B")
        try await waitUntil { hub.devices.first?.udid == "端末B" }
        #expect(hub.selectedDevice(for: session)?.udid == "端末A")
        await fixture.setState("Booted", udid: "端末A")
        try await waitUntil { creations == 1 }
        await fixture.setState("Shutdown", udid: "端末A")
        try await waitUntil { fake.invalidations == 1 }
        #expect(await fixture.mutations().isEmpty)
        hub.disconnectAll()
    }

    @Test func 起動と停止とスクリーンショットは明示操作時だけ実行する() async {
        let fixture = HubCatalogFixture(states: ["端末A": "Shutdown"])
        let fake = HubTransport()
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection { fake }
        }
        await hub.refresh()
        let session = SessionID()
        hub.setVisible(true, displayID: UUID(), sessionID: session)
        await hub.boot(for: session)
        #expect(hub.selectedDevice(for: session)?.isBooted == true)
        fake.failed?("補助プロセスが終了しました")
        let destination = URL(fileURLWithPath: "/検証/画面.png")
        #expect(await hub.screenshot(for: session, destination: destination))
        await hub.shutdown(udid: "端末A")
        #expect(hub.selectedDevice(for: session)?.isBooted == false)
        #expect(await fixture.mutations() == [
            ["boot", "端末A"], ["io", "端末A", "screenshot", destination.path], ["shutdown", "端末A"],
        ])
        hub.disconnectAll()
    }

    @Test(arguments: [false, true])
    func 補助プロセスの終了と期限切れ後もセッションとターミナルの入出力を続ける(timeout: Bool) async throws {
        let fixture = HubCatalogFixture()
        let fake = HubTransport(), retry = HubTransport()
        var attempts = 0
        let hub = SimulatorHub(catalog: fixture.catalog(), refreshInterval: 60) {
            SimulatorDisplayConnection(timeout: timeout ? 0.02 : 5) {
                attempts += 1
                return attempts == 1 ? fake : retry
            }
        }
        let sessionID = SessionID()
        let sessionPTY = MockPTYManager()
        let (events, continuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let session = SessionViewModel(
            id: sessionID, ptyManager: sessionPTY, hookEvents: events,
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: .init(command: "/bin/sh", args: [], env: ["TERM": "xterm-256color"],
                                workingDirectory: "/tmp", kind: .claudeCode, statusBootstrap: .viaHook)
        )
        let terminalPTY = MockPTYManager()
        let terminal = TerminalPanelSession(controller: UserTerminalController(
            pty: terminalPTY, shellPath: "/bin/sh", workingDirectory: "/tmp",
            environment: ["TERM": "xterm-256color"]
        ))
        await session.start()
        await session.spawnEager()
        continuation.yield((sessionID, .sessionStart))
        await terminal.ensureStarted()
        try await waitUntil {
            sessionPTY.spawnCalls.count == 1 && session.status == .idle && terminal.controller.isRunning
        }
        await hub.refresh()
        hub.setVisible(true, displayID: UUID(), sessionID: sessionID)
        let connection = try #require(hub.connection(for: sessionID))
        let generation = connection.generation.current
        if !timeout {
            fake.complete(udid: "端末A", generation: generation)
            fake.failed?("補助プロセスが終了しました")
            retry.failed?("再接続した補助プロセスも終了しました")
        }
        try await waitUntil { connection.reason != nil }
        #expect(fake.invalidations == 1)
        #expect(retry.invalidations == 1)
        #expect(attempts == 2)
        #expect(connection.canReconnect)
        #expect(connection.displayInfo == nil)
        fake.complete(udid: "端末A", generation: generation)
        #expect(connection.displayInfo == nil)
        continuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
        try await waitUntil { session.status == .running }
        await session.sendInput(Data("継続\r".utf8))
        #expect(sessionPTY.writtenCalls.last?.0 == Data("継続\r".utf8))
        sessionPTY.emitOutput(for: sessionID, data: Data("SESSION_CONTINUES\r\n".utf8))
        try await waitUntil { session.terminalCoordinator.visibleText().contains("SESSION_CONTINUES") }
        continuation.yield((sessionID, .stop(turnId: nil)))
        try await waitUntil { session.status == .idle }
        let terminalID = try #require(terminal.controller.sessionID)
        terminal.terminalCoordinator.onInput(Data("echo continues\r".utf8))
        try await waitUntil { terminalPTY.writtenCalls.count == 1 }
        #expect(terminalPTY.writtenCalls.first?.0 == Data("echo continues\r".utf8))
        terminalPTY.emitOutput(for: terminalID, data: Data("TERMINAL_CONTINUES\r\n".utf8))
        try await waitUntil { terminal.terminalCoordinator.visibleText().contains("TERMINAL_CONTINUES") }
        #expect(sessionPTY.killedIDs.isEmpty)
        #expect(terminalPTY.killedIDs.isEmpty)
        hub.disconnectAll()
        await session.kill()
        continuation.finish()
        await terminal.controller.shutdown()
    }
}

actor HubCatalogFixture {
    private var states: [String: String]
    private var commands: [[String]] = []

    init(states: [String: String] = ["端末A": "Booted"]) { self.states = states }

    nonisolated func catalog() -> SimulatorCatalog {
        SimulatorCatalog { arguments, _ in try await self.run(arguments) }
    }

    func setState(_ state: String, udid: String) { states[udid] = state }
    func mutations() -> [[String]] { commands.filter { $0.first != "list" } }

    private func run(_ arguments: [String]) throws -> SimulatorCatalog.CommandResult {
        commands.append(arguments)
        if arguments.first == "boot" { states[arguments[1]] = "Booted" }
        if arguments.first == "shutdown" { states[arguments[1]] = "Shutdown" }
        let devices = states.map { udid, state in
            ["udid": udid, "name": udid, "state": state, "isAvailable": true] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "devices": ["com.apple.CoreSimulator.SimRuntime.iOS-26-2": devices],
        ])
        return .init(status: 0, output: data, errorOutput: Data())
    }
}

@Suite @MainActor struct SimulatorDisplayCountTests {
    @Test func 同じ端末を表示する登録だけを数える() async {
        let hub = SimulatorHub(catalog: HubCatalogFixture(states: ["端末A": "Shutdown", "端末B": "Shutdown"]).catalog())
        defer { hub.disconnectAll() }
        await hub.refresh()
        let first = SessionID(), second = SessionID()
        let firstDisplay = UUID(), secondDisplay = UUID()
        hub.select(udid: "端末A", for: first)
        hub.select(udid: "端末A", for: second)
        hub.setVisible(true, displayID: firstDisplay, sessionID: first)
        hub.setVisible(true, displayID: secondDisplay, sessionID: second)
        #expect(hub.displayCount(udid: "端末A") == 2)
        #expect(hub.displayCount(udid: "端末B") == 0)
        hub.select(udid: "端末B", for: second)
        #expect(hub.displayCount(udid: "端末A") == 1)
        #expect(hub.displayCount(udid: "端末B") == 1)
        hub.removeDisplay(firstDisplay)
        #expect(hub.displayCount(udid: "端末A") == 0)
        hub.setVisible(false, displayID: secondDisplay, sessionID: second)
        #expect(hub.displayCount(udid: "端末B") == 0)
    }
}

@MainActor final class HubTransport: SimulatorDisplayTransport {
    var failed: (@MainActor (String) -> Void)?
    var probeReply: (@MainActor (SimulatorBridgeCapability) -> Void)?
    var attachReply: (@MainActor (SimulatorDisplayInfo?, NSError?) -> Void)?
    var attached: [String] = []
    var detached: [String] = []
    var invalidations = 0
    var releases = 0
    var inputs = 0
    var buttons: [Int] = []

    func complete(udid: String, generation: Int) {
        probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
                                              helperBuild: "検証", xcodeBuild: "17C52",
                                              coreSimulatorLoaded: true, simulatorKitLoaded: true))
        guard let surface = IOSurface(properties: [.width: 4, .height: 8, .bytesPerElement: 4,
                                                  .bytesPerRow: 16, .allocSize: 128, .pixelFormat: 0x42475241]) else {
            Issue.record("検証用の画面を作成できませんでした")
            return
        }
        attachReply?(SimulatorDisplayInfo(udid: udid, connectionGeneration: generation, displayGeneration: 1,
                                          surface: surface, pixelWidth: 4, pixelHeight: 8,
                                          orientation: .portrait, surfaceIsRotated: false, pixelFormat: 0x42475241), nil)
    }

    func resume(surfaceChanged: @escaping @MainActor (SimulatorDisplayInfo) -> Void,
                failed: @escaping @MainActor (String) -> Void) { self.failed = failed }
    func probe(reply: @escaping @MainActor (SimulatorBridgeCapability) -> Void) { probeReply = reply }
    func attach(udid: String, generation: Int,
                reply: @escaping @MainActor (SimulatorDisplayInfo?, NSError?) -> Void) {
        attached.append(udid)
        attachReply = reply
    }
    func detach(udid: String) { detached.append(udid) }
    func sendTouch(udid: String, phase: Int, x: Double, y: Double) { inputs += 1 }
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int) { inputs += 1 }
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool) { inputs += 1 }
    func sendButton(udid: String, button: Int) { inputs += 1; buttons.append(button) }
    func releaseAll(udid: String) { releases += 1 }
    func invalidate() { invalidations += 1 }
}
