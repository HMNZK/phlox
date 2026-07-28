import Foundation

/// `settings.json` を「自分が知らないキーを壊さずに」読み書きするストア。
///
/// 設定ファイルはユーザーが手で書くものでもあるため、既存内容を丸ごと読み込み、
/// 指定されたトップレベルキーだけ差し替えて書き戻す。ファイルが無い場合は空オブジェクトから始める。
public struct JSONSettingsStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var url: URL { fileURL }

    /// `FileManager` は `Sendable` ではないので保持せず、都度 `default` を使う。
    private var fileManager: FileManager { .default }

    public var exists: Bool { fileManager.fileExists(atPath: fileURL.path) }

    /// 現在の内容を読む。ファイルが無ければ空オブジェクト。壊れた JSON は投げる（黙って上書きしない）。
    public func load() throws -> JSONValue {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .object([:]) }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return .object([:]) }
        return try JSONValueCoder.decode(data)
    }

    /// トップレベルキー1つを差し替えて保存する。`value` が `nil` ならそのキーを消す。
    public func update(key: String, to value: JSONValue?) throws {
        let current = try load()
        try save(current.settingTopLevel(key, to: value))
    }

    /// 全体を書き戻す。親ディレクトリが無ければ作り、書き込みはアトミックに行う。
    public func save(_ root: JSONValue) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try JSONValueCoder.encode(root)
        try data.write(to: fileURL, options: .atomic)
    }
}
