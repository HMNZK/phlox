import Foundation

/// 延期された実行サービスの更新（ADR 0233）を、間隔を空けて有限回だけ再要求する規則。
/// 暴走しないよう、間隔の下限と回数の上限を持つ。`sleep`を差し替えて、実時間を待たずに試験できる。
public enum HostUpdateRetry {
    /// 再要求の間隔の下限（これより短い値を渡されても切り上げる）。
    public static let minimumInterval: Duration = .seconds(30)
    public static let defaultInterval: Duration = .seconds(30)
    /// 再要求の最大回数（既定の間隔で約20分）。
    public static let maximumAttempts = 40

    /// 延期が続く間だけ、`interval`ごとに`attempt`を呼ぶ。`attempt`が`false`（もう延期でない）・
    /// キャンセル・上限のどれかで止まる。戻り値は`attempt`を呼んだ回数。
    @discardableResult
    public static func run(
        interval: Duration = defaultInterval,
        maxAttempts: Int = maximumAttempts,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        attempt: @Sendable () async -> Bool
    ) async -> Int {
        let wait = max(interval, minimumInterval)
        let limit = max(0, min(maxAttempts, maximumAttempts))
        var count = 0
        while count < limit {
            do { try await sleep(wait) } catch { return count }
            if Task.isCancelled { return count }
            count += 1
            if await attempt() == false { return count }
        }
        return count
    }
}

/// 画面とホストのビルド番号（CFBundleVersion）の順序（ADR 0233）。更新を要求するのは画面の方が新しいときだけ。
public enum HostBuildOrder {
    /// `candidate`が`current`より新しいか。`.`区切りの各要素を整数として前から比べ、足りない要素は0とみなす。
    /// どちらかが空・数値でない要素を含むなら偽（更新を要求しない側に倒す）。
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let lhs = components(candidate), let rhs = components(current) else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [UInt64]? {
        var result: [UInt64] = []
        for part in version.split(separator: ".", omittingEmptySubsequences: false) {
            // 符号・空白・全角数字などは数値として扱わない（UInt64(_:)は"+5"を受け付けるため、先に数字だけかを見る）。
            guard part.allSatisfy({ ("0"..."9").contains($0) }), let value = UInt64(part) else { return nil }
            result.append(value)
        }
        return result
    }
}
