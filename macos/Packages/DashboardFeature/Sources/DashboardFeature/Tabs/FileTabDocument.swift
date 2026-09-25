import Foundation
import Observation
import AgentDomain
import SessionFeature

/// ファイルの子タブの中身（02 の移動表「編集 → ファイルタブ」）。読み込んだ時点の内容を覚えておき、
/// 保存時にディスクが変わっていれば競合として返す（旧エディタパネルと同じ規則）。
@MainActor
@Observable
public final class FileTabDocument {
    public enum SaveResult: Equatable, Sendable {
        case saved
        case conflictDetected
    }

    /// worktree 直下からの相対パス。
    public let path: String
    public var draft = ""
    /// 読めなかった（非 UTF-8・削除済み・worktree の外）。
    public private(set) var loadFailed = false
    private var loadedDiskContent: String? {
        didSet { baselineAt = loadedDiskContent == nil ? nil : Date() }
    }
    /// ディスクの内容を最後に読んだ／書いた時刻。これより後の他セッションの書き換えを競合相手とみなす。
    public private(set) var baselineAt: Date?
    /// 読み込んだファイルの絶対パス（保存と同じく Git のルート基準）。
    private var absolutePath: String?

    /// 開いたときの作業ディレクトリ。セッションの作業場所が変わったら作り直す。
    public let workingDirectory: String
    @ObservationIgnored private let service: WorkingTreeService

    public init(path: String, workingDirectory: String) {
        self.path = path
        self.workingDirectory = workingDirectory
        self.service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: workingDirectory, isDirectory: true))
    }

    public var isLoaded: Bool { loadedDiskContent != nil }
    public var isDirty: Bool { loadedDiskContent.map { $0 != draft } ?? false }
    public var fileName: String { (path as NSString).lastPathComponent }

    /// 開いてからこのファイルを書き換えた別セッションの表示名（07「アザミ · Codex」）。
    /// 分かるのはチャット型のファイル変更だけ。その後にターミナルやエディタが書き換えていれば分からないので nil。
    public func lastWriter(among sessions: [SessionNode], excluding sessionID: SessionID) -> String? {
        guard let baselineAt, let absolutePath else { return nil }
        let target = Self.canonical(absolutePath, relativeTo: "/")
        var latest: (date: Date, name: String)?
        for node in sessions where node.id != sessionID {
            guard case .appServer(let chat) = node else { continue }
            for case .fileChange(_, let changes, let timestamp) in chat.transcript
            where timestamp > baselineAt && timestamp > (latest?.date ?? .distantPast)
                && changes.contains(where: { Self.canonical($0.path, relativeTo: node.rawWorkspacePath) == target }) {
                latest = (timestamp, "\(node.displayName) · \(node.agentDescriptor.displayName)")
            }
        }
        // ponytail: 変更の記録時刻とディスクの更新時刻を 5 秒の幅で突き合わせる。書き手の記録が要るなら保存経路で記録する。
        guard let latest,
              let modified = (try? FileManager.default.attributesOfItem(atPath: absolutePath))?[.modificationDate] as? Date,
              modified <= latest.date.addingTimeInterval(Self.writeTolerance)
        else { return nil }
        return latest.name
    }

    static let writeTolerance: TimeInterval = 5

    private static func canonical(_ path: String, relativeTo base: String) -> String {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(path)
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// 未読込のときだけ読む（タブの切り替えで下書きを失わない）。
    public func loadIfNeeded() async {
        guard loadedDiskContent == nil else { return }
        do {
            absolutePath = await service.absolutePath(path)
            // 読み始める前の時刻を基準にする（読んでいる間の他セッションの書き換えも相手とみなす）。
            let startedAt = Date()
            let contents = try await service.fileContents(path)
            loadedDiskContent = contents
            baselineAt = startedAt
            draft = contents
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    public func save() async throws -> SaveResult {
        guard let expected = loadedDiskContent else { return .conflictDetected }
        let saving = draft
        switch try await service.save(path: path, content: saving, expectedDiskContent: expected) {
        case .saved:
            loadedDiskContent = saving
            return .saved
        case .conflict:
            return .conflictDetected
        }
    }

    public func overwrite() async throws {
        let saving = draft
        _ = try await service.save(path: path, content: saving, expectedDiskContent: nil)
        loadedDiskContent = saving
    }
}

/// セッション × パスごとのファイルタブ。表示の途中で作ってよいよう観測対象にはしない。
@MainActor
final class FileTabDocuments {
    private var documents: [SessionID: [String: FileTabDocument]] = [:]

    /// セッションの作業場所が変わっていたら、旧い場所の下書きは捨てて開き直す
    /// （作業場所の変更は「進行中の作業は失われます」と確認してから行われる）。
    func document(for sessionID: SessionID, path: String, workingDirectory: String) -> FileTabDocument {
        if let existing = documents[sessionID]?[path], existing.workingDirectory == workingDirectory { return existing }
        let created = FileTabDocument(path: path, workingDirectory: workingDirectory)
        documents[sessionID, default: [:]][path] = created
        return created
    }

    func existing(for sessionID: SessionID, path: String) -> FileTabDocument? {
        documents[sessionID]?[path]
    }

    func remove(for sessionID: SessionID, path: String) {
        documents[sessionID]?[path] = nil
    }

    func removeAll(for sessionID: SessionID) {
        documents[sessionID] = nil
    }

    /// 未保存のファイル名（セッション削除の確認に出す）。
    func dirtyFileNames(for sessionID: SessionID) -> [String] {
        (documents[sessionID] ?? [:]).values.filter(\.isDirty).map(\.fileName).sorted()
    }
}
