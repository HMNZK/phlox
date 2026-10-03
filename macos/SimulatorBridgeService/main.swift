import Foundation
import SimulatorBridgeKit
import IOSurface

// XPC の呼び出し・非公開 API・終了処理は同じ直列キューで処理する。
final class SimulatorBridgeService: NSObject, SimulatorBridgeProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.phlox.simulator.display")
    private let connection: NSXPCConnection
    private let loader = PrivateSimulatorAPI()
    private var captures: [String: PrivateSimulatorAPI] = [:]
    private var pending: [String: (SimulatorDisplayInfo?, NSError?) -> Void] = [:]
    private var displayGenerations: [String: Int] = [:]

    init(connection: NSXPCConnection) { self.connection = connection }

    func probe(reply: @escaping (SimulatorBridgeCapability) -> Void) {
        let response = Reply(reply)
        queue.async { [self] in
            _ = loader.load()
            response.call(SimulatorBridgeCapability(
                protocolVersion: SimulatorBridgeInterfaces.protocolVersion,
                helperBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明",
                xcodeBuild: loader.xcodeBuild, coreSimulatorLoaded: loader.coreSimulatorLoaded,
                simulatorKitLoaded: loader.simulatorKitLoaded, reason: loader.reason
            ))
        }
    }

    func attach(udid: String, generation: Int, reply: @escaping (SimulatorDisplayInfo?, NSError?) -> Void) {
        let response = Reply<(SimulatorDisplayInfo?, NSError?)> { reply($0.0, $0.1) }
        queue.async { [self] in
            detachCapture(udid)
            guard generation >= 0 else {
                response.call((nil, error("接続世代が不正です")))
                return
            }
            let capture = PrivateSimulatorAPI()
            captures[udid] = capture
            pending[udid] = { response.call(($0, $1)) }
            do {
                try capture.attach(udid, queue: queue) { [weak self, weak capture] surface in
                    guard let self, let capture, self.captures[udid] === capture else { return }
                    let next = (self.displayGenerations[udid] ?? 0) + 1
                    self.displayGenerations[udid] = next
                    let info = SimulatorDisplayInfo(
                        udid: udid, connectionGeneration: generation, displayGeneration: next, surface: surface,
                        pixelWidth: IOSurfaceGetWidth(surface), pixelHeight: IOSurfaceGetHeight(surface),
                        orientation: .portrait, surfaceIsRotated: false, pixelFormat: IOSurfaceGetPixelFormat(surface)
                    )
                    if let first = self.pending.removeValue(forKey: udid) { first(info, nil) }
                    else {
                        let client = self.connection.remoteObjectProxyWithErrorHandler { failure in
                            NSLog("表示情報の送信に失敗しました: %@", failure.localizedDescription)
                        } as? SimulatorBridgeClientProtocol
                        client?.surfaceChanged(info)
                    }
                }
            } catch {
                pending.removeValue(forKey: udid)?(nil, error as NSError)
                captures.removeValue(forKey: udid)?.detach()
            }
        }
    }

    func detach(udid: String) { queue.async { self.detachCapture(udid) } }

    private func detachCapture(_ udid: String) {
        pending.removeValue(forKey: udid)?(nil, error("画面取得を終了しました"))
        captures.removeValue(forKey: udid)?.detach()
    }

    func invalidate() {
        queue.async { [self] in
            for udid in Array(captures.keys) { detachCapture(udid) }
            connection.exportedObject = nil
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
        }
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "Phlox.SimulatorBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func sendTouch(udid: String, phase: Int, x: Double, y: Double) {
        queue.async { self.captures[udid]?.sendTouch(phase, x: x, y: y) }
    }
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int) {
        queue.async { self.captures[udid]?.sendScroll(dx, dy: dy, x: x, y: y, phase: phase) }
    }
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool) {
        queue.async { self.captures[udid]?.sendKey(keyCode, modifiers: modifiers, down: down) }
    }
    func sendButton(udid: String, button: Int) {
        queue.async { self.captures[udid]?.sendButton(button) }
    }
    func releaseAll(udid: String) { queue.async { self.captures[udid]?.releaseAll() } }
}

// 応答クロージャーはキューへ一度だけ渡し、そのキューだけで呼ぶ。
private final class Reply<Value>: @unchecked Sendable {
    let call: (Value) -> Void
    init(_ call: @escaping (Value) -> Void) { self.call = call }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let service = SimulatorBridgeService(connection: connection)
        connection.exportedInterface = SimulatorBridgeInterfaces.service()
        connection.exportedObject = service
        connection.remoteObjectInterface = SimulatorBridgeInterfaces.client()
        connection.invalidationHandler = { service.invalidate() }
        connection.interruptionHandler = { service.invalidate() }
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
