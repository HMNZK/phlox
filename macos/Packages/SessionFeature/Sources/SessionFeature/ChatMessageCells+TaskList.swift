import SwiftUI
import StructuredChatKit
import DesignSystem

/// エージェントのタスクリストカード（tasks/task-2.md 契約。受け入れテスト
/// AcceptanceTaskListCardTests が凍結）。transcript 内に 1 枚だけ置かれ、
/// taskListUpdated のたびに最新スナップショットへ差し替わる。
///
/// スケルトン（フェーズ1 凍結公開面）: 表示実装は task-2 が行う。
struct TaskListCell: View {
    let tasks: [AgentTaskItem]
    let timestamp: Date

    var body: some View {
        // task-2 で実装（タスクごとの行＋状態グリフ）。
        EmptyView()
    }
}
