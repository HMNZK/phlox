import Foundation
import os

/// 自分（このプロセスのこの `JSONFileStore` インスタンス）が最後に書き込んだ内容と、その直後に
/// 観測したディスク実体の stat（サイズ・更新日時・パーミッション）のスナップショット。
private struct WrittenSnapshot: Equatable {
    let data: Data
    let fileSize: Int64
    let modificationDate: Date
    let posixPermissions: UInt16
}

/// ディスク実体の現在の stat（無変更スキップの照合に使う項目のみ）。
private struct DiskStat: Equatable {
    let fileSize: Int64
    let modificationDate: Date
    let posixPermissions: UInt16
}

/// 直前に書き込んだ内容とその時点のディスク stat をプロセス内キャッシュし、無変更 save の
/// ディスク書き込みをスキップするための保持クラス。`JSONFileStore` は値型のため、`let` で保持される
/// インスタンス越しに書き込み履歴を共有できるよう参照型として切り出す。
/// ロックで保護しているため `Sendable` に安全に適合する。
///
/// スキップ可否は「encode バイト列がキャッシュと一致」**かつ**「自分の書き込み直後に記録した
/// ディスク stat が現在の実ファイルの stat と一致」の両方が成立する場合のみ true。
/// ファイル不在・stat 取得失敗・stat 不一致（外部書き換え・削除・quarantine・chmod 等の
/// プロセス外ドリフト）はすべて判定不能として書き込む側へ倒す。
private final class LastWrittenSnapshotCache: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: WrittenSnapshot?

    /// `currentDiskStat` が nil（stat 取得失敗・ファイル不在）の場合は必ず false（書き込む）を返す。
    func canSkipWrite(candidateData: Data, currentDiskStat: DiskStat?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let snapshot, let currentDiskStat else { return false }
        guard snapshot.data == candidateData else { return false }
        return snapshot.fileSize == currentDiskStat.fileSize
            && snapshot.modificationDate == currentDiskStat.modificationDate
            && snapshot.posixPermissions == currentDiskStat.posixPermissions
    }

    func record(data: Data, diskStat: DiskStat) {
        lock.lock()
        defer { lock.unlock() }
        snapshot = WrittenSnapshot(
            data: data,
            fileSize: diskStat.fileSize,
            modificationDate: diskStat.modificationDate,
            posixPermissions: diskStat.posixPermissions
        )
    }
}

/// Codable な envelope を JSON ファイル 1 つへ保存・復元する共通実装。
/// `JSONProjectStore` / `JSONSessionStore` が委譲する。
struct JSONFileStore<File: Codable & Sendable>: Sendable {
    private let fileURL: URL
    private let logger: Logger
    private let lastWrittenCache = LastWrittenSnapshotCache()

    init(fileURL: URL, category: String) {
        self.fileURL = fileURL
        self.logger = Logger(subsystem: "com.phlox.Phlox", category: category)
    }

    /// ファイルが存在しない場合は nil を返す。
    /// 読込・デコード失敗時はログを残し、破損ファイルを退避してから nil を返す。
    func load() -> File? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(File.self, from: data)
        } catch {
            logger.error("load failed for \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            quarantineCorruptFile()
            return nil
        }
    }

    func save(_ file: File) throws {
        // `.sortedKeys` を指定して JSON オブジェクトのキー順序を決定的にする。デフォルトの
        // JSONEncoder はキー順序が呼び出しごとに不定（内部辞書のハッシュ順）になり得るため、
        // 指定しないと論理的に同一な内容でも encode 済みバイト列が一致せず、無変更スキップの
        // 判定が事実上機能しなくなる（誤って「変更あり」と判定し続ける＝安全側ではあるが
        // 事後条件「同一内容の連続 save は 2 回目以降ディスク書き込みを行わない」を満たせない）。
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)

        // ディスク実体の現在の stat を取得する。ファイル不在・stat 取得失敗はすべて nil として
        // 扱い、以降の canSkipWrite で「判定不能→書き込む」側へ倒す（プロセス外ドリフト対策）。
        let currentDiskStat = try? readDiskStat()
        guard !lastWrittenCache.canSkipWrite(candidateData: data, currentDiskStat: currentDiskStat) else {
            // 前回自分が書き込んだ内容・stat と現在のディスク実体が完全に一致する場合のみ
            // 書き込みをスキップする（正しさに影響しない最適化）。
            return
        }
        try data.write(to: fileURL, options: .atomic)
        try setOwnerOnlyPermissions()
        // 書き込み直後の stat を記録する。この stat 取得に失敗した場合はキャッシュを更新せず
        // （次回 save で必ず「判定不能→書き込む」側へ倒れる）、エラーを呼び出し元へ伝播する。
        let writtenStat = try readDiskStat()
        lastWrittenCache.record(data: data, diskStat: writtenStat)
    }

    /// `.atomic` 書き込みは一時ファイル→rename で実体を差し替えるため、rename 後の実ファイルに対して
    /// パーミッションを明示設定する（umask 依存で読み取り権限が広がるのを防ぐ）。
    private func setOwnerOnlyPermissions() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }

    private enum DiskStatError: Error {
        case missingAttribute
    }

    /// 無変更スキップの照合に使う現在のディスク実体 stat を読む。ファイルが存在しない・属性が
    /// 取得できない場合は throw する（呼び出し側で `try?` により nil＝判定不能として扱われる）。
    private func readDiskStat() throws -> DiskStat {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard
            let size = attributes[.size] as? NSNumber,
            let modificationDate = attributes[.modificationDate] as? Date,
            let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            throw DiskStatError.missingAttribute
        }
        return DiskStat(
            fileSize: size.int64Value,
            modificationDate: modificationDate,
            posixPermissions: permissions.uint16Value & 0o777
        )
    }

    /// 破損ファイルを `.corrupt-<epoch秒>` へ退避し、次の save が破損データを正常上書きして
    /// 事後調査を不可能にすることを防ぐ。
    private func quarantineCorruptFile() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let destination = fileURL.appendingPathExtension("corrupt-\(timestamp)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            logger.error("quarantined corrupt file to \(destination.path, privacy: .public)")
        } catch {
            logger.error("failed to quarantine corrupt file \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
