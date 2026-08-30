import AgentDomain
import Foundation

public final class CodexUsageProvider: UsageProvider {
    public let kind: AgentKind = .codex

    // ponytail: 末尾2MiBに利用量イベントが無い形式へ変わったら、後方チャンク走査へ切り替える。
    private static let usageTailBytes: UInt64 = 2 * 1_024 * 1_024
    private let sessionsRoot: URL

    public init(sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")) {
        self.sessionsRoot = sessionsRoot
    }

    public func fetch() async -> CLIUsage {
        let now = Date()
        guard let latestFile = latestRolloutFile() else {
            return CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "セッション履歴なし")), updatedAt: now)
        }

        guard let text = Self.tailText(from: latestFile),
              let buckets = Self.buckets(fromJSONL: text),
              !buckets.isEmpty
        else {
            return CLIUsage(kind: kind, state: .unavailable(reason: String(localized: "セッション履歴なし")), updatedAt: now)
        }

        return CLIUsage(kind: kind, state: .ok(buckets), updatedAt: now)
    }

    private static func tailText(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let offset = end > usageTailBytes ? end - usageTailBytes : 0
        try? handle.seek(toOffset: offset)
        do {
            var data = try handle.readToEnd() ?? Data()
            if offset > 0, let newline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(...newline)
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func latestRolloutFile() -> URL? {
        Self.latestRolloutFile(under: sessionsRoot, listDirectory: Self.listDirectory(_:))
    }

    /// 年/月/日 の数値ディレクトリを最新側から降順に辿り、最初に rollout を含む日ディレクトリ内の
    /// 最新ファイルを返す。全体の再帰列挙を避け、古い年月のディレクトリへは降りない。
    static func latestRolloutFile(under root: URL, listDirectory: (URL) -> [URL]) -> URL? {
        for yearURL in numericDirectoriesDescending(in: root, listDirectory: listDirectory) {
            for monthURL in numericDirectoriesDescending(in: yearURL, listDirectory: listDirectory) {
                for dayURL in numericDirectoriesDescending(in: monthURL, listDirectory: listDirectory) {
                    if let latest = latestRolloutFile(in: dayURL, listDirectory: listDirectory) {
                        return latest
                    }
                }
            }
        }
        return nil
    }

    private static func numericDirectoriesDescending(in url: URL, listDirectory: (URL) -> [URL]) -> [URL] {
        listDirectory(url)
            .compactMap { child -> (url: URL, value: Int)? in
                guard let value = Int(child.lastPathComponent),
                      (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { return nil }
                return (child, value)
            }
            .sorted { $0.value > $1.value }
            .map(\.url)
    }

    private static func latestRolloutFile(in directory: URL, listDirectory: (URL) -> [URL]) -> URL? {
        var latest: (url: URL, modifiedAt: Date)?
        for url in listDirectory(directory) {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl"
            else { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            if latest == nil || modifiedAt > latest!.modifiedAt {
                latest = (url, modifiedAt)
            }
        }
        return latest?.url
    }

    private static func listDirectory(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: []
        )) ?? []
    }

    static func buckets(fromJSONL text: String) -> [UsageBucket]? {
        var lastRateLimits: CodexRateLimits?
        let decoder = JSONDecoder()

        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(CodexRolloutEvent.self, from: data),
                  let rateLimits = event.payload?.rateLimits
            else {
                continue
            }
            lastRateLimits = rateLimits
        }

        guard let lastRateLimits else { return nil }
        let bucketsByID = Dictionary(
            uniqueKeysWithValues: [lastRateLimits.primary, lastRateLimits.secondary]
            .compactMap { $0 }
            .compactMap(Self.bucket(from:))
            .map { ($0.id, $0) }
        )
        return ["5h", "weekly"].compactMap { bucketsByID[$0] }
    }

    private static func bucket(from limit: CodexRateLimit) -> UsageBucket? {
        let resetsAt = limit.resetsAt.map { Date(timeIntervalSince1970: $0) }
        switch limit.windowMinutes {
        case 300:
            return UsageBucket(id: "5h", label: String(localized: "5時間"), usedPercent: limit.usedPercent, resetsAt: resetsAt)
        case 10_080:
            return UsageBucket(id: "weekly", label: String(localized: "週次"), usedPercent: limit.usedPercent, resetsAt: resetsAt)
        default:
            return nil
        }
    }
}

private struct CodexRolloutEvent: Decodable {
    let payload: CodexPayload?
}

private struct CodexPayload: Decodable {
    let rateLimits: CodexRateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

private struct CodexRateLimits: Decodable {
    let primary: CodexRateLimit?
    let secondary: CodexRateLimit?
}

private struct CodexRateLimit: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
