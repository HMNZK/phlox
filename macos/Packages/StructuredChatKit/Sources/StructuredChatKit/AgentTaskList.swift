import Foundation

/// エージェントのタスクリスト（Claude Code の TodoWrite / TaskCreate / TaskUpdate）の
/// 1 項目（tasks/task-2.md 契約。受け入れテスト AcceptanceClaudeTaskListEventTests /
/// AcceptanceTaskListCardTests が凍結）。
///
/// - TodoWrite: `todos` 全量スナップショット（id なし → 生成側が安定 id を割り当てる）
/// - TaskCreate/TaskUpdate: `taskId` による差分更新（status: pending/in_progress/completed/deleted。
///   deleted はリストから除外され、この型では表現しない）
public struct AgentTaskItem: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let status: AgentTaskStatus

    public init(id: String, title: String, status: AgentTaskStatus) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// タスクの状態。Claude Code 実測値 pending / in_progress / completed に対応する
/// （deleted は除外扱いで、この enum には含めない）。
public enum AgentTaskStatus: String, Equatable, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}
