import AppKit
import Foundation
import IOSurface
import Testing
import SimulatorBridgeKit
@testable import DashboardFeature

@Suite(.serialized) @MainActor
struct SimulatorDisplayConnectionTests {
    @Test(arguments: [false, true])
    func 解放時に接続を一度だけ破棄する(disconnect: Bool) throws {
        let fake = FakeTransport()
        var connection: SimulatorDisplayConnection? = SimulatorDisplayConnection { fake }
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
        connection.attach(udid: "端末")
        fake.probeReply?(capability(version: 999))
        #expect(fake.attachedUDID == nil)
        #expect(connection.reason?.contains("再起動") == true)
        #expect(fake.invalidations == 1)
    }

    @Test func 部品の読み込み失敗をエラーにする() {
        let fake = FakeTransport()
        let connection = SimulatorDisplayConnection { fake }
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
    func invalidate() { invalidations += 1 }
}
