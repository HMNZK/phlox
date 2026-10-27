import DashboardFeature
import Foundation

struct SessionRuntimeReceivedSnapshot {
    let envelope: SessionRuntimeSnapshotEnvelope
    let startedAt: ContinuousClock.Instant
    func isFresh(at now: ContinuousClock.Instant = ContinuousClock.now) -> Bool { startedAt.duration(to: now) <= .seconds(35) }
}

@MainActor
public final class SessionRuntimeClient {
    public let endpoint: SessionRuntimeEndpoint
    public var onCommandSnapshot: (@MainActor (DashboardRuntimeSnapshot) async throws -> Void)?
    private var pollingTask: Task<Void, Never>?
    private var lastAppliedSequence: UInt64 = 0
    private var latestSnapshot: SessionRuntimeReceivedSnapshot?
    private var latestReceivedSequence: UInt64 = 0
    private var supportsControlSkills = false
    private var pendingOperationBytes = 0
    private var pendingOperationCount = 0
    private var pendingUrgentOperationBytes = 0
    private var pendingUrgentOperationCount = 0
    private let snapshotDecoder: @Sendable (Data) throws -> SessionRuntimeSnapshotEnvelope
    private enum RequestLane: Hashable {
        case read, snapshot, command, urgent
        var maximumActive: Int { switch self { case .read, .snapshot: 2; case .command: 3; case .urgent: 1 } }
        var maximumQueued: Int { switch self { case .read, .snapshot: 8; case .command: 20; case .urgent: 4 } }
    }
    private var activeRequests: [RequestLane: Int] = [:]
    private var requestWaiters: [(id: UUID, lane: RequestLane, continuation: CheckedContinuation<Void, Error>)] = []

    public convenience init(endpoint: SessionRuntimeEndpoint) {
        self.init(endpoint: endpoint) { try JSONDecoder().decode(SessionRuntimeSnapshotEnvelope.self, from: $0) }
    }

    init(endpoint: SessionRuntimeEndpoint, snapshotDecoder: @escaping @Sendable (Data) throws -> SessionRuntimeSnapshotEnvelope) {
        self.endpoint = endpoint
        self.snapshotDecoder = snapshotDecoder
    }

    public func handshake() async throws {
        let response = try await read(path: "handshake")
        let handshake = try JSONDecoder().decode(SessionRuntimeHandshake.self, from: response)
        try acceptHandshake(handshake)
    }

    func acceptHandshake(_ handshake: SessionRuntimeHandshake) throws {
        guard handshake.protocolVersion == SessionRuntimeEndpoint.protocolVersion else {
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }
        guard handshake.generation == endpoint.generation else { throw SessionRuntimeConnectionError.staleGeneration }
        supportsControlSkills = handshake.supportsControlSkills == true
    }

    public func snapshot() async throws -> DashboardRuntimeSnapshot {
        try await fetchSnapshot().snapshot
    }

    public func command(_ command: DashboardRuntimeCommand) async throws -> DashboardRuntimeReply {
        if !supportsControlSkills {
            switch command {
            case .message(let request) where request.skill != nil:
                throw SessionRuntimeConnectionError.incompatibleProtocol
            case .session(_, _, .sendControlSkill):
                throw SessionRuntimeConnectionError.incompatibleProtocol
            default: break
            }
        }
        guard pendingOperationCount < 64 else { throw SessionRuntimeConnectionError.busy }
        let payload = try JSONEncoder().encode(command)
        let result = try await perform(payload, path: "command", urgent: command.isRuntimeUrgent)
        do {
            let reply = try JSONDecoder().decode(DashboardRuntimeReply.self, from: result.data)
            if let onCommandSnapshot {
                let envelope = try await fetchSnapshot()
                try await apply(envelope, using: onCommandSnapshot)
            }
            return reply
        } catch {
            throw SessionRuntimeConnectionError.resultUnknown(result.id)
        }
    }

    public func applicationSnapshot() async throws -> Data {
        try await read(path: "application-snapshot")
    }

    public func applicationCommand(_ payload: Data) async throws -> Data {
        return try await perform(payload, path: "application-command").data
    }

    public func startPolling(
        interval: Duration = .milliseconds(250),
        onSnapshot: @escaping @MainActor (DashboardRuntimeSnapshot) async throws -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        disconnect()
        pollingTask = Task { [weak self] in
            var recoveryDelay = Duration.seconds(1)
            do {
                while !Task.isCancelled {
                    guard let self else { return }
                    do {
                        let envelope = try await self.fetchSnapshot()
                        try Task.checkCancellation()
                        try await self.apply(envelope, using: onSnapshot)
                        recoveryDelay = .seconds(1)
                    } catch SessionRuntimeConnectionError.busy {
                        try await Task.sleep(for: interval)
                        continue
                    } catch let error as URLError where error.code == .timedOut {
                        try Task.checkCancellation()
                        onFailure(error)
                        try await Task.sleep(for: recoveryDelay)
                        recoveryDelay = min(recoveryDelay * 2, .seconds(8))
                        continue
                    }
                    try await Task.sleep(for: interval)
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { onFailure(error) }
            }
        }
    }

    public func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func fetchSnapshot() async throws -> SessionRuntimeSnapshotEnvelope {
        for _ in 0..<3 {
            if let latestSnapshot, !latestSnapshot.isFresh() { self.latestSnapshot = nil }
            let startedAt = ContinuousClock.now
            let envelope = try await readSnapshot()
            try Task.checkCancellation()
            let received = SessionRuntimeReceivedSnapshot(envelope: envelope, startedAt: startedAt)
            guard received.isFresh(), envelope.sequence >= latestReceivedSequence else { continue }
            latestReceivedSequence = envelope.sequence
            latestSnapshot = received
            return envelope
        }
        throw SessionRuntimeConnectionError.runtimeUnavailable("新しい画面状態を期限内に取得できません。")
    }

    private func readSnapshot() async throws -> SessionRuntimeSnapshotEnvelope {
        let deadline = ContinuousClock.now + .seconds(30)
        while true {
            do {
                try await acquireRequest(lane: .snapshot)
                break
            } catch SessionRuntimeConnectionError.busy {
                guard ContinuousClock.now < deadline else { throw SessionRuntimeConnectionError.busy }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { releaseRequest(lane: .snapshot) }
        let data = try await read(path: "snapshot")
        let snapshotDecoder = snapshotDecoder
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let snapshot = try snapshotDecoder(data)
            try Task.checkCancellation()
            return snapshot
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func apply(_ envelope: SessionRuntimeSnapshotEnvelope, using handler: @MainActor (DashboardRuntimeSnapshot) async throws -> Void) async throws {
        var current = envelope
        if latestSnapshot?.envelope.sequence != envelope.sequence || latestSnapshot?.isFresh() != true {
            current = try await fetchSnapshot()
        }
        guard current.sequence > lastAppliedSequence else { return }
        lastAppliedSequence = current.sequence
        try await handler(current.snapshot)
    }

    private func perform(_ payload: Data, path: String, urgent: Bool = false) async throws -> (data: Data, id: UUID) {
        guard payload.count <= (SessionRuntimeTransport.maximumRequestBytes - 4096) / 4 * 3 else {
            throw SessionRuntimeConnectionError.rejected("操作データがサイズ上限を超えています。")
        }
        let availableBytes = urgent ? 16 * 1024 * 1024 - pendingUrgentOperationBytes : 240 * 1024 * 1024 - (pendingOperationBytes - pendingUrgentOperationBytes)
        let availableCount = urgent ? 8 - pendingUrgentOperationCount : 56 - (pendingOperationCount - pendingUrgentOperationCount)
        guard availableCount > 0, payload.count <= availableBytes else {
            throw SessionRuntimeConnectionError.busy
        }
        pendingOperationCount += 1
        pendingOperationBytes += payload.count
        if urgent { pendingUrgentOperationCount += 1; pendingUrgentOperationBytes += payload.count }
        defer {
            pendingOperationCount -= 1
            pendingOperationBytes -= payload.count
            if urgent { pendingUrgentOperationCount -= 1; pendingUrgentOperationBytes -= payload.count }
        }
        let operation = SessionRuntimeOperation(generation: endpoint.generation, payload: payload)
        let body = try JSONEncoder().encode(operation)
        guard body.count <= SessionRuntimeTransport.maximumRequestBytes else {
            throw SessionRuntimeConnectionError.rejected("操作データがサイズ上限を超えています。")
        }
        do {
            let deadline = ContinuousClock.now + .seconds(30)
            while true {
                do { return (try await request(path: path, body: body, urgent: urgent), operation.id) }
                catch SessionRuntimeConnectionError.busy {
                    guard ContinuousClock.now < deadline else { throw SessionRuntimeConnectionError.busy }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
        } catch let error as SessionRuntimeConnectionError {
            if error == .responseTooLarge || error == .disconnected {
                throw SessionRuntimeConnectionError.resultUnknown(operation.id)
            }
            throw error
        } catch {
            throw SessionRuntimeConnectionError.resultUnknown(operation.id)
        }
    }

    private func request(path: String, body: Data? = nil, urgent: Bool = false) async throws -> Data {
        let lane: RequestLane = body == nil ? .read : urgent ? .urgent : .command
        try await acquireRequest(lane: lane)
        defer { releaseRequest(lane: lane) }
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint.url.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.setValue(String(SessionRuntimeEndpoint.protocolVersion), forHTTPHeaderField: "X-Phlox-Runtime-Protocol")
        request.setValue(endpoint.generation.uuidString, forHTTPHeaderField: "X-Phlox-Runtime-Generation")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let maximumBytes = body == nil ? SessionRuntimeTransport.maximumSnapshotBytes : SessionRuntimeTransport.maximumCommandReplyBytes
        let (data, response) = try await BoundedRuntimeRequest.load(request, maximumBytes: maximumBytes)
        switch response.statusCode {
        case 200: return data
        case 401: throw SessionRuntimeConnectionError.unauthorized
        case 409: throw SessionRuntimeConnectionError.rejected(Self.failureMessage(data))
        case 413: throw SessionRuntimeConnectionError.responseTooLarge
        case 503: throw SessionRuntimeConnectionError.busy
        default: throw SessionRuntimeConnectionError.rejected(Self.failureMessage(data))
        }
    }

    private func read(path: String) async throws -> Data {
        let deadline = ContinuousClock.now + .seconds(30)
        while true {
            do { return try await request(path: path) }
            catch SessionRuntimeConnectionError.busy {
                guard ContinuousClock.now < deadline else { throw SessionRuntimeConnectionError.busy }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func acquireRequest(lane: RequestLane) async throws {
        try Task.checkCancellation()
        if activeRequests[lane, default: 0] < lane.maximumActive, !requestWaiters.contains(where: { $0.lane == lane }) {
            activeRequests[lane, default: 0] += 1
            return
        }
        guard requestWaiters.lazy.filter({ $0.lane == lane }).count < lane.maximumQueued else { throw SessionRuntimeConnectionError.busy }
        let id = UUID()
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(35)) }
            catch { return }
            self?.failRequestWaiter(id, error: SessionRuntimeConnectionError.busy)
        }
        defer { timeout.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { requestWaiters.append((id, lane, continuation)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.failRequestWaiter(id, error: CancellationError()) }
        }
    }

    private func releaseRequest(lane: RequestLane) {
        activeRequests[lane, default: 0] -= 1
        if let index = requestWaiters.firstIndex(where: { $0.lane == lane }) {
            activeRequests[lane, default: 0] += 1
            requestWaiters.remove(at: index).continuation.resume()
        }
    }

    private func failRequestWaiter(_ id: UUID, error: Error) {
        guard let index = requestWaiters.firstIndex(where: { $0.id == id }) else { return }
        requestWaiters.remove(at: index).continuation.resume(throwing: error)
    }

    private static func failureMessage(_ data: Data) -> String {
        (try? JSONDecoder().decode(SessionRuntimeFailure.self, from: data).message) ?? "実行サービスが操作を拒否しました。"
    }

    deinit { pollingTask?.cancel() }
}

private final class BoundedRuntimeRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var cancelled = false

    private init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    static func load(_ request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let delegate = BoundedRuntimeRequest(maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(request, continuation: continuation)
            }
        } onCancel: { delegate.cancel() }
    }

    private func start(_ request: URLRequest, continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        let task = lock.withLock { () -> URLSessionDataTask? in
            guard !cancelled else { return nil }
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.connectionProxyDictionary = [:]
            configuration.timeoutIntervalForResource = 35
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: request)
            self.task = task
            return task
        }
        guard let task else { continuation.resume(throwing: CancellationError()); return }
        task.resume()
    }

    private func cancel() {
        lock.withLock { cancelled = true }
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        let completion = lock.withLock { () -> (CheckedContinuation<(Data, HTTPURLResponse), Error>?, URLSession?) in
            let completion = (continuation, session)
            continuation = nil
            session = nil
            task = nil
            data = Data()
            return completion
        }
        completion.1?.invalidateAndCancel()
        completion.0?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel)
            finish(.failure(SessionRuntimeConnectionError.responseTooLarge))
            return
        }
        lock.withLock { self.response = response }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let overflow = lock.withLock {
            guard continuation != nil else { return false }
            guard chunk.count <= maximumBytes - data.count else { return true }
            data.append(chunk)
            return false
        }
        if overflow { finish(.failure(SessionRuntimeConnectionError.responseTooLarge)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<(Data, HTTPURLResponse), Error> = lock.withLock {
            if let error { return .failure(error) }
            guard let response else { return .failure(SessionRuntimeConnectionError.disconnected) }
            return .success((data, response))
        }
        finish(result)
    }
}
