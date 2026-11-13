import Darwin
import Foundation

/// 計画的なホスト更新で、旧ホストが新ホストへ渡す確定点（ADR 0233）。
/// 旧ホストがコミット前に原子的に書き（fsync）、新ホストが採用前に読む。チェックポイントが無い／読めないときは何も採用しない。
public struct HandoverSession: Codable, Sendable, Equatable {
    /// `SessionID`のUUID文字列。
    public var sessionID: String
    /// `codex` / `claudeCode`。
    public var agent: String
    /// 採用先のholder（カタログ走査ではなく、この記録で解決する）。
    public var holder: HolderRecord
    /// 旧ホストが内部状態へ反映済みの最後の受信番号。新ホストはこれより後だけを受け取る。
    public var appliedSeq: UInt64
    /// エージェント別のクライアント状態（JSON）。
    public var clientState: Data
    /// 子の環境にある認証トークン（`PHLOX_TOKEN`）。新ホストが同じセッションへ再登録する。秘密なので、消費時に外す。
    /// 無い（旧形式）なら新ホストは新しいトークンを発行する。
    public var token: String?

    public init(sessionID: String, agent: String, holder: HolderRecord, appliedSeq: UInt64, clientState: Data,
                token: String? = nil) {
        self.sessionID = sessionID
        self.agent = agent
        self.holder = holder
        self.appliedSeq = appliedSeq
        self.clientState = clientState
        self.token = token
    }
}

public struct HandoverCheckpoint: Codable, Sendable, Equatable {
    /// 形式の版。読めない版のチェックポイントは採用しない。
    public static let formatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    /// 書いたホストの世代ID。
    public var sourceGeneration: String
    /// 子（hook/Control）が環境変数に固定しているポート。新ホストは同じポートを厳密に束縛する。
    public var hookPort: Int?
    public var controlPort: Int?
    public var sessions: [HandoverSession]

    public init(
        createdAt: Date = Date(), sourceGeneration: String, hookPort: Int?, controlPort: Int?, sessions: [HandoverSession]
    ) {
        formatVersion = Self.formatVersion
        self.createdAt = createdAt
        self.sourceGeneration = sourceGeneration
        self.hookPort = hookPort
        self.controlPort = controlPort
        self.sessions = sessions
    }
}

public enum HandoverCheckpointError: Error, Equatable, Sendable {
    case unsafeFile(String)
    case unsupportedFormat(Int)
    case system(String, Int32)
}

/// `<store>/session-runtime/handover/checkpoint.json`。採用済みは`consumed.json`へ改名して二重採用を防ぐ。
public enum HandoverCheckpointStore {
    public static let maximumBytes = 256 * 1024 * 1024

    public static func checkpointURL(directory: URL) -> URL { directory.appendingPathComponent("checkpoint.json") }

    private static func consumedURL(directory: URL) -> URL { directory.appendingPathComponent("consumed.json") }

    /// 原子的に書いてfsyncする。書き終えるまで、読み手には古い（または無い）状態だけが見える。
    public static func write(_ checkpoint: HandoverCheckpoint, directory: URL) throws {
        try HolderDirectory.ensurePrivate(directory.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)
        let final = checkpointURL(directory: directory)
        let temporary = directory.appendingPathComponent(".checkpoint-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw HandoverCheckpointError.system("open", errno) }
        var renamed = false
        defer {
            close(descriptor)
            if !renamed { unlink(temporary.path) }
        }
        do { try HolderWire.writeAll(descriptor, data) } catch { throw HandoverCheckpointError.system("write", errno) }
        guard fsync(descriptor) == 0 else { throw HandoverCheckpointError.system("fsync", errno) }
        guard rename(temporary.path, final.path) == 0 else { throw HandoverCheckpointError.system("rename", errno) }
        renamed = true
        let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            close(directoryDescriptor)
        }
    }

    /// 無ければnil。あっても所有者・種別・モード・版が不正なら例外（採用しない。黙って無視もしない）。
    public static func read(directory: URL) throws -> HandoverCheckpoint? {
        let url = checkpointURL(directory: directory)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw HandoverCheckpointError.unsafeFile(url.path)
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1, info.st_size <= maximumBytes else {
            throw HandoverCheckpointError.unsafeFile(url.path)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let checkpoint = try decoder.decode(HandoverCheckpoint.self, from: data)
        guard checkpoint.formatVersion == HandoverCheckpoint.formatVersion else {
            throw HandoverCheckpointError.unsupportedFormat(checkpoint.formatVersion)
        }
        return checkpoint
    }

    /// 全項目を外し終えたチェックポイントを退避する（再起動しても二重に採用しない）。一部だけ外すときは`consume`を使う。
    public static func markConsumed(directory: URL) throws {
        // 消費済みの記録に秘密を残さない。トークンを外して書き直してから改名する。
        if var checkpoint = try read(directory: directory), checkpoint.sessions.contains(where: { $0.token != nil }) {
            for index in checkpoint.sessions.indices { checkpoint.sessions[index].token = nil }
            try write(checkpoint, directory: directory)
        }
        guard rename(checkpointURL(directory: directory).path, consumedURL(directory: directory).path) == 0 else {
            throw HandoverCheckpointError.system("rename", errno)
        }
    }

    /// 自分（`sourceGeneration`）が書いた確定点だけを消す。確定点を書いた後に更新を中止したとき、
    /// 次のホスト起動が、終了済みの子を指す古い確定点を採用しないようにする。
    /// 他の世代が書いたもの・読めないもの（不正な所有者やモード）には触れない。消したらtrue。
    @discardableResult
    public static func discard(sourceGeneration: String, directory: URL) throws -> Bool {
        guard let checkpoint = try read(directory: directory), checkpoint.sourceGeneration == sourceGeneration else { return false }
        guard unlink(checkpointURL(directory: directory).path) == 0 else { throw HandoverCheckpointError.system("unlink", errno) }
        return true
    }

    /// 採用に成功した（または利用者が明示的に放棄した）セッションの項目だけを外す。
    /// 残りがあれば原子的に書き直す（残った項目は次の起動で再び採用を試みる）。残りが無ければ全体を消費済みにする。
    /// 該当する項目が無ければ何も変えない。
    public static func consume(sessionIDs: Set<String>, directory: URL) throws {
        guard var checkpoint = try read(directory: directory) else { return }
        let remaining = checkpoint.sessions.filter { !sessionIDs.contains($0.sessionID) }
        guard remaining.count != checkpoint.sessions.count else { return }
        if remaining.isEmpty {
            try markConsumed(directory: directory)
        } else {
            checkpoint.sessions = remaining
            try write(checkpoint, directory: directory)
        }
    }
}
