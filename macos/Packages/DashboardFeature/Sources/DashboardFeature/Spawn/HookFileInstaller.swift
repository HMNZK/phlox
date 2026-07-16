import Foundation

public struct HookInstallation: Sendable, Equatable {
    public let hooksFileURL: URL
    public let backedUpUserHooks: Bool
    fileprivate let backupFileURL: URL?

    init(hooksFileURL: URL, backedUpUserHooks: Bool, backupFileURL: URL?) {
        self.hooksFileURL = hooksFileURL
        self.backedUpUserHooks = backedUpUserHooks
        self.backupFileURL = backupFileURL
    }
}

/// hooks.json の設置結果。Codex / Cursor の hooks マネージャが返す。
public enum HookFileInstallResult: Sendable, Equatable {
    case installed(HookInstallation)
    case skippedExistingUserFile
}

enum HookFileInstaller {
    static let backupFileName = "hooks.json.phlox-backup"
    private static let appMarkerSessionID = "PHLOX_SESSION_ID="

    static func install(
        directoryName: String,
        fileName: String = "hooks.json",
        settings: [String: Any],
        dispatcherPath: String,
        in workingDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> HookFileInstallResult {
        let hooksDir = workingDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)

        let hooksURL = hooksDir.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: hooksURL.path),
           !isAppInstalledHooks(at: hooksURL, dispatcherPath: dispatcherPath, fileManager: fileManager) {
            return .skippedExistingUserFile
        }

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        try data.write(to: hooksURL, options: .atomic)

        return .installed(
            HookInstallation(
                hooksFileURL: hooksURL,
                backedUpUserHooks: false,
                backupFileURL: nil
            )
        )
    }

    static func cleanup(_ installation: HookInstallation, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: installation.hooksFileURL.path) {
            try fileManager.removeItem(at: installation.hooksFileURL)
        }
        if installation.backedUpUserHooks,
           let backupURL = installation.backupFileURL,
           fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.moveItem(at: backupURL, to: installation.hooksFileURL)
        }
    }

    /// 既存 hooks.json が本アプリが書き出したものか（dispatcher または旧セッション ID 前置を含む command）。
    static func isAppInstalledHooks(
        at hooksURL: URL,
        dispatcherPath: String,
        fileManager: FileManager
    ) -> Bool {
        guard let data = try? Data(contentsOf: hooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return jsonContainsAppHookMarker(json, dispatcherPath: dispatcherPath)
    }

    private static func jsonContainsAppHookMarker(_ value: Any, dispatcherPath: String) -> Bool {
        switch value {
        case let string as String:
            return string.contains(dispatcherPath) || string.contains(appMarkerSessionID)
        case let array as [Any]:
            return array.contains { jsonContainsAppHookMarker($0, dispatcherPath: dispatcherPath) }
        case let dictionary as [String: Any]:
            return dictionary.values.contains { jsonContainsAppHookMarker($0, dispatcherPath: dispatcherPath) }
        default:
            return false
        }
    }
}
