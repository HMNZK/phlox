import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// ADR 0116: transcript セルの同値性。
// 目的は「1行の更新で配列全体が無効化されても、変化していない行の body 再評価を飛ばす」こと。
// ここで固定したい振る舞いは 2 つ:
//  (1) 表示に効く値が同じなら、クロージャが別物でも equal になる（クロージャを比較に含めると
//      毎回生成されるため常に不一致になり、差分が一切効かなくなる）。
//  (2) 表示に効く値が変われば not equal になる（更新が握り潰されない）。

@MainActor
struct TranscriptCellEquatableWhiteboxTests {
    private let descriptor = AgentRegistry.descriptor(for: .claudeCode)
    private let otherDescriptor = AgentRegistry.descriptor(for: .codex)
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func message(id: String, text: String) -> ChatItem {
        .agentMessage(id: id, text: text, timestamp: timestamp)
    }

    private func view(
        item: ChatItem,
        isRunningCommand: Bool = false,
        descriptor: AgentDescriptor,
        onSelectSubAgent: ((String) -> Void)? = nil
    ) -> ChatItemView {
        ChatItemView(
            item: item,
            isRunningCommand: isRunningCommand,
            agentDescriptor: descriptor,
            onSelectSubAgent: onSelectSubAgent,
            onRespondToUserQuestion: { _, _ in true }
        )
    }

    @Test("表示値が同じなら、毎回生成される別クロージャを渡しても equal になる")
    func chatItemView_sameDisplayValues_differentClosures_areEqual() {
        let item = message(id: "item-1", text: "こんにちは")
        let a = view(item: item, descriptor: descriptor, onSelectSubAgent: { _ in })
        let b = view(item: item, descriptor: descriptor, onSelectSubAgent: { _ in })

        #expect(a == b)
    }

    @Test("本文が変われば not equal になる（ストリーミング更新が握り潰されない）")
    func chatItemView_differentText_isNotEqual() {
        let a = view(item: message(id: "item-1", text: "こんに"), descriptor: descriptor)
        let b = view(item: message(id: "item-1", text: "こんにちは"), descriptor: descriptor)

        #expect(a != b)
    }

    @Test("実行中フラグが変われば not equal になる")
    func chatItemView_differentRunningFlag_isNotEqual() {
        let item = ChatItem.commandExecution(
            id: "cmd-1",
            command: "swift test",
            output: "収集中",
            timestamp: timestamp
        )
        let a = view(item: item, isRunningCommand: true, descriptor: descriptor)
        let b = view(item: item, isRunningCommand: false, descriptor: descriptor)

        #expect(a != b)
    }

    @Test("エージェントが変われば not equal になる（見た目が descriptor に依存するため）")
    func chatItemView_differentDescriptor_isNotEqual() {
        let item = message(id: "item-1", text: "こんにちは")
        let a = view(item: item, descriptor: descriptor)
        let b = view(item: item, descriptor: otherDescriptor)

        #expect(a != b)
    }

    @Test("コマンドグループも、保持値が同じなら equal・ターン実行状態が変われば not equal")
    func commandGroupCell_equalityFollowsStoredValues() {
        let items = [
            ChatItem.commandExecution(id: "cmd-1", command: "rg TODO", output: "3 件", timestamp: timestamp),
            ChatItem.commandExecution(id: "cmd-2", command: "rg FIXME", output: "1 件", timestamp: timestamp),
        ]
        let running = CommandGroupCell(items: items, lastTranscriptID: "cmd-2", isTurnRunning: true)
        let runningAgain = CommandGroupCell(items: items, lastTranscriptID: "cmd-2", isTurnRunning: true)
        let idle = CommandGroupCell(items: items, lastTranscriptID: "cmd-2", isTurnRunning: false)

        #expect(running == runningAgain)
        #expect(running != idle)
    }
}
