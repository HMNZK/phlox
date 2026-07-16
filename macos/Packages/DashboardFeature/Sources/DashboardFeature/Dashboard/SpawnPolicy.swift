import Foundation
import AgentDomain

/// API spawn の制限検査と親子関係の認可判定（DashboardViewModel からの Extract Class、R2）。
/// 可変状態（レート制限タイムスタンプ・セッション一覧）は呼び出し側が保持し、ここは純粋判定だけを行う。
enum SpawnPolicy {
    /// API 経由 spawn の深い連鎖を防ぐ。
    static let maxAPISpawnDepth = 3
    /// API 経由 spawn の短時間連打を抑える。
    static let maxAPISpawnCountPerSecond = 5
    /// API 経由 spawn のレート制限に使うスライディングウィンドウ。
    static let apiSpawnRateLimitWindowSeconds: TimeInterval = 1

    /// ウィンドウ外のタイムスタンプを整理し、上限以内なら now を追記して返す。
    /// 上限超過なら `AgentSpawnError.spawnRateLimited` を投げる。
    static func recordingSpawnAttempt(timestamps: [Date], now: Date) throws -> [Date] {
        let windowStart = now.addingTimeInterval(-apiSpawnRateLimitWindowSeconds)
        var filtered = timestamps.filter { $0 > windowStart }
        guard filtered.count < maxAPISpawnCountPerSecond else {
            throw AgentSpawnError.spawnRateLimited
        }
        filtered.append(now)
        return filtered
    }

    /// spawn 深さの上限を検査する。
    static func validateAPISpawn(newDepth: Int) throws {
        if newDepth > maxAPISpawnDepth {
            throw AgentSpawnError.depthLimitExceeded
        }
    }

    /// 親リンクをたどった深さ（root は 0）。循環・欠損リンクで打ち切る。
    /// `parents` は sessionID → parentSessionID（nil は root）の対応。
    static func depth(of id: SessionID, parents: [SessionID: SessionID?]) -> Int {
        guard let start = parents[id] else { return 0 }

        var depth = 0
        var visited: Set<SessionID> = [id]
        var remaining = parents.count
        var currentParentID = start

        while let parentID = currentParentID, remaining > 0 {
            guard !visited.contains(parentID),
                  let parentLink = parents[parentID] else {
                break
            }
            visited.insert(parentID)
            depth += 1
            currentParentID = parentLink
            remaining -= 1
        }

        return depth
    }

    /// kill(remove) 専用の認可。requester なし・自己 kill・対象不明は許可、
    /// それ以外は requester が対象の祖先であるときだけ許可する。
    ///
    /// MC-2b: `privilegedRequester`（既定 nil）に一致する requester は、
    /// cascade delete を含む全 remove を無条件に許可する。これは脅威モデル
    /// 「モバイルトークン漏洩 = Mac の全権奪取」と整合する特権付与であり、
    /// 範囲は remove のみ（他操作の認可は一切変更しない）。
    /// 既定 nil では ancestor ベースの既存挙動を完全に保つ。
    static func isAuthorizedToRemove(
        _ id: SessionID,
        requester: SessionID?,
        parents: [SessionID: SessionID?],
        privilegedRequester: SessionID? = nil
    ) -> Bool {
        guard let requester else { return true }
        if let privilegedRequester, requester == privilegedRequester { return true }
        guard requester != id else { return true }
        guard let targetParentLink = parents[id] else { return true }

        var visited: Set<SessionID> = [id]
        var remaining = parents.count
        var currentParentID = targetParentLink

        while let parentID = currentParentID, remaining > 0 {
            if parentID == requester { return true }
            guard !visited.contains(parentID),
                  let parentLink = parents[parentID] else {
                break
            }
            visited.insert(parentID)
            currentParentID = parentLink
            remaining -= 1
        }

        return false
    }
}
