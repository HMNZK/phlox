import Foundation

/// 前回起動時に使用した hook / control サーバーのポート番号。
/// 再起動時に同じポートを優先確保し、復元セッションの接続先がずれないようにする。
public struct SavedPorts: Codable, Equatable, Sendable {
    public let hookPort: UInt16
    public let controlPort: UInt16

    public init(hookPort: UInt16, controlPort: UInt16) {
        self.hookPort = hookPort
        self.controlPort = controlPort
    }

    /// 保存済みポートを読み込む。ファイルが無い・JSON が壊れている場合は nil（新規割当てへフォールバック）。
    public static func load(from url: URL) -> SavedPorts? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SavedPorts.self, from: data)
    }

    /// ポートを保存する（親ディレクトリ作成 + atomic write）。
    public func save(to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
