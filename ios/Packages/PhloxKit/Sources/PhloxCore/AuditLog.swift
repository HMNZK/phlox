import Foundation

/// 端末内ファイルに監査ログを永続化する `AuditLogging` 実装（E3-6）。
/// 既定はアプリサンドボックスの ApplicationSupport 配下。テストは任意の `fileURL` を注入できる。
public actor FileAuditLog: AuditLogging {
    private let fileURL: URL
    private let maxEntries: Int
    private var entries: [AuditEntry]

    public init(fileURL: URL? = nil, maxEntries: Int = 500) {
        let resolvedURL = fileURL ?? Self.defaultURL()
        self.fileURL = resolvedURL
        self.maxEntries = maxEntries
        self.entries = Self.loadEntries(from: resolvedURL)
    }

    public func record(_ operation: AuditOperation) async {
        entries.append(AuditEntry(operation, at: Date()))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    public func recentEntries(limit: Int) async -> [AuditEntry] {
        Array(entries.reversed().prefix(max(0, limit)))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func loadEntries(from url: URL) -> [AuditEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AuditEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("phlox-audit.json")
    }
}
