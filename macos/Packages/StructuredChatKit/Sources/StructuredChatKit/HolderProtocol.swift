import Darwin
import Foundation

/// 子プロセスの寿命を保持するholderとの通信契約（ADR 0233）。
/// holderはプロトコルを解釈せず、子の標準出力の各行に通し番号（seq、1から）を付けて保持する。
public enum HolderProtocol {
    /// 通信形式の版。能力を広げるときは`hello`の応答で表し、この値は互換が切れるときだけ上げる。
    public static let version = 1
    /// 1フレームの上限。`LineDelimitedProcessTransport`の1行上限（64MiB＋読み取り1回分の64KiB）を、
    /// JSONの`Data`（base64で4/3に膨らむ）として載せられる大きさに、外枠の余裕（256KiB）を足す。
    public static let maximumFrameBytes = ((64 * 1024 * 1024 + 64 * 1024 + 2) / 3) * 4 + 256 * 1024
    /// 子ごとの保持量の目安。確認前の行がこれに達したら読み取りを止める（行は捨てない）。
    public static let defaultRetentionLimit = 64 * 1024 * 1024
}

public enum HolderSignal: String, Codable, Sendable {
    case interrupt
    case terminate
}

public enum HolderRequest: Codable, Sendable {
    case hello(version: Int)
    /// 書込権を取り、`fromSeq`より後の保持行を再送してから、以後の行を順に送る。
    case attach(fromSeq: UInt64)
    case write(epoch: UInt64, requestID: UInt64, sendID: UUID, data: Data)
    case signal(epoch: UInt64, requestID: UInt64, kind: HolderSignal)
    /// 常駐側が`seq`までを確定点へ反映した。以後その番号以下を破棄できる。
    case confirm(epoch: UInt64, seq: UInt64)
    case stderrTail(requestID: UInt64)
    case detach(epoch: UInt64)
}

public enum HolderReply: Codable, Sendable, Equatable {
    case written
    case failed(String)
    /// 古い世代の接続による操作。何も実行していない。
    case notWriter
    case text(String?)
    case ok
    /// 以前の接続が受け付けたが、書き切ったか確認できない送信。再送してはならない。
    case unknown
}

public struct HolderAttachInfo: Codable, Sendable, Equatable {
    public let epoch: UInt64
    /// 保持している最小のseq（行が無ければlastSeq+1）。確認前の行は捨てないので、確認済みより後は必ず保持されている。
    public let firstRetainedSeq: UInt64
    public let lastSeq: UInt64
    /// 保持量が上限に達して子の出力の読み取りを止めている（子はパイプが満杯になると進行が止まる）。確認が進むと再開する。
    public let backpressured: Bool
    /// 子が終了している場合の終了状態。
    public let exitStatus: Int32?
    /// 送信が書き切られたか確認できていない送信ID（再送しない）。
    public let unknownSendIDs: [UUID]
    public let childPID: Int32
}

public enum HolderFrame: Codable, Sendable {
    case hello(version: Int, holderID: String, holderPID: Int32, childPID: Int32)
    case attached(HolderAttachInfo)
    case line(seq: UInt64, data: Data)
    case reply(requestID: UInt64, result: HolderReply)
    case exited(status: Int32, lastSeq: UInt64)
    /// 新しい世代の接続に書込権を取られた。この接続は閉じられる。
    case evicted
}

/// holderの探索記録（`session-runtime/holders/<id>/holder.json`）。holder自身が原子的に書く。
public struct HolderRecord: Codable, Sendable, Equatable {
    public let holderID: String
    public let protocolVersion: Int
    public let holderPID: Int32
    public let childPID: Int32
    public let socketPath: String
    public let startedAt: Date
    /// 呼び出し側の識別情報（セッションID、エージェント種別など）。holderは解釈しない。
    public let metadata: [String: String]
}

/// holderを起動するための指定。環境変数に秘密を含むので、引数やファイルでなくholderの標準入力で渡す。
public struct HolderSpawnSpec: Codable, Sendable {
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String?
    public var metadata: [String: String]
    /// holder.jsonを置く専用ディレクトリ（0700で作られる）。
    public var recordDirectory: String
    /// ソケットを置く短いパスのディレクトリ（sockaddr_unの長さ制限のため`recordDirectory`と分ける）。
    public var socketDirectory: String
    public var retentionLimit: Int

    public init(
        command: String, arguments: [String], environment: [String: String], workingDirectory: String?,
        metadata: [String: String], recordDirectory: String, socketDirectory: String,
        retentionLimit: Int = HolderProtocol.defaultRetentionLimit
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.metadata = metadata
        self.recordDirectory = recordDirectory
        self.socketDirectory = socketDirectory
        self.retentionLimit = retentionLimit
    }
}

public enum HolderError: Error, Equatable, LocalizedError, Sendable {
    case connectionFailed(String)
    case incompatibleVersion(Int)
    case frameTooLarge(Int)
    case malformedFrame
    case disconnected
    /// 古い世代の接続のため拒否された。
    case notWriter
    /// 送信が書き切られたか確認できない。再送してはならない。
    case sendResultUnknown(UUID)
    case sendFailed(String)
    case launchFailed(String)
    case unsafePath(String)
    /// 計画的更新の確定中のため送信できない。何も送っていない。
    case handoverInProgress

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): "holderへ接続できません: \(reason)"
        case .incompatibleVersion(let version): "holderの通信版(\(version))に対応していません。"
        case .frameTooLarge(let size): "holderのフレームが大きすぎます(\(size)バイト)。"
        case .malformedFrame: "holderのフレームが不正です。"
        case .disconnected: "holderとの接続が切れました。"
        case .notWriter: "書込権がありません。新しい接続に置き換えられました。"
        case .sendResultUnknown: "送信の結果を確認できません。自動再送は行いません。"
        case .sendFailed(let reason): "送信に失敗しました: \(reason)"
        case .launchFailed(let reason): "holderを起動できません: \(reason)"
        case .unsafePath(let path): "安全でないholderのパスです: \(path)"
        case .handoverInProgress: "ホストの更新中のため送信できません。完了後にもう一度お試しください。"
        }
    }
}

/// 長さ（4バイト・ビッグエンディアン）つきのJSONフレーム。
enum HolderWire {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        // `Data`はbase64になる。既定のエンコーダは`/`を`\/`にエスケープするので、`/`ばかりのbase64（0xFFの列）は
        // 4/3でなく8/3に膨らみ、上限（4/3で見積もる）を超える。エスケープしない。
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let body = try encoder.encode(value)
        guard body.count <= HolderProtocol.maximumFrameBytes else { throw HolderError.frameTooLarge(body.count) }
        var length = UInt32(body.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(body)
        return data
    }

    static func writeAll(_ descriptor: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw HolderError.disconnected
                }
                if count == 0 { throw HolderError.disconnected }
                offset += count
            }
        }
    }

    /// 指定バイト数を読み切る。EOF・エラーはnil。
    static func readExactly(_ descriptor: Int32, count: Int) -> Data? {
        if count == 0 { return Data() }
        var result = Data(count: count)
        var offset = 0
        let ok = result.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while offset < count {
                let n = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if n == 0 { return false }
                offset += n
            }
            return true
        }
        return ok ? result : nil
    }

    static func readFrame<T: Decodable>(_ descriptor: Int32, as type: T.Type) throws -> T? {
        guard let header = readExactly(descriptor, count: 4) else { return nil }
        let length = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard length <= HolderProtocol.maximumFrameBytes else { throw HolderError.frameTooLarge(length) }
        guard let body = readExactly(descriptor, count: length) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: body) } catch { throw HolderError.malformedFrame }
    }
}

/// sockaddr_unを作って接続・束縛するための補助。
enum HolderSocket {
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw HolderError.unsafePath(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            let bytes = Array(path.utf8) + [0]
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    static func connect(path: String) throws -> Int32 {
        var address = try address(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw HolderError.connectionFailed("socket \(errno)") }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        var noSigpipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(descriptor)
            throw HolderError.connectionFailed("connect \(code)")
        }
        return descriptor
    }

    /// 接続相手が同じユーザーか。
    static func peerIsSameUser(_ descriptor: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(descriptor, &uid, &gid) == 0 && uid == geteuid()
    }
}

/// 0700の専用ディレクトリを所有者・種別つきで作る/検証する。
enum HolderDirectory {
    static func ensurePrivate(_ path: String) throws {
        let parent = (path as NSString).deletingLastPathComponent
        if !parent.isEmpty, parent != path {
            try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }
        if mkdir(path, 0o700) != 0, errno != EEXIST { throw HolderError.unsafePath(path) }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0 else { throw HolderError.unsafePath(path) }
    }
}
