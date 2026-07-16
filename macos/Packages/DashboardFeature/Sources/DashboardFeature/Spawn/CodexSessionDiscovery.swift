import Foundation

/// Codex rollout JSONL の `session_meta` を走査し native session id を取得する。
struct CodexSessionDiscovery: Sendable {
    let codexHome: URL
    let now: @Sendable () -> Date

    init(
        codexHome: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.codexHome = codexHome
        self.now = now
    }

    private var sessionsRoot: URL {
        codexHome.appendingPathComponent("sessions", isDirectory: true)
    }

    /// spawn 直前に呼び、既存 rollout ファイルパスの snapshot を返す。
    func snapshotExistingRollouts(around spawnTime: Date) -> Set<String> {
        Set(rolloutPaths(in: dayDirectories(for: spawnTime)))
    }

    /// snapshot に無い新規 rollout から条件一致の native id を 1 回探す（リトライは呼び出し側）。
    func discoverNativeSessionID(
        spawnTime: Date,
        workingDirectory: String,
        excluding existing: Set<String>,
        claimedIDs: Set<String>
    ) -> String? {
        let normalizedCWD = Self.normalizedPath(workingDirectory)
        let minimumTimestamp = spawnTime.addingTimeInterval(-2)
        let candidatePaths = rolloutPaths(in: dayDirectories(for: spawnTime))
            .filter { !existing.contains($0) }

        var bestMatch: (id: String, distance: TimeInterval)?

        for path in candidatePaths {
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard let meta = Self.readSessionMeta(from: fileURL) else {
                continue
            }

            let nativeID = meta.id.lowercased()
            guard !claimedIDs.contains(nativeID) else { continue }
            guard Self.normalizedPath(meta.cwd) == normalizedCWD else { continue }
            guard meta.timestamp >= minimumTimestamp else { continue }

            guard let filenameUUID = Self.uuidFromRolloutFilename(fileURL.lastPathComponent),
                  filenameUUID == nativeID else {
                continue
            }

            let distance = abs(meta.timestamp.timeIntervalSince(spawnTime))
            if bestMatch == nil || distance < bestMatch!.distance {
                bestMatch = (nativeID, distance)
            }
        }

        return bestMatch?.id
    }

    // MARK: - Rollout path collection

    private func dayDirectories(for spawnTime: Date) -> [URL] {
        let current = now()
        let spawnDay = Self.dayDirectory(for: spawnTime, under: sessionsRoot)
        let currentDay = Self.dayDirectory(for: current, under: sessionsRoot)
        if spawnDay.path == currentDay.path {
            return [spawnDay]
        }
        return [spawnDay, currentDay]
    }

    private func rolloutPaths(in dayDirectories: [URL]) -> [String] {
        dayDirectories.flatMap { directory in
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [String]()
            }

            return contents.compactMap { url -> String? in
                let name = url.lastPathComponent
                guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { return nil }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                    return nil
                }
                return url.path
            }
        }
    }

    static func dayDirectory(for date: Date, under sessionsRoot: URL, calendar: Calendar = .current) -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        return sessionsRoot
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
    }

    // MARK: - Parsing

    private struct SessionMeta {
        let id: String
        let cwd: String
        let timestamp: Date
    }

    private struct SessionMetaLine: Decodable {
        let type: String?
        let payload: SessionMetaPayload?

        var isSessionMeta: Bool {
            type == "session_meta"
        }
    }

    private struct SessionMetaPayload: Decodable {
        let id: String
        let cwd: String
        let timestamp: String
    }

    private static func readSessionMeta(from fileURL: URL) -> SessionMeta? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 65_536), !data.isEmpty else { return nil }
        guard let firstLine = String(data: data, encoding: .utf8)?
            .split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .first else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let line = try? decoder.decode(SessionMetaLine.self, from: Data(firstLine.utf8)),
              line.isSessionMeta,
              let payload = line.payload,
              let timestamp = Self.parseTimestamp(payload.timestamp) else {
            return nil
        }

        return SessionMeta(id: payload.id, cwd: payload.cwd, timestamp: timestamp)
    }

    static func parseTimestamp(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) {
            return date
        }
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }

    static func uuidFromRolloutFilename(_ filename: String) -> String? {
        guard filename.hasPrefix("rollout-"), filename.hasSuffix(".jsonl") else { return nil }
        let stem = String(filename.dropLast(".jsonl".count))
        guard stem.count >= 36 else { return nil }
        let candidate = String(stem.suffix(36))
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        guard candidate.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        return candidate.lowercased()
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
