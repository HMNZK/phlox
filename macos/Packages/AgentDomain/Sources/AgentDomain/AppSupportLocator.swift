import Foundation

/// `~/Library/Application Support/<flavor>` を解決する共有 locator。
public enum AppSupportLocator {
    /// FileManager 経由でアプリサポートのルートを解決し、flavor 名を付けて返す。
    /// （`CompositionRoot` 用。ディレクトリ自体は作成しない）
    public static func appSupportDirectoryURL(
        flavor: AppFlavor = .current,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let dataDir = environment["PHLOX_DATA_DIR"], !dataDir.isEmpty {
            return URL(fileURLWithPath: dataDir, isDirectory: true)
        }
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return root.appendingPathComponent(flavor.appSupportDirectoryName, isDirectory: true)
    }

    /// ホームディレクトリ起点で `Library/Application Support/<flavor>` を組み立てて返す。
    /// （DashboardFeature 側の呼び出し用。テストで home を差し替えられる）
    public static func appSupportDirectoryURL(
        flavor: AppFlavor = .current,
        home: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let dataDir = environment["PHLOX_DATA_DIR"], !dataDir.isEmpty {
            return URL(fileURLWithPath: dataDir, isDirectory: true)
        }
        return home.appending(
            path: "Library/Application Support/\(flavor.appSupportDirectoryName)",
            directoryHint: .isDirectory
        )
    }
}
