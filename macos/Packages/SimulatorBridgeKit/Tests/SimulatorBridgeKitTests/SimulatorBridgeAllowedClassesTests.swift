import AppKit
import IOSurface
import Testing
import XCTest
@testable import SimulatorBridgeKit

// 補助プロセスが宣言と違う型を返しても、本体が受け取らないこと。
final class SimulatorBridgeAllowedClassesTests: XCTestCase {
    func test能力値の代わりにNSStringが届いても受け取らない() {
        let harness = DisguiseHarness(probeReply: NSString(string: "偽装"))
        defer { harness.close() }
        let replied = expectation(description: "偽装した能力値を受け取ってしまった")
        replied.isInverted = true
        let rejected = expectation(description: "通信エラーで拒否")
        harness.proxy { _ in rejected.fulfill() }.probe { _ in replied.fulfill() }
        wait(for: [replied, rejected], timeout: 2)

    }

    func test表示情報の代わりにIOSurfaceが届いても受け取らない() throws {
        let surface = try XCTUnwrap(IOSurface(properties: [.width: 2, .height: 3, .bytesPerElement: 4]))
        let rejected = expectation(description: "表示情報の偽装を接続無効化で拒否")
        let harness = DisguiseHarness(surfaceChanged: surface, onInvalidation: { rejected.fulfill() })
        defer { harness.close() }
        let received = expectation(description: "偽装した表示情報を受け取ってしまった")
        received.isInverted = true
        harness.client.onReceive = { received.fulfill() }
        harness.proxy { _ in }.attach(udid: "端末", generation: 1) { _, _ in }
        wait(for: [received, rejected], timeout: 2)

    }
}

private final class DisguiseHarness: NSObject, NSXPCListenerDelegate, SimulatorBridgeProtocol {
    let probeReply: AnyObject?
    let surfaceObject: AnyObject?
    let client = DisguiseClient()
    let onInvalidation: () -> Void
    private let listener = NSXPCListener.anonymous()
    private var accepted: [NSXPCConnection] = []
    private var connection: NSXPCConnection!

    init(probeReply: AnyObject? = nil, surfaceChanged: AnyObject? = nil,
         onInvalidation: @escaping () -> Void = {}) {
        self.onInvalidation = onInvalidation
        self.probeReply = probeReply
        self.surfaceObject = surfaceChanged
        super.init()
        listener.delegate = self
        listener.resume()
        connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = SimulatorBridgeInterfaces.service()
        connection.exportedInterface = SimulatorBridgeInterfaces.client()
        connection.exportedObject = client
        connection.invalidationHandler = onInvalidation
        connection.resume()
    }
    func proxy(_ onError: @escaping (Error) -> Void) -> SimulatorBridgeProtocol {
        connection.remoteObjectProxyWithErrorHandler(onError) as! SimulatorBridgeProtocol
    }
    func close() {
        connection.invalidationHandler = nil
        connection.invalidate()
        accepted.forEach { $0.invalidate() }
        listener.invalidate()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.exportedInterface = SimulatorBridgeInterfaces.service()
        c.remoteObjectInterface = SimulatorBridgeInterfaces.client()
        c.exportedObject = self
        accepted.append(c)
        c.resume()
        return true
    }
    func probe(reply: @escaping (SimulatorBridgeCapability) -> Void) {
        // 宣言と異なる型を送る攻撃を再現するため、テストでだけ型を偽装する。
        if let probeReply { reply(unsafeBitCast(probeReply, to: SimulatorBridgeCapability.self)) }
    }
    func attach(udid: String, generation: Int, reply: @escaping (SimulatorDisplayInfo?, NSError?) -> Void) {
        if let surfaceObject {
            (accepted.last?.remoteObjectProxy as? SimulatorBridgeClientProtocol)?
                .surfaceChanged(unsafeBitCast(surfaceObject, to: SimulatorDisplayInfo.self))
        }
        reply(nil, nil)
    }
    func detach(udid: String) {}
    func sendTouch(udid: String, phase: Int, x: Double, y: Double) {}
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int) {}
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool) {}
    func sendButton(udid: String, button: Int) {}
    func releaseAll(udid: String) {}
}

private final class DisguiseClient: NSObject, SimulatorBridgeClientProtocol {
    var onReceive: () -> Void = {}
    func surfaceChanged(_ info: SimulatorDisplayInfo) { onReceive() }
}
