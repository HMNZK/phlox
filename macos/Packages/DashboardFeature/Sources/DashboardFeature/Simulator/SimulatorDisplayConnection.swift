import Foundation
import Observation
import SimulatorBridgeKit

@MainActor
protocol SimulatorDisplayTransport: AnyObject {
    func resume(surfaceChanged: @escaping @MainActor (SimulatorDisplayInfo) -> Void,
                failed: @escaping @MainActor (String) -> Void)
    func probe(reply: @escaping @MainActor (SimulatorBridgeCapability) -> Void)
    func attach(udid: String, generation: Int,
                reply: @escaping @MainActor (SimulatorDisplayInfo?, NSError?) -> Void)
    func detach(udid: String)
    func invalidate()
}

/// 1つの表示に必要な接続。端末の起動・停止や自動再接続はここでは行わない。
@MainActor @Observable
public final class SimulatorDisplayConnection {
    public private(set) var displayInfo: SimulatorDisplayInfo?
    public private(set) var reason: String?
    public private(set) var generation = SimulatorConnectionGeneration()
    @ObservationIgnored private let makeTransport: () -> any SimulatorDisplayTransport
    @ObservationIgnored private let timeout: TimeInterval
    @ObservationIgnored private var transport: (any SimulatorDisplayTransport)?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var udid: String?

    public convenience init() {
        self.init(makeTransport: { SimulatorXPCTransport() })
    }

    init(timeout: TimeInterval = SimulatorBridgeInterfaces.replyTimeout,
         makeTransport: @escaping () -> any SimulatorDisplayTransport) {
        self.timeout = timeout
        self.makeTransport = makeTransport
    }

    isolated deinit {
        deadline?.cancel()
        transport?.invalidate()
    }

    public func attach(udid: String) {
        disconnect()
        reason = nil
        self.udid = udid
        let current = generation.current
        let transport = makeTransport()
        self.transport = transport
        transport.resume(surfaceChanged: { [weak self] info in
            guard self?.generation.accepts(current) == true else { return }
            self?.receive(info)
        }, failed: { [weak self] message in self?.fail(message, generation: current) })
        let probeRequest = beginDeadline(current)
        transport.probe { [weak self] capability in
            guard let self, self.finishDeadline(probeRequest, generation: current) else { return }
            guard capability.protocolVersion == SimulatorBridgeInterfaces.protocolVersion else {
                self.fail("通信仕様の版が異なります。アプリを再起動してください", generation: current)
                return
            }
            guard capability.coreSimulatorLoaded, capability.simulatorKitLoaded, capability.reason == nil else {
                self.fail(capability.reason ?? "画面取得の部品を読み込めません", generation: current)
                return
            }
            let attachRequest = self.beginDeadline(current)
            transport.attach(udid: udid, generation: current) { [weak self] info, error in
                guard let self, self.finishDeadline(attachRequest, generation: current) else { return }
                if let error { self.fail(error.localizedDescription, generation: current) }
                else if let info, self.receive(info) {} // 通知と応答は同じ世代検査を通す。
                else { self.fail("有効な表示情報を受け取れませんでした", generation: current) }
            }
        }
    }

    public func disconnect() {
        generation.advance()
        request += 1
        deadline?.cancel()
        deadline = nil
        if let udid { transport?.detach(udid: udid) }
        transport?.invalidate()
        transport = nil
        udid = nil
        displayInfo = nil
    }

    @discardableResult private func receive(_ info: SimulatorDisplayInfo) -> Bool {
        guard let udid, info.isCurrent(udid: udid, connectionGeneration: generation.current,
                                      minimumDisplayGeneration: displayInfo?.displayGeneration ?? 0),
              info.pixelWidth > 0, info.pixelHeight > 0 else { return false }
        displayInfo = info
        return true
    }

    private func beginDeadline(_ current: Int) -> Int {
        deadline?.cancel()
        request += 1
        let pending = request
        let duration = timeout
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, self.request == pending else { return }
            self.fail("補助プロセスの応答期限を超えました", generation: current)
        }
        return pending
    }

    private func finishDeadline(_ pending: Int, generation current: Int) -> Bool {
        guard generation.accepts(current), request == pending, transport != nil else { return false }
        deadline?.cancel()
        deadline = nil
        request += 1
        return true
    }

    private func fail(_ message: String, generation current: Int) {
        guard generation.accepts(current) else { return }
        disconnect()
        reason = message
    }
}

@MainActor
private final class SimulatorXPCTransport: NSObject, SimulatorDisplayTransport, SimulatorBridgeClientProtocol {
    private let connection: NSXPCConnection
    private var changed: (@MainActor (SimulatorDisplayInfo) -> Void)?
    private var failed: (@MainActor (String) -> Void)?

    override init() {
        connection = NSXPCConnection(serviceName: (Bundle.main.bundleIdentifier ?? "com.phlox.Phlox") + ".SimulatorBridge")
        super.init()
    }

    func resume(surfaceChanged: @escaping @MainActor (SimulatorDisplayInfo) -> Void,
                failed: @escaping @MainActor (String) -> Void) {
        changed = surfaceChanged
        self.failed = failed
        connection.remoteObjectInterface = SimulatorBridgeInterfaces.service()
        connection.exportedInterface = SimulatorBridgeInterfaces.client()
        connection.exportedObject = self
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.failed?("補助プロセスとの通信が中断しました") }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.failed?("補助プロセスとの接続が終了しました") }
        }
        connection.resume()
    }

    private var service: (any SimulatorBridgeProtocol)? {
        connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in self?.failed?(message) }
        } as? any SimulatorBridgeProtocol
    }

    func probe(reply: @escaping @MainActor (SimulatorBridgeCapability) -> Void) {
        service?.probe { capability in
            let delivery = Delivery(capability)
            Task { @MainActor in reply(delivery.value) }
        }
    }

    func attach(udid: String, generation: Int,
                reply: @escaping @MainActor (SimulatorDisplayInfo?, NSError?) -> Void) {
        service?.attach(udid: udid, generation: generation) { info, error in
            let delivery = Delivery((info, error))
            Task { @MainActor in reply(delivery.value.0, delivery.value.1) }
        }
    }

    func detach(udid: String) { service?.detach(udid: udid) }

    func invalidate() {
        changed = nil
        failed = nil
        connection.exportedObject = nil
        connection.invalidate()
    }

    nonisolated func surfaceChanged(_ info: SimulatorDisplayInfo) {
        let delivery = Delivery(info)
        Task { @MainActor [weak self] in self?.changed?(delivery.value) }
    }
}

// 共通契約の不変な値を XPC の配送キューから MainActor へ渡す。
private struct Delivery<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
