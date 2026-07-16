import Foundation

/// エージェント CLI のプラン残量（レート制限使用率）のスナップショット。
/// Claude の get_usage control_request 応答（utilization / resets_at）を
/// statusLine キャッシュと同じ語彙（usedPercentage）へ正規化して運ぶ。
public struct AgentRateLimitsSnapshot: Sendable, Equatable {
    public struct Bucket: Sendable, Equatable {
        public let usedPercentage: Double
        public let resetsAt: Date?

        public init(usedPercentage: Double, resetsAt: Date?) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }
    }

    public let fiveHour: Bucket?
    public let sevenDay: Bucket?
    /// データの取得時刻（UI の鮮度注記に使う）。
    public let asOf: Date

    public init(fiveHour: Bucket?, sevenDay: Bucket?, asOf: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.asOf = asOf
    }
}

/// 会話ターンとは独立した帯域外リクエストでプラン残量を問い合わせられる
/// 構造化チャットクライアント。
public protocol UsageQuerying: Sendable {
    /// 現在のレート制限使用率を返す。プロセス未起動・応答不能・応答が
    /// 解釈不能な場合は throw する（呼び出し側がフォールバックを判断する）。
    func fetchRateLimits() async throws -> AgentRateLimitsSnapshot
}
