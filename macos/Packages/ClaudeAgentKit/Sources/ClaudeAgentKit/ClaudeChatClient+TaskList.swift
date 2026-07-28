import Foundation
import StructuredChatKit

extension ClaudeChatClient {
    /// TodoWrite の `todos` 全量スナップショットを、UI がそのまま置換できる値へ還元する。
    /// 同じ content が同じ位置にある限り ID を変えない。重複した content は位置で区別する。
    func taskListSnapshot(from input: [String: Any]) -> [AgentTaskItem] {
        guard let todos = input["todos"] as? [Any] else { return [] }

        return todos.enumerated().compactMap { index, value in
            guard let todo = value as? [String: Any] else { return nil }
            let title = todo["content"] as? String ?? ""
            let status: AgentTaskStatus
            switch todo["status"] as? String {
            case "in_progress":
                status = .inProgress
            case "completed":
                status = .completed
            case "pending", .none:
                status = .pending
            default:
                status = .pending
            }
            return AgentTaskItem(
                id: "todo-\(index)-\(title)",
                title: title,
                status: status
            )
        }
    }

    /// TaskUpdate は taskId を入力に持つため、実行要求時点で既知の項目を差分更新できる。
    func applyTaskUpdate(_ input: [String: Any]) -> Bool {
        guard let taskID = input["taskId"] as? String,
              let index = taskListTasks.firstIndex(where: { $0.id == taskID })
        else { return false }

        if input["status"] as? String == "deleted" {
            taskListTasks.remove(at: index)
            return true
        }

        let title = input["subject"] as? String ?? taskListTasks[index].title
        let status = normalizedStatus(input["status"] as? String)
        let replacement = AgentTaskItem(id: taskID, title: title, status: status)
        guard replacement != taskListTasks[index] else { return false }
        taskListTasks[index] = replacement
        return true
    }

    /// TaskCreate の user tool_result は toolUseResult.task.id に作成済み ID を載せる。
    /// TaskCreate の結果には status がないため、作成直後は pending として扱う。
    func resolveCreatedTaskIfNeeded(toolUseId: String, event: [String: Any]) {
        guard let title = pendingCreatedTaskTitles.removeValue(forKey: toolUseId),
              let result = event["toolUseResult"] as? [String: Any],
              let taskID = taskIdentifier(from: result),
              !taskListTasks.contains(where: { $0.id == taskID })
        else { return }

        taskListTasks.append(AgentTaskItem(
            id: taskID,
            title: title,
            status: normalizedStatus(result["status"] as? String)
        ))
        eventContinuation.yield(.taskListUpdated(tasks: taskListTasks))
    }

    private func taskIdentifier(from result: [String: Any]) -> String? {
        guard let task = result["task"] as? [String: Any] else { return nil }
        if let taskID = task["id"] as? String, !taskID.isEmpty {
            return taskID
        }
        if let taskID = task["id"] as? NSNumber {
            return taskID.stringValue
        }
        return nil
    }

    private func normalizedStatus(_ rawStatus: String?) -> AgentTaskStatus {
        switch rawStatus {
        case "in_progress": .inProgress
        case "completed": .completed
        default: .pending
        }
    }
}
