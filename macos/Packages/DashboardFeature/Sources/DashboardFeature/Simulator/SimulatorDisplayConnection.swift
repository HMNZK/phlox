import Foundation
import IOSurface
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
    func sendTouch(udid: String, phase: Int, x: Double, y: Double)
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int)
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool)
    func sendButton(udid: String, button: Int)
    func releaseAll(udid: String)
    func invalidate()
}

/// 端末ごとの接続。復旧時にも端末の起動・停止や古い入力の再送は行わない。
@MainActor @Observable
public final class SimulatorDisplayConnection {
    public private(set) var displayInfo: SimulatorDisplayInfo?
    private(set) var displayOrientation: SimulatorOrientation = .portrait
    var presentedDisplayInfo: SimulatorDisplayInfo? {
        guard let info = displayInfo else { return nil }
        return SimulatorDisplayInfo(
            udid: info.udid, connectionGeneration: info.connectionGeneration,
            displayGeneration: info.displayGeneration, surface: info.surface,
            pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight,
            orientation: displayOrientation, surfaceIsRotated: false, pixelFormat: info.pixelFormat
        )
    }
    public private(set) var reason: String?
    public private(set) var generation = SimulatorConnectionGeneration()
    public private(set) var inputRevision = 0
    private(set) var capability: SimulatorBridgeCapability?
    private(set) var support: SimulatorPolicy.Support = .unsupported
    private(set) var canReconnect = false
    private(set) var blocksRetry = false
    @ObservationIgnored private(set) var lastFrameUpdate: Date?
    var inputEnabled: Bool { support.allowsInput && displayInfo != nil }
    var automaticallyReconnects = false
    var policy: SimulatorPolicy?
    private var runtimeIdentifier: String?
    private var triesUnverified = false
    private var retried = false
    private var automaticReconnectTimes: [TimeInterval] = []
    private var requestedUDID: String?
    @ObservationIgnored private var observedSurface: UInt32?
    @ObservationIgnored private var observedSeed: UInt32?
    private var acceptsSurfaces = false
    private(set) var sentKeyCodes: Set<UInt16> = []
    @ObservationIgnored private let makeTransport: () -> any SimulatorDisplayTransport
    @ObservationIgnored private let timeout: TimeInterval
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private var transport: (any SimulatorDisplayTransport)?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var udid: String?

    public convenience init() {
        self.init(makeTransport: { SimulatorXPCTransport() })
    }

    init(timeout: TimeInterval = SimulatorBridgeInterfaces.replyTimeout,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         makeTransport: @escaping () -> any SimulatorDisplayTransport) {
        self.timeout = timeout
        self.now = now
        self.makeTransport = makeTransport
    }

    isolated deinit {
        deadline?.cancel()
        if let udid { transport?.releaseAll(udid: udid) }
        transport?.invalidate()
    }

    public func attach(udid: String) {
        requestedUDID = udid
        capability = nil
        start(udid: udid)
    }

    public func configureVerifiedRuntime(_ runtimeIdentifier: String) {
        policy = .verified
        configure(runtimeIdentifier: runtimeIdentifier, triesUnverified: false)
    }

    #if DEBUG
    /// 許可リストへ追加する前の検査専用。登録済みの組も未確認として扱う。
    public func configureForCompatibilityCheck(runtime: String) {
        policy = SimulatorPolicy(entries: [])
        runtimeIdentifier = nil
        configure(runtimeIdentifier: runtime, triesUnverified: true)
    }
    #endif

    func configure(runtimeIdentifier: String, triesUnverified: Bool) {
        guard self.runtimeIdentifier != runtimeIdentifier || self.triesUnverified != triesUnverified else { return }
        self.runtimeIdentifier = runtimeIdentifier
        self.triesUnverified = triesUnverified
        guard let capability else { return }
        let next = policy?.support(xcodeBuild: capability.xcodeBuild, runtimeIdentifier: runtimeIdentifier,
                                   triesUnverified: triesUnverified) ?? .unsupported
        let changed = support != next
        support = next
        if changed, !blocksRetry, let requestedUDID { attach(udid: requestedUDID) }
    }

    func reconnect() {
        guard canReconnect, !blocksRetry, let requestedUDID else { return }
        attach(udid: requestedUDID)
    }

    private func start(udid: String) {
        disconnect()
        reason = nil
        canReconnect = false
        blocksRetry = false
        self.udid = udid
        let current = generation.current
        let transport = makeTransport()
        self.transport = transport
        transport.resume(surfaceChanged: { [weak self] info in
            guard self?.generation.accepts(current) == true else { return }
            self?.receive(info)
        }, failed: { [weak self] message in self?.fail(message, generation: current) })
        guard generation.accepts(current) else { return }
        let probeRequest = beginDeadline(current)
        transport.probe { [weak self] capability in
            guard let self, self.finishDeadline(probeRequest, generation: current) else { return }
            self.capability = capability
            guard capability.protocolVersion == SimulatorBridgeInterfaces.protocolVersion else {
                self.fail("通信仕様の版が異なります。アプリを再起動してください", generation: current, retryable: false)
                return
            }
            guard capability.coreSimulatorLoaded, capability.simulatorKitLoaded, capability.reason == nil else {
                self.fail(capability.reason ?? "画面取得の部品を読み込めません", generation: current, retryable: false)
                return
            }
            self.support = .unsupported
            if let runtime = self.runtimeIdentifier, let policy = self.policy {
                self.support = policy.support(xcodeBuild: capability.xcodeBuild, runtimeIdentifier: runtime,
                                              triesUnverified: self.triesUnverified)
            }
            guard self.support.allowsDisplay else {
                self.disconnect()
                self.reason = self.support.message
                return
            }
            self.acceptsSurfaces = true
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
        releaseAll()
        generation.advance()
        request += 1
        deadline?.cancel()
        deadline = nil
        if let udid { transport?.detach(udid: udid) }
        transport?.invalidate()
        transport = nil
        udid = nil
        displayInfo = nil
        displayOrientation = .portrait
        lastFrameUpdate = nil
        observedSurface = nil
        observedSeed = nil
        acceptsSurfaces = false
    }

    func sendTouch(phase: Int, point: CGPoint) {
        guard inputEnabled, let info = displayInfo else { return }
        transport?.sendTouch(udid: info.udid, phase: phase, x: point.x, y: point.y)
    }

    func sendScroll(dx: Double, dy: Double, point: CGPoint, phase: Int = 0) {
        guard inputEnabled, let info = displayInfo else { return }
        transport?.sendScroll(udid: info.udid, dx: dx, dy: dy, x: point.x, y: point.y, phase: phase)
    }

    func sendKey(keyCode: UInt16, modifiers: UInt, down: Bool) {
        guard inputEnabled, let info = displayInfo else { return }
        transport?.sendKey(udid: info.udid, keyCode: keyCode, modifiers: modifiers, down: down)
        if down { sentKeyCodes.insert(keyCode) }
        else { sentKeyCodes.remove(keyCode) }
    }

    public func sendHome() {
        guard inputEnabled, let info = displayInfo else { return }
        transport?.sendButton(udid: info.udid, button: 0)
    }

    func rotateDisplay() {
        guard displayInfo != nil else { return }
        releaseAll()
        displayOrientation = displayOrientation.clockwise
    }

    public func releaseAll() {
        inputRevision += 1
        sentKeyCodes.removeAll()
        if let udid { transport?.releaseAll(udid: udid) }
    }

    @discardableResult private func receive(_ info: SimulatorDisplayInfo) -> Bool {
        guard acceptsSurfaces, let udid, info.isCurrent(udid: udid, connectionGeneration: generation.current,
                                      minimumDisplayGeneration: displayInfo?.displayGeneration ?? 0),
              info.pixelWidth > 0, info.pixelHeight > 0 else { return false }
        displayInfo = info
        retried = false
        observeFrame(info, seed: IOSurfaceGetSeed(info.surface))
        return true
    }

    func observeFrame(_ info: SimulatorDisplayInfo, seed: UInt32, at date: Date = Date()) {
        guard info.isCurrent(udid: udid ?? "", connectionGeneration: generation.current,
                             minimumDisplayGeneration: displayInfo?.displayGeneration ?? 0), displayInfo != nil else { return }
        let surface = IOSurfaceGetID(info.surface)
        if observedSurface != surface || observedSeed != seed {
            observedSurface = surface
            observedSeed = seed
            lastFrameUpdate = date
        }
    }

    func hasStaleFrame(at date: Date) -> Bool {
        guard displayInfo != nil, let lastFrameUpdate else { return false }
        return date.timeIntervalSince(lastFrameUpdate) >= 5
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

    private func fail(_ message: String, generation current: Int, retryable: Bool = true) {
        guard generation.accepts(current) else { return }
        disconnect()
        reason = message
        blocksRetry = !retryable
        canReconnect = retryable
        if retryable, automaticallyReconnects, !retried, let requestedUDID {
            let instant = now()
            automaticReconnectTimes.removeAll { instant - $0 >= 60 }
            guard automaticReconnectTimes.count < 3 else { return }
            retried = true
            automaticReconnectTimes.append(instant)
            start(udid: requestedUDID)
        }
    }
}

@MainActor
final class SimulatorXPCTransport: NSObject, SimulatorDisplayTransport, SimulatorBridgeClientProtocol {
    private let connection: NSXPCConnection
    private var changed: (@MainActor (SimulatorDisplayInfo) -> Void)?
    private var failed: (@MainActor (String) -> Void)?

    override convenience init() {
        self.init(connection: NSXPCConnection(serviceName: (Bundle.main.bundleIdentifier ?? "com.phlox.Phlox") + ".SimulatorBridge"))
    }

    init(connection: NSXPCConnection) {
        self.connection = connection
        super.init()
    }

    func resume(surfaceChanged: @escaping @MainActor (SimulatorDisplayInfo) -> Void,
                failed: @escaping @MainActor (String) -> Void) {
        changed = surfaceChanged
        self.failed = failed
        connection.remoteObjectInterface = SimulatorBridgeInterfaces.service()
        connection.exportedInterface = SimulatorBridgeInterfaces.client()
        connection.exportedObject = self
        connection.interruptionHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.failed?("補助プロセスとの通信が中断しました") }
        }
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.failed?("補助プロセスとの接続が終了しました") }
        }
        connection.resume()
    }

    private var service: (any SimulatorBridgeProtocol)? {
        connection.remoteObjectProxyWithErrorHandler { @Sendable [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in self?.failed?(message) }
        } as? any SimulatorBridgeProtocol
    }

    func probe(reply: @escaping @MainActor (SimulatorBridgeCapability) -> Void) {
        service?.probe { @Sendable capability in
            let delivery = Delivery(capability)
            Task { @MainActor in reply(delivery.value) }
        }
    }

    func attach(udid: String, generation: Int,
                reply: @escaping @MainActor (SimulatorDisplayInfo?, NSError?) -> Void) {
        service?.attach(udid: udid, generation: generation) { @Sendable info, error in
            let delivery = Delivery((info, error))
            Task { @MainActor in reply(delivery.value.0, delivery.value.1) }
        }
    }

    func detach(udid: String) { service?.detach(udid: udid) }
    func sendTouch(udid: String, phase: Int, x: Double, y: Double) {
        service?.sendTouch(udid: udid, phase: phase, x: x, y: y)
    }
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double, phase: Int) {
        service?.sendScroll(udid: udid, dx: dx, dy: dy, x: x, y: y, phase: phase)
    }
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool) {
        service?.sendKey(udid: udid, keyCode: keyCode, modifiers: modifiers, down: down)
    }
    func sendButton(udid: String, button: Int) { service?.sendButton(udid: udid, button: button) }
    func releaseAll(udid: String) { service?.releaseAll(udid: udid) }

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
