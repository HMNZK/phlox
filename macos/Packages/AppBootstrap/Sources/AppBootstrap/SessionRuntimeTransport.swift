import CryptoKit
import Darwin
import DashboardFeature
import Foundation
import LocalHTTPServer
import Network
import Security
import os

public enum SessionRuntimeConnectionError: Error, LocalizedError, Sendable, Equatable {
    case invalidEndpoint
    case unauthorized
    case incompatibleProtocol
    case staleGeneration
    case expiredOperation
    case operationConflict
    case busy
    case responseTooLarge
    case disconnected
    case runtimeUnavailable(String)
    case rejected(String)
    case resultUnknown(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "実行サービスの接続先が不正です。"
        case .unauthorized: "実行サービスの認証に失敗しました。"
        case .incompatibleProtocol: "実行サービスとのバージョン互換性がありません。"
        case .staleGeneration: "実行サービスが切り替わりました。再接続が必要です。"
        case .expiredOperation: "操作の有効期限が切れました。"
        case .operationConflict: "同じ操作番号で内容が異なる要求を受信しました。"
        case .busy: "実行サービスの操作数が上限に達しています。"
        case .responseTooLarge: "実行サービスの応答がサイズ上限を超えています。"
        case .disconnected: "実行サービスとの接続が切れました。"
        case .runtimeUnavailable(let reason): "実行サービスに接続できません。\(reason)"
        case .rejected(let reason): reason
        case .resultUnknown(let id): "操作の結果を確認できません。自動再送は行いません。操作番号 \(id)"
        }
    }
}

public struct SessionRuntimeEndpoint: Sendable {
    public static let protocolVersion = 1
    public let url: URL
    public let generation: UUID
    let token: String

    public init(url: URL, generation: UUID, token: String) throws {
        guard url.scheme == "http", url.host == "127.0.0.1", let port = url.port,
              (1...65535).contains(port), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, ["", "/"].contains(url.path),
              !token.isEmpty else { throw SessionRuntimeConnectionError.invalidEndpoint }
        self.url = url
        self.generation = generation
        self.token = token
    }
}

struct SessionRuntimeOperation: Codable, Sendable {
    let id: UUID
    let generation: UUID
    let issuedAt: Date
    let payload: Data

    init(id: UUID = UUID(), generation: UUID, issuedAt: Date = Date(), payload: Data) {
        self.id = id
        self.generation = generation
        self.issuedAt = issuedAt
        self.payload = payload
    }
}

struct SessionRuntimeHandshake: Codable, Sendable {
    let protocolVersion: Int
    let generation: UUID
    var supportsControlSkills: Bool? = nil
}

struct SessionRuntimeSnapshotEnvelope: Codable, Sendable {
    let sequence: UInt64
    let snapshot: DashboardRuntimeSnapshot
}

private struct SessionRuntimeSnapshotSequence: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: UInt64(0))
    func next() -> UInt64 { value.withLock { $0 += 1; return $0 } }
}

struct SessionRuntimeFailure: Codable, Sendable {
    let message: String
}

struct SessionRuntimeAuthorization: Sendable {
    let token: String

    func accepts(_ header: String?) -> Bool {
        guard let header else { return false }
        let expected = Array("Bearer \(token)".utf8)
        let actual = Array(header.utf8)
        guard expected.count == actual.count else { return false }
        return zip(expected, actual).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

actor SessionRuntimeCommandLedger {
    nonisolated let generation: UUID
    private struct Entry {
        let digest: Data
        let issuedAt: Date
        let task: Task<Data, Error>
        let urgent: Bool
        var reservedBytes: Int
        var completed: Bool
    }
    private var entries: [UUID: Entry] = [:]
    private let maximumOperations: Int
    private let maximumBytes: Int
    private let reservedUrgentOperations: Int
    private let reservedUrgentBytes: Int
    static let maximumReplyBytes = SessionRuntimeTransport.maximumCommandReplyBytes
    private var reservedBytes = 0
    private var urgentBytes = 0
    private var urgentOperations = 0
    private var latestObservedTime = Date.distantPast

    init(generation: UUID, maximumOperations: Int = 8192, maximumBytes: Int = 256 * 1024 * 1024) {
        self.generation = generation
        self.maximumOperations = maximumOperations
        self.maximumBytes = maximumBytes
        self.reservedUrgentOperations = min(128, maximumOperations / 16)
        self.reservedUrgentBytes = maximumBytes / 16
    }

    func perform(
        _ operation: SessionRuntimeOperation,
        now: Date = Date(),
        scope: String = "",
        maximumResultBytes: Int = SessionRuntimeTransport.maximumCommandReplyBytes,
        urgent: Bool = false,
        execute: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        guard operation.generation == generation else { throw SessionRuntimeConnectionError.staleGeneration }
        let now = max(now, latestObservedTime)
        latestObservedTime = now
        let age = now.timeIntervalSince(operation.issuedAt)
        guard age >= -5, age < 120 else { throw SessionRuntimeConnectionError.expiredOperation }
        var hasher = SHA256()
        hasher.update(data: Data(scope.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: operation.payload)
        let digest = Data(hasher.finalize())
        if let entry = entries[operation.id] {
            guard entry.digest == digest, entry.issuedAt == operation.issuedAt, entry.urgent == urgent else {
                throw SessionRuntimeConnectionError.operationConflict
            }
            return try await entry.task.value
        }
        let expired = entries.filter { $0.value.completed && now.timeIntervalSince($0.value.issuedAt) >= 120 }
        for (id, entry) in expired {
            reservedBytes -= entry.reservedBytes
            if entry.urgent { urgentBytes -= entry.reservedBytes; urgentOperations -= 1 }
            entries.removeValue(forKey: id)
        }
        guard (0...Self.maximumReplyBytes).contains(maximumResultBytes) else {
            throw SessionRuntimeConnectionError.responseTooLarge
        }
        let reservation = operation.payload.count + maximumResultBytes + 1024
        let availableBytes = urgent ? reservedUrgentBytes - urgentBytes : maximumBytes - reservedUrgentBytes - (reservedBytes - urgentBytes)
        let availableOperations = urgent ? reservedUrgentOperations - urgentOperations : maximumOperations - reservedUrgentOperations - (entries.count - urgentOperations)
        guard availableOperations > 0, reservation <= availableBytes else {
            throw SessionRuntimeConnectionError.busy
        }
        let task = Task {
            let result = try await execute()
            guard result.count <= maximumResultBytes else { throw SessionRuntimeConnectionError.responseTooLarge }
            return result
        }
        entries[operation.id] = Entry(digest: digest, issuedAt: operation.issuedAt, task: task, urgent: urgent, reservedBytes: reservation, completed: false)
        reservedBytes += reservation
        if urgent { urgentBytes += reservation; urgentOperations += 1 }
        let result = await task.result
        if var entry = entries[operation.id], !entry.completed {
            let retained = ((try? result.get().count) ?? 0) + 1024
            reservedBytes -= entry.reservedBytes - retained
            if entry.urgent { urgentBytes -= entry.reservedBytes - retained }
            entry.reservedBytes = retained
            entry.completed = true
            entries[operation.id] = entry
        }
        return try result.get()
    }
}

public enum SessionRuntimeCredentialStore {
    public static func load(storeURL: URL) throws -> String {
        let directory = try validatedDirectory(storeURL)
        let path = directory.appendingPathComponent("master-token").path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o777 == 0o600,
              info.st_nlink == 1, info.st_size == 64 else { throw SessionRuntimeConnectionError.unauthorized }
        var bytes = [UInt8](repeating: 0, count: 64)
        guard read(descriptor, &bytes, 64) == 64,
              bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SessionRuntimeConnectionError.unauthorized
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func loadOrCreate(storeURL: URL) throws -> String {
        let directory = try validatedDirectory(storeURL)
        let descriptor = open(directory.appendingPathComponent("master-token").path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if descriptor < 0 {
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return try load(storeURL: storeURL)
        }
        defer { close(descriptor) }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw SessionRuntimeConnectionError.runtimeUnavailable("認証情報を生成できません。")
        }
        let token = random.map { String(format: "%02x", $0) }.joined()
        let bytes = Array(token.utf8)
        guard fchmod(descriptor, 0o600) == 0,
              bytes.withUnsafeBytes({ write(descriptor, $0.baseAddress, $0.count) }) == bytes.count,
              fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return token
    }

    private static func validatedDirectory(_ storeURL: URL) throws -> URL {
        let directory = storeURL.appendingPathComponent("session-runtime", isDirectory: true)
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700 else {
            throw SessionRuntimeConnectionError.unauthorized
        }
        return directory
    }
}

public actor SessionRuntimeTransport {
    public static let maximumSnapshotBytes = 64 * 1024 * 1024
    public static let maximumRequestBytes = 160 * 1024 * 1024
    public static let maximumCommandReplyBytes = 128 * 1024 * 1024
    private let generation: UUID
    private let authorization: SessionRuntimeAuthorization
    private let snapshot: @MainActor @Sendable () throws -> DashboardRuntimeSnapshot
    private let command: @MainActor @Sendable (DashboardRuntimeCommand) async throws -> DashboardRuntimeReply
    private let applicationSnapshot: (@MainActor @Sendable () throws -> Data)?
    private let applicationCommand: (@MainActor @Sendable (Data) async throws -> Data)?
    private let ledger: SessionRuntimeCommandLedger
    private let snapshotSequence = SessionRuntimeSnapshotSequence()
    private let queue = DispatchQueue(label: "Phlox.SessionRuntimeTransport")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var receivingRequest = false
    private var pendingPayloadBytes = 0
    private var pendingUrgentPayloadBytes = 0
    private var pendingNormalCommands = 0
    private var pendingUrgentCommands = 0
    private var pendingReads = 0
    private let responseBudget = SessionRuntimeResponseBudget()

    private enum Request {
        case handshake
        case snapshot
        case applicationSnapshot
        case command(SessionRuntimeOperation, DashboardRuntimeCommand)
        case applicationCommand(SessionRuntimeOperation)
    }

    public init(
        generation: UUID,
        storeURL: URL,
        snapshot: @escaping @MainActor @Sendable () throws -> DashboardRuntimeSnapshot,
        command: @escaping @MainActor @Sendable (DashboardRuntimeCommand) async throws -> DashboardRuntimeReply,
        applicationSnapshot: (@MainActor @Sendable () throws -> Data)? = nil,
        applicationCommand: (@MainActor @Sendable (Data) async throws -> Data)? = nil
    ) throws {
        self.generation = generation
        self.authorization = SessionRuntimeAuthorization(token: try SessionRuntimeCredentialStore.loadOrCreate(storeURL: storeURL))
        self.snapshot = snapshot
        self.command = command
        self.applicationSnapshot = applicationSnapshot
        self.applicationCommand = applicationCommand
        self.ledger = SessionRuntimeCommandLedger(generation: generation)
    }

    public func start() async throws -> URL {
        guard listener == nil else { throw SessionRuntimeConnectionError.busy }
        let listener = try LocalHTTPListener.makeListener(port: 0)
        self.listener = listener
        do {
            let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue, maxConnections: 8) { [weak self] connection in
                guard let self else { connection.cancel(); return }
                Task { await self.handle(connection) }
            }
            return URL(string: "http://127.0.0.1:\(port)")!
        } catch {
            listener.cancel()
            self.listener = nil
            throw error
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func handle(_ connection: NWConnection) async {
        guard listener != nil, connections.count < 16 else { connection.cancel(); return }
        let connectionID = UUID()
        connections[connectionID] = connection
        var commandAdmission: (bytes: Int, urgent: Bool)?
        var readAdmitted = false
        defer {
            if let commandAdmission { finishCommand(payloadBytes: commandAdmission.bytes, urgent: commandAdmission.urgent) }
            if readAdmitted { pendingReads -= 1 }
            connections.removeValue(forKey: connectionID)
            connection.cancel()
        }
        do {
            try await LocalHTTPConnection.startAndWaitUntilReady(connection, queue: queue)
            let request = try await receive(from: connection)
            let body: Data
            let maximumResponseBytes: Int
            switch request {
            case .handshake:
                maximumResponseBytes = Self.maximumSnapshotBytes
                guard pendingReads < 2 else { throw SessionRuntimeConnectionError.busy }
                pendingReads += 1
                readAdmitted = true
                body = try JSONEncoder().encode(SessionRuntimeHandshake(protocolVersion: SessionRuntimeEndpoint.protocolVersion, generation: generation, supportsControlSkills: true))
            case .snapshot:
                maximumResponseBytes = Self.maximumSnapshotBytes
                guard pendingReads < 2 else { throw SessionRuntimeConnectionError.busy }
                pendingReads += 1
                readAdmitted = true
                let provider = snapshot
                let sequence = snapshotSequence
                body = try await MainActor.run {
                    let snapshot = try provider()
                    return try JSONEncoder().encode(SessionRuntimeSnapshotEnvelope(sequence: sequence.next(), snapshot: snapshot))
                }
            case .applicationSnapshot:
                maximumResponseBytes = Self.maximumSnapshotBytes
                guard pendingReads < 2 else { throw SessionRuntimeConnectionError.busy }
                pendingReads += 1
                readAdmitted = true
                guard let applicationSnapshot else { throw SessionRuntimeConnectionError.rejected("アプリ設定の共有には対応していません。") }
                body = try await applicationSnapshot()
            case .command(let operation, let decoded):
                maximumResponseBytes = Self.maximumCommandReplyBytes
                try admitCommand(payloadBytes: operation.payload.count, urgent: decoded.isRuntimeUrgent)
                commandAdmission = (operation.payload.count, decoded.isRuntimeUrgent)
                let command = self.command
                body = try await ledger.perform(operation, scope: "/command", maximumResultBytes: decoded.maximumRuntimeReplyBytes, urgent: decoded.isRuntimeUrgent) {
                    return try await JSONEncoder().encode(command(decoded))
                }
            case .applicationCommand(let operation):
                maximumResponseBytes = Self.maximumCommandReplyBytes
                try admitCommand(payloadBytes: operation.payload.count, urgent: false)
                commandAdmission = (operation.payload.count, false)
                guard let applicationCommand else { throw SessionRuntimeConnectionError.rejected("アプリ設定の変更には対応していません。") }
                body = try await ledger.perform(operation, scope: "/application-command") {
                    try await applicationCommand(operation.payload)
                }
            }
            guard body.count <= maximumResponseBytes else { throw SessionRuntimeConnectionError.responseTooLarge }
            await send(status: 200, body: body, connection: connection)
        } catch {
            let status: Int
            switch error {
            case SessionRuntimeConnectionError.unauthorized: status = 401
            case SessionRuntimeConnectionError.busy: status = 503
            case SessionRuntimeConnectionError.staleGeneration, SessionRuntimeConnectionError.incompatibleProtocol,
                 SessionRuntimeConnectionError.operationConflict: status = 409
            case SessionRuntimeConnectionError.responseTooLarge, HTTPMessageParserError.payloadTooLarge: status = 413
            default: status = 400
            }
            let body = (try? JSONEncoder().encode(SessionRuntimeFailure(message: String(error.localizedDescription.prefix(8192))))) ?? Data()
            await send(status: status, body: body, connection: connection)
        }
    }

    private func receive(from connection: NWConnection) async throws -> Request {
        guard !receivingRequest else { throw SessionRuntimeConnectionError.busy }
        receivingRequest = true
        defer { receivingRequest = false }
        let request = try await LocalHTTPConnection.receiveRequest(from: connection, timeout: .seconds(10), maxBodyLength: Self.maximumRequestBytes)
        guard listener != nil else { throw SessionRuntimeConnectionError.disconnected }
        guard authorization.accepts(request.headers["authorization"]) else { throw SessionRuntimeConnectionError.unauthorized }
        guard request.headers["x-phlox-runtime-protocol"] == String(SessionRuntimeEndpoint.protocolVersion) else {
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }
        guard request.headers["x-phlox-runtime-generation"] == generation.uuidString else {
            throw SessionRuntimeConnectionError.staleGeneration
        }
        switch (request.method, request.target) {
        case ("GET", "/handshake"): return .handshake
        case ("GET", "/snapshot"): return .snapshot
        case ("GET", "/application-snapshot"): return .applicationSnapshot
        case ("POST", "/command"):
            let operation = try JSONDecoder().decode(SessionRuntimeOperation.self, from: request.body)
            return .command(operation, try JSONDecoder().decode(DashboardRuntimeCommand.self, from: operation.payload))
        case ("POST", "/application-command"):
            return .applicationCommand(try JSONDecoder().decode(SessionRuntimeOperation.self, from: request.body))
        default: throw SessionRuntimeConnectionError.rejected("実行サービスの要求形式が不正です。")
        }
    }

    private func admitCommand(payloadBytes: Int, urgent: Bool) throws {
        let availableBytes = urgent ? 16 * 1024 * 1024 - pendingUrgentPayloadBytes : 240 * 1024 * 1024 - (pendingPayloadBytes - pendingUrgentPayloadBytes)
        guard payloadBytes <= availableBytes,
              (urgent ? pendingUrgentCommands < 2 : pendingNormalCommands < 4) else {
            throw SessionRuntimeConnectionError.busy
        }
        pendingPayloadBytes += payloadBytes
        if urgent { pendingUrgentPayloadBytes += payloadBytes }
        if urgent { pendingUrgentCommands += 1 } else { pendingNormalCommands += 1 }
    }

    private func finishCommand(payloadBytes: Int, urgent: Bool) {
        pendingPayloadBytes -= payloadBytes
        if urgent { pendingUrgentPayloadBytes -= payloadBytes }
        if urgent { pendingUrgentCommands -= 1 } else { pendingNormalCommands -= 1 }
    }

    private func send(status: Int, body: Data, connection: NWConnection) async {
        await responseBudget.acquire(body.count + 1024)
        let data = HTTPResponseSerializer.serialize(statusCode: status, statusText: status == 200 ? "OK" : "Error", contentType: "application/json", body: body)
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
            connection.cancel()
        }
        await LocalHTTPConnection.sendAndClose(data, over: connection)
        timeout.cancel()
        await responseBudget.release(body.count + 1024)
    }
}

extension DashboardRuntimeCommand {
    var isRuntimeUrgent: Bool {
        if case .session(_, _, .recoverLaunchDraft) = self { return false }
        return isImmediateSessionControl
    }

    var maximumRuntimeReplyBytes: Int {
        switch self {
        case .session(_, _, .revert), .session(_, _, .recoverLaunchDraft), .history: SessionRuntimeTransport.maximumCommandReplyBytes
        default: 1024 * 1024
        }
    }
}

private actor SessionRuntimeResponseBudget {
    private let maximumBytes = SessionRuntimeTransport.maximumCommandReplyBytes + 1024
    private var reservedBytes = 0
    private var waiters: [(bytes: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func acquire(_ bytes: Int) async {
        if waiters.isEmpty, bytes <= maximumBytes - reservedBytes { reservedBytes += bytes; return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append((bytes, continuation))
        }
    }

    func release(_ bytes: Int) {
        reservedBytes -= bytes
        while let first = waiters.first, first.bytes <= maximumBytes - reservedBytes {
            reservedBytes += first.bytes
            waiters.removeFirst().continuation.resume()
        }
    }
}
