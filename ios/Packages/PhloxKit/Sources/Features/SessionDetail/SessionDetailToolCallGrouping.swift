import Foundation
import PhloxCore

/// SessionDetail transcript のトップレベル描画単位（phlox-ux-5fixes task-5 契約）。
/// Mac の `ChatTranscriptBlock`（single / commandGroup）に対応する iOS 版。
/// 契約の正本: tasks/task-5.md（受け入れテスト AcceptanceIOSToolCallGroupingTests が凍結）。
public enum SessionDetailChatBlock: Identifiable, Equatable, Sendable {
    case single(ChatMessage)
    case commandGroup(id: String, items: [ChatMessage])

    public var id: String {
        switch self {
        case .single(let message):
            message.id
        case .commandGroup(let id, _):
            id
        }
    }
}

/// 連続する `.command` メッセージを 1 ブロックへ集約する純関数（task-5 契約のスタブ実装。
/// 現状は全件 single を返す。実装は task-5 が担う）。
public enum SessionDetailToolCallGrouping {
    public static func blocks(from messages: [ChatMessage]) -> [SessionDetailChatBlock] {
        messages.map { .single($0) }
    }
}
