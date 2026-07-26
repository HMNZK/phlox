import Foundation

/// `~/.codex/config.toml` を読み書きするストア。
///
/// このファイルはユーザーが手で書き、Codex 自身も追記する共有資産である。
/// そのため解析して書き戻す方式は採らず、`TOMLDocument` で**触った行だけ**を書き換える。
/// 書き込み前には必ず1世代の控えを残す（`config.toml.phlox-backup`）。
public struct CodexConfigStore: Sendable {
    private let fileURL: URL
    private let backupURL: URL

    public init(fileURL: URL, backupURL: URL) {
        self.fileURL = fileURL
        self.backupURL = backupURL
    }

    public init(paths: CodexConfigPaths) {
        self.init(fileURL: paths.configFile, backupURL: paths.configBackupFile)
    }

    public var url: URL { fileURL }
    public var backupFileURL: URL { backupURL }

    /// `FileManager` は `Sendable` ではないので保持せず、都度 `default` を使う。
    private var fileManager: FileManager { .default }

    public var exists: Bool { fileManager.fileExists(atPath: fileURL.path) }

    /// 現在の内容を読む。ファイルが無ければ空の文書。
    public func load() throws -> TOMLDocument {
        guard fileManager.fileExists(atPath: fileURL.path) else { return TOMLDocument(text: "") }
        return TOMLDocument(text: try String(contentsOf: fileURL, encoding: .utf8))
    }

    /// 書き戻す。内容が変わっていなければ何もしない（無用な更新でバックアップを潰さない）。
    @discardableResult
    public func save(_ document: TOMLDocument) throws -> Bool {
        let next = document.text
        let current = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        guard next != current else { return false }

        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            try Data(current.utf8).write(to: backupURL, options: .atomic)
        }
        try Data(next.utf8).write(to: fileURL, options: .atomic)
        return true
    }

    /// 読み込み → 変更 → 保存 をまとめて行う。
    @discardableResult
    public func update(_ mutate: (inout TOMLDocument) -> Void) throws -> Bool {
        var document = try load()
        mutate(&document)
        return try save(document)
    }
}
