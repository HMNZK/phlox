import AppKit
import Foundation
import IOSurface
import Observation
import Testing
import SimulatorBridgeKit
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct SimulatorDisplayConnectionTests {
    #if DEBUG
    @Test(arguments: ["com.apple.CoreSimulator.SimRuntime.iOS-26-2", "未登録ランタイム", "表示のみランタイム"])
    func 明示的な互換性検査は登録状態によらず未確認として入力を検査する(runtime: String) throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        connection.policy = runtime == "表示のみランタイム"
            ? SimulatorPolicy(entries: [.init(xcodeBuild: "17C52", runtimeIdentifier: runtime, supportsInput: false)])
            : .verified
        connection.configureForCompatibilityCheck(runtime: runtime)
        connection.attach(udid: "端末")
        fake.probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
            helperBuild: "検証", xcodeBuild: "17C52", coreSimulatorLoaded: true, simulatorKitLoaded: true))
        #expect(connection.policy?.entries.isEmpty == true)
        #expect(connection.support == .unverified)
        #expect(fake.attachedUDID == "端末")
        fake.attachReply?(try info(connection.generation.current), nil)
        #expect(connection.inputEnabled)
        connection.disconnect()
    }

    @Test func 同じ未確認指定で接続中でも互換性検査は表示のみ方針を置き換える() throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        connection.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "検証", runtimeIdentifier: "検証ランタイム", supportsInput: false)])
        connection.configure(runtimeIdentifier: "検証ランタイム", triesUnverified: true)
        connection.attach(udid: "端末")
        fake.probeReply?(capability())
        fake.attachReply?(try info(connection.generation.current), nil)
        #expect(connection.support == .displayOnly)
        #expect(!connection.inputEnabled)
        connection.configureForCompatibilityCheck(runtime: "検証ランタイム")
        #expect(connection.support == .unverified)
        fake.probeReply?(capability())
        fake.attachReply?(try info(connection.generation.current), nil)
        #expect(connection.inputEnabled)
        connection.disconnect()
    }

    @Test(arguments: ["版不一致", "部品読み込み失敗"])
    func 明示的な互換性検査でも版不一致と部品読み込み失敗は解除しない(failure: String) {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        connection.configureForCompatibilityCheck(runtime: "未登録ランタイム")
        connection.attach(udid: "端末")
        fake.probeReply?(capability(version: failure == "版不一致" ? 999 : SimulatorBridgeInterfaces.protocolVersion,
                                    loaded: failure != "部品読み込み失敗"))
        #expect(connection.blocksRetry)
        #expect(fake.attachedUDID == nil)
        #expect(!connection.inputEnabled)
        #expect(connection.reason != nil)
    }

    #endif

    @Test func フレーム更新は画面の監視へ通知せず診断は毎秒の再読で更新する() throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        configure(connection)
        connection.attach(udid: "端末")
        fake.probeReply?(capability())
        let frame = try info(connection.generation.current)
        fake.attachReply?(frame, nil)
        let instant = Date(timeIntervalSince1970: 100)
        connection.observeFrame(frame, seed: 1, at: instant)
        let changes = FrameObservationChanges()
        withObservationTracking {
            _ = connection.lastFrameUpdate
            _ = connection.hasStaleFrame(at: instant)
        } onChange: {
            changes.changed = true
        }
        for seconds in 0..<5 {
            #expect(!connection.hasStaleFrame(at: instant.addingTimeInterval(Double(seconds))))
        }
        #expect(connection.hasStaleFrame(at: instant.addingTimeInterval(5)))
        connection.observeFrame(frame, seed: 2, at: instant.addingTimeInterval(6))
        #expect(!changes.changed)
        #expect(!connection.hasStaleFrame(at: instant.addingTimeInterval(6)))
        #expect(!connection.hasStaleFrame(at: instant.addingTimeInterval(10)))
        #expect(connection.hasStaleFrame(at: instant.addingTimeInterval(11)))
        connection.disconnect()
    }

    @Test(arguments: ["com.apple.CoreSimulator.SimRuntime.iOS-26-2", "未確認ランタイム"])
    func 公開の設定入口も正式な許可リストを照合する(runtime: String) {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        connection.configureVerifiedRuntime(runtime)
        connection.attach(udid: "端末")
        fake.probeReply?(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
            helperBuild: "検証", xcodeBuild: "17C52", coreSimulatorLoaded: true, simulatorKitLoaded: true))
        let supported = runtime == "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
        #expect(connection.support == (supported ? .supported : .unsupported))
        #expect((fake.attachedUDID != nil) == supported)
        connection.disconnect()
    }

    @Test(arguments: ["有効な画面", "probeのみ", "古い画面", "別端末", "寸法なし"])
    func 自動再接続の回数は正しい画面で復旧した時だけ戻る(recovery: String) throws {
        var attempts: [FakeTransport] = []
        let connection = SimulatorDisplayConnection {
            let fake = FakeTransport()
            attempts.append(fake)
            return fake
        }
        configure(connection)
        connection.automaticallyReconnects = true
        connection.attach(udid: "端末")
        attempts[0].failed?("切断1")
        #expect(attempts.count == 2)
        let retry = attempts[1]
        retry.probeReply?(capability())
        let generation = connection.generation.current
        switch recovery {
        case "有効な画面": retry.attachReply?(try info(generation), nil)
        case "古い画面": retry.changed?(try info(generation - 1))
        case "別端末": retry.changed?(try info(generation, udid: "別端末"))
        case "寸法なし":
            let valid = try info(generation)
            retry.changed?(SimulatorDisplayInfo(udid: valid.udid, connectionGeneration: generation,
                displayGeneration: 1, surface: valid.surface, pixelWidth: 0, pixelHeight: 8,
                orientation: .portrait, surfaceIsRotated: false, pixelFormat: valid.pixelFormat))
        default: break
        }
        retry.failed?("切断2")
        #expect(attempts.count == (recovery == "有効な画面" ? 3 : 2))
        if recovery != "有効な画面" { #expect(connection.canReconnect) }
        connection.disconnect()
    }

    @Test func 自動再接続は直近60秒に3回までで期限後に戻る() throws {
        var clock: TimeInterval = 100
        var attempts: [FakeTransport] = []
        let connection = SimulatorDisplayConnection(now: { clock }) {
            let fake = FakeTransport()
            attempts.append(fake)
            return fake
        }
        configure(connection)
        connection.automaticallyReconnects = true
        connection.attach(udid: "端末")
        for instant: TimeInterval in [100, 110, 120] {
            clock = instant
            let active = try #require(attempts.last)
            active.probeReply?(capability())
            active.attachReply?(try info(connection.generation.current), nil)
            active.failed?("切断")
        }
        #expect(attempts.count == 4)
        let fourth = try #require(attempts.last)
        fourth.probeReply?(capability())
        fourth.attachReply?(try info(connection.generation.current), nil)
        clock = 159.999
        fourth.failed?("60秒未満の切断")
        #expect(attempts.count == 4)
        #expect(connection.canReconnect)
        connection.reconnect()
        #expect(attempts.count == 5)
        let manual = try #require(attempts.last)
        manual.probeReply?(capability())
        manual.attachReply?(try info(connection.generation.current), nil)
        clock = 160
        manual.failed?("60秒後の切断")
        #expect(attempts.count == 6)
        connection.disconnect()
    }

    @Test(arguments: [false, true])
    func 方針またはランタイムが未設定なら接続しない(runtimeOnly: Bool) {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        if runtimeOnly {
            connection.configure(runtimeIdentifier: "検証ランタイム", triesUnverified: true)
        } else {
            connection.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "検証", runtimeIdentifier: "検証ランタイム", supportsInput: true)])
        }
        connection.attach(udid: "端末")
        fake.probeReply?(capability())
        #expect(connection.support == .unsupported)
        #expect(!connection.inputEnabled)
        #expect(fake.attachedUDID == nil)
        #expect(connection.reason == SimulatorPolicy.Support.unsupported.message)
        connection.disconnect()
    }

    @Test func probe完了前の画面通知は採用しない() throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        configure(connection)
        connection.attach(udid: "端末")
        fake.changed?(try info(connection.generation.current))
        #expect(connection.displayInfo == nil)
        fake.probeReply?(capability(version: 999))
        fake.changed?(try info(connection.generation.current))
        #expect(connection.displayInfo == nil)
        #expect(fake.attachedUDID == nil)
    }

    @Test(arguments: [false, true])
    func 解放時に接続を一度だけ破棄する(disconnect: Bool) throws {
        let fake = FakeTransport()
        var connection: SimulatorDisplayConnection? = SimulatorDisplayConnection { fake }
        configure(connection)
        weak let released = connection
        connection?.attach(udid: "端末")
        fake.probeReply?(capability())
        fake.attachReply?(try info(try #require(connection?.generation.current)), nil)
        if disconnect { connection?.disconnect() }
        connection = nil
        #expect(released == nil)
        #expect(fake.invalidations == 1)
    }

    @Test func 表示情報を受信し交代したsurfaceを採用する() throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        configure(connection)
        connection.attach(udid: "端末")
        fake.probeReply?(capability())
        let first = try info(connection.generation.current, display: 1)
        fake.attachReply?(first, nil)
        #expect(connection.displayInfo === first)
        let next = try info(connection.generation.current, display: 2)
        fake.changed?(next)
        #expect(connection.displayInfo === next)
        #expect(connection.reason == nil)
        #expect(fake.attachedUDID == "端末")
        #expect(fake.attachedGeneration == first.connectionGeneration)
        connection.disconnect()
        #expect(fake.detached == ["端末"])
        #expect(fake.invalidations == 1)
        #expect(connection.displayInfo == nil)
    }

    @Test func 古い接続と表示世代と別端末の通知を捨てる() throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        configure(connection)
        connection.attach(udid: "端末")
        fake.probeReply?(capability())
        let current = try info(connection.generation.current, display: 2)
        fake.attachReply?(current, nil)
        fake.changed?(try info(current.connectionGeneration - 1, display: 3))
        fake.changed?(try info(current.connectionGeneration, display: 1))
        fake.changed?(try info(current.connectionGeneration, display: 3, udid: "別端末"))
        #expect(connection.displayInfo === current)
        connection.disconnect()
    }

    @Test(arguments: [false, true])
    func 補助プロセスの終了を接続前後でエラーにする(attached: Bool) throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        configure(connection)
        connection.attach(udid: "端末")
        let generation = connection.generation.current
        if attached {
            fake.probeReply?(capability())
            fake.attachReply?(try info(generation), nil)
        }
        fake.failed?("補助プロセスが終了しました")
        #expect(connection.reason == "補助プロセスが終了しました")
        #expect(connection.displayInfo == nil)
        #expect(fake.invalidations == 1)
        fake.probeReply?(capability())
        fake.changed?(try info(generation))
        #expect(connection.displayInfo == nil)
        #expect(connection.generation.current > generation)
    }

    @Test(arguments: [false, true])
    func probeとattachの期限切れで接続を破棄し遅い応答を捨てる(attach: Bool) async throws {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection(timeout: 0.02) { fake }
        configure(connection)
        connection.attach(udid: "端末")
        let generation = connection.generation.current
        if attach { fake.probeReply?(capability()) }
        for _ in 0..<100 {
            if connection.reason != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(connection.reason == "補助プロセスの応答期限を超えました")
        #expect(fake.invalidations == 1)
        fake.probeReply?(capability())
        fake.attachReply?(try info(generation), nil)
        #expect(connection.displayInfo == nil)
        #expect(connection.generation.current > generation)
    }

    @Test func 版不一致ならattachせずエラーにする() {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        configure(connection)
        connection.attach(udid: "端末")
        fake.probeReply?(capability(version: 999))
        #expect(fake.attachedUDID == nil)
        #expect(connection.reason?.contains("再起動") == true)
        #expect(fake.invalidations == 1)
    }

    @Test func 部品の読み込み失敗をエラーにする() {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
        configure(connection)
        connection.attach(udid: "端末")
        fake.probeReply?(capability(loaded: false))
        #expect(fake.attachedUDID == nil)
        #expect(connection.reason != nil)
        #expect(fake.invalidations == 1)
    }

    @Test func attachのエラーと不正な応答をエラーにする() throws {
        for response in 0..<3 {
            let fake = FakeTransport()
            let connection = SimulatorDisplayConnection { fake }
            configure(connection)
            connection.attach(udid: "端末")
            fake.probeReply?(capability())
            switch response {
            case 0: fake.attachReply?(nil, NSError(domain: "検証", code: 1, userInfo: [NSLocalizedDescriptionKey: "取得失敗"]))
            case 1: fake.attachReply?(nil, nil)
            default: fake.attachReply?(try info(connection.generation.current - 1), nil)
            }
            #expect(connection.reason != nil)
            #expect(connection.displayInfo == nil)
            #expect(fake.invalidations == 1)
        }
    }

    @Test func 端末切替後の旧接続の終了と応答を捨てる() throws {
        let old = FakeTransport()
        let new = FakeTransport()
        var transports = [old, new]
        let connection = SimulatorDisplayConnection { transports.removeFirst() }
        configure(connection)
        connection.attach(udid: "端末")
        let previous = connection.generation.current
        old.probeReply?(capability())
        connection.attach(udid: "別端末")
        new.probeReply?(capability())
        let current = try info(connection.generation.current, udid: "別端末")
        new.attachReply?(current, nil)
        old.failed?("旧プロセスの終了")
        old.attachReply?(try info(previous), nil)
        #expect(connection.displayInfo === current)
        #expect(connection.reason == nil)
        connection.disconnect()
    }

    @Test func 表示部品はsurfaceを設定し古い通知を捨てて終了時に解放する() throws {
        let view = SimulatorScreenNSView()
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 800)
        let current = try info(2, display: 2)
        view.update(current)
        let layer = try #require(view.layer?.sublayers?.first)
        #expect((layer.contents as? IOSurface) === current.surface)
        #expect(layer.contentsGravity == .resizeAspect)
        view.update(try info(1, display: 3))
        view.update(try info(2, display: 1))
        #expect((layer.contents as? IOSurface) === current.surface)
        view.stop()
        #expect(layer.contents == nil)
    }

    private func configure(_ connection: SimulatorDisplayConnection?) {
        connection?.policy = SimulatorPolicy(entries: [.init(xcodeBuild: "検証", runtimeIdentifier: "検証ランタイム", supportsInput: true)])
        connection?.configure(runtimeIdentifier: "検証ランタイム", triesUnverified: false)
    }

    private func capability(version: Int = SimulatorBridgeInterfaces.protocolVersion, loaded: Bool = true) -> SimulatorBridgeCapability {
        SimulatorBridgeCapability(protocolVersion: version, helperBuild: "検証", xcodeBuild: "検証",
                                  coreSimulatorLoaded: loaded, simulatorKitLoaded: loaded)
    }

    private func info(_ generation: Int, display: Int = 1, udid: String = "端末") throws -> SimulatorDisplayInfo {
        let surface = try #require(IOSurface(properties: [
            .width: 4, .height: 8, .bytesPerElement: 4, .bytesPerRow: 16,
            .allocSize: 128, .pixelFormat: 0x42475241,
        ]))
        return SimulatorDisplayInfo(udid: udid, connectionGeneration: generation, displayGeneration: display,
                                    surface: surface, pixelWidth: 4, pixelHeight: 8, orientation: .portrait,
                                    surfaceIsRotated: false, pixelFormat: 0x42475241)
    }
}

private final class FrameObservationChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var changed: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@MainActor private final class FakeTransport: SimulatorDisplayTransport {
    var changed: (@MainActor (SimulatorDisplayInfo) -> Void)?
    var failed: (@MainActor (String) -> Void)?
    var probeReply: (@MainActor (SimulatorBridgeCapability) -> Void)?
    var attachReply: (@MainActor (SimulatorDisplayInfo?, NSError?) -> Void)?
    var attachedUDID: String?
    var attachedGeneration: Int?
    var detached: [String] = []
    var invalidations = 0

    func resume(surfaceChanged: @escaping @MainActor (SimulatorDisplayInfo) -> Void,
                failed: @escaping @MainActor (String) -> Void) {
        changed = surfaceChanged
        self.failed = failed
    }
    func probe(reply: @escaping @MainActor (SimulatorBridgeCapability) -> Void) { probeReply = reply }
    func attach(udid: String, generation: Int,
                reply: @escaping @MainActor (SimulatorDisplayInfo?, NSError?) -> Void) {
        attachedUDID = udid
        attachedGeneration = generation
        attachReply = reply
    }
    func detach(udid: String) { detached.append(udid) }
    func sendTouch(udid: String, phase: Int, x: Double, y: Double) {}
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int) {}
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool) {}
    func sendButton(udid: String, button: Int) {}
    func releaseAll(udid: String) {}
    func invalidate() { invalidations += 1 }
}
