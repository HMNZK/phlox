import Foundation
import IOSurface
import Testing
import XCTest
@testable import SimulatorBridgeKit

struct SimulatorGenerationTests {
    @Test func 再接続と期限切れで古い応答を除外する() {
        var generation = SimulatorConnectionGeneration()
        let first = generation.advance()
        #expect(generation.accepts(first))
        let second = generation.advance()
        #expect(!generation.accepts(first))
        #expect(generation.accepts(second))
        #expect(!generation.accepts(second + 1))
    }

    @Test func 能力値を安全に符号化する() throws {
        let capability = SimulatorBridgeCapability(
            protocolVersion: 1, helperBuild: "2", xcodeBuild: "17C52",
            coreSimulatorLoaded: true, simulatorKitLoaded: false, reason: "部品を読み込めません"
        )
        let data = try NSKeyedArchiver.archivedData(withRootObject: capability, requiringSecureCoding: true)
        let decoded = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: SimulatorBridgeCapability.self, from: data))
        #expect(decoded.protocolVersion == 1)
        #expect(decoded.helperBuild == "2")
        #expect(decoded.xcodeBuild == "17C52")
        #expect(decoded.coreSimulatorLoaded)
        #expect(!decoded.simulatorKitLoaded)
        #expect(decoded.reason == "部品を読み込めません")
    }

    @Test func 理由なしの能力値を安全に符号化する() throws {
        let capability = SimulatorBridgeCapability(
            protocolVersion: 1, helperBuild: "2", xcodeBuild: "17C52",
            coreSimulatorLoaded: true, simulatorKitLoaded: true
        )
        let data = try NSKeyedArchiver.archivedData(withRootObject: capability, requiringSecureCoding: true)
        let decoded = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: SimulatorBridgeCapability.self, from: data))
        #expect(decoded.reason == nil)
        #expect(decoded.simulatorKitLoaded)
    }

    @Test func 表示情報の欠落と不正な値を拒否する() throws {
        let surface = try #require(IOSurface(properties: [.width: 2, .height: 3, .bytesPerElement: 4]))
        let info = SimulatorDisplayInfo(
            udid: "端末", connectionGeneration: 1, displayGeneration: 2, surface: surface,
            pixelWidth: 2, pixelHeight: 3, orientation: .portrait,
            surfaceIsRotated: false, pixelFormat: UInt32.max
        )
        let coder = DisplayInfoCoder()
        info.encode(with: coder)
        #expect(SimulatorDisplayInfo(coder: coder)?.pixelFormat == UInt32.max)
        for key in coder.values.keys {
            let incomplete = DisplayInfoCoder(values: coder.values)
            incomplete.values.removeValue(forKey: key)
            #expect(SimulatorDisplayInfo(coder: incomplete) == nil)
        }
        for (key, value) in [("pixelWidth", 0), ("pixelHeight", -1), ("orientation", 4),
                             ("connectionGeneration", -1), ("displayGeneration", -1), ("pixelFormat", -1)] {
            let invalid = DisplayInfoCoder(values: coder.values)
            invalid.values[key] = value
            #expect(SimulatorDisplayInfo(coder: invalid) == nil)
        }
    }
}

// IOSurfaceを通常のアーカイブへ渡さず、復号時の必須項目と値の検査を試す。
private final class DisplayInfoCoder: NSCoder {
    var values: [String: Any]
    init(values: [String: Any] = [:]) { self.values = values }
    override var allowsKeyedCoding: Bool { true }
    override func containsValue(forKey key: String) -> Bool { values[key] != nil }
    override func encode(_ object: Any?, forKey key: String) { values[key] = object }
    override func encode(_ value: Int, forKey key: String) { values[key] = value }
    override func encode(_ value: Int64, forKey key: String) { values[key] = value }
    override func encode(_ value: Bool, forKey key: String) { values[key] = value }
    override func decodeInteger(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    override func decodeInt64(forKey key: String) -> Int64 {
        if let value = values[key] as? Int64 { return value }
        return Int64(values[key] as? Int ?? 0)
    }
    override func decodeBool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func __decodeObject(ofClasses classes: Set<AnyHashable>?, forKey key: String) -> Any? { values[key] }
}

// IOSurfaceはNSXPCCoder専用なので、通常のアーカイブではなく匿名XPC接続で検査する。
final class SimulatorBridgeContractTests: XCTestCase {
    func test表示情報と能力値をXPCで往復する() throws {
        let surface = try XCTUnwrap(IOSurface(properties: [
            .width: 2, .height: 3, .bytesPerElement: 4, .pixelFormat: 0x42475241,
        ]))
        let info = SimulatorDisplayInfo(
            udid: "端末", connectionGeneration: 7, displayGeneration: 3, surface: surface,
            pixelWidth: 2, pixelHeight: 3, orientation: .landscapeRight,
            surfaceIsRotated: true, pixelFormat: 0x42475241
        )
        XCTAssertTrue(info.isCurrent(udid: "端末", connectionGeneration: 7, minimumDisplayGeneration: 3))
        XCTAssertFalse(info.isCurrent(udid: "別端末", connectionGeneration: 7, minimumDisplayGeneration: 3))
        XCTAssertFalse(info.isCurrent(udid: "端末", connectionGeneration: 8, minimumDisplayGeneration: 3))
        XCTAssertFalse(info.isCurrent(udid: "端末", connectionGeneration: 7, minimumDisplayGeneration: 4))

        let callback = expectation(description: "表示変更通知")
        let reply = expectation(description: "接続応答")
        let probe = expectation(description: "能力値応答")
        let errorReply = expectation(description: "エラー応答")
        let client = ContractClient { received in
            XCTAssertEqual(received.udid, "端末")
            XCTAssertEqual(received.connectionGeneration, 7)
            XCTAssertEqual(received.displayGeneration, 3)
            XCTAssertEqual(received.pixelWidth, 2)
            XCTAssertEqual(received.pixelHeight, 3)
            XCTAssertEqual(received.orientation, .landscapeRight)
            XCTAssertTrue(received.surfaceIsRotated)
            XCTAssertEqual(received.pixelFormat, 0x42475241)
            XCTAssertEqual(IOSurfaceGetID(received.surface), IOSurfaceGetID(surface))
            callback.fulfill()
        }
        let listener = NSXPCListener.anonymous()
        let delegate = ContractListener(info: info)
        listener.delegate = delegate
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = SimulatorBridgeInterfaces.service()
        connection.exportedInterface = SimulatorBridgeInterfaces.client()
        connection.exportedObject = client
        connection.resume()
        defer {
            connection.invalidate()
            delegate.connections.forEach { $0.invalidate() }
            listener.invalidate()
        }
        let proxy = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC通信に失敗: \(error)")
        } as? SimulatorBridgeProtocol)
        proxy.probe { capability in
            XCTAssertEqual(capability.protocolVersion, SimulatorBridgeInterfaces.protocolVersion)
            XCTAssertEqual(capability.helperBuild, "1")
            XCTAssertEqual(capability.xcodeBuild, "17C52")
            XCTAssertTrue(capability.coreSimulatorLoaded)
            XCTAssertTrue(capability.simulatorKitLoaded)
            XCTAssertNil(capability.reason)
            probe.fulfill()
        }
        proxy.attach(udid: "端末", generation: 7) { received, error in
            XCTAssertNil(error)
            XCTAssertEqual(received?.connectionGeneration, 7)
            XCTAssertEqual(received?.displayGeneration, 3)
            XCTAssertEqual(received?.surface.width, 2)
            reply.fulfill()
        }
        proxy.attach(udid: "不在", generation: 7) { received, error in
            XCTAssertNil(received)
            XCTAssertEqual(error?.domain, "SimulatorBridgeContractTests")
            XCTAssertEqual(error?.code, 1)
            XCTAssertEqual(error?.localizedDescription, "端末がありません")
            errorReply.fulfill()
        }
        wait(for: [callback, reply, probe, errorReply], timeout: 5)
    }
}

private final class ContractClient: NSObject, SimulatorBridgeClientProtocol {
    let receive: (SimulatorDisplayInfo) -> Void
    init(receive: @escaping (SimulatorDisplayInfo) -> Void) { self.receive = receive }
    func surfaceChanged(_ info: SimulatorDisplayInfo) { receive(info) }
}

private final class ContractListener: NSObject, NSXPCListenerDelegate {
    let info: SimulatorDisplayInfo
    var connections: [NSXPCConnection] = []
    init(info: SimulatorDisplayInfo) { self.info = info }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = SimulatorBridgeInterfaces.service()
        connection.remoteObjectInterface = SimulatorBridgeInterfaces.client()
        connection.exportedObject = ContractService(info: info, connection: connection)
        connections.append(connection)
        connection.resume()
        return true
    }
}

private final class ContractService: NSObject, SimulatorBridgeProtocol {
    let info: SimulatorDisplayInfo
    weak var connection: NSXPCConnection?
    init(info: SimulatorDisplayInfo, connection: NSXPCConnection) {
        self.info = info
        self.connection = connection
    }
    func probe(reply: @escaping (SimulatorBridgeCapability) -> Void) {
        reply(SimulatorBridgeCapability(protocolVersion: SimulatorBridgeInterfaces.protocolVersion, helperBuild: "1", xcodeBuild: "17C52",
                                        coreSimulatorLoaded: true, simulatorKitLoaded: true))
    }
    func attach(udid: String, generation: Int, reply: @escaping (SimulatorDisplayInfo?, NSError?) -> Void) {
        guard udid == info.udid else {
            reply(nil, NSError(domain: "SimulatorBridgeContractTests", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "端末がありません"]))
            return
        }
        reply(info, nil)
        (connection?.remoteObjectProxy as? SimulatorBridgeClientProtocol)?.surfaceChanged(info)
    }
    func detach(udid: String) {}
    func sendTouch(udid: String, phase: Int, x: Double, y: Double) {}
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int) {}
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool) {}
    func sendButton(udid: String, button: Int) {}
    func releaseAll(udid: String) {}
}
