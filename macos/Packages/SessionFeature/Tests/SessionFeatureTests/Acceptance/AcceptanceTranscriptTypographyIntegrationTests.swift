// task-40（UI-03）の統合受け入れテスト。
//
// ベースラインでの red 理由: `TranscriptTypography` と
// `ChatTranscriptBlock.typographyRole` は本タスクが新設する面で、
// baseline_commit には存在しない（参照未解決でコンパイル不能＝red）。
//
// 描画（NSHostingView / ImageRenderer）は PM 採択時の調整により凍結対象外。

import CoreGraphics
import DesignSystem
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

private let typographyTestTime = Date(timeIntervalSince1970: 1_700_000_000)

private func typographyUser(_ id: String) -> ChatItem {
    .userMessage(id: id, text: id, timestamp: typographyTestTime)
}

private func typographyAgent(_ id: String) -> ChatItem {
    .agentMessage(id: id, text: id, timestamp: typographyTestTime)
}

private func typographyCommand(_ id: String) -> ChatItem {
    .commandExecution(id: id, command: "command \(id)", output: "output", timestamp: typographyTestTime)
}

private func flattenTranscript(_ blocks: [ChatTranscriptBlock]) -> [ChatItem] {
    blocks.flatMap { block -> [ChatItem] in
        switch block {
        case .single(let item): [item]
        case .commandGroup(_, let items): items
        }
    }
}

/// 正本 `gap` と `typographyRole` の合成。実 View の直前ブロック参照・先頭持ち越し・
/// 二重適用・倍率再適用は `task40-wiring.rb` の `check_gap_application` が検査する。
private func gaps(for blocks: [ChatTranscriptBlock]) -> [CGFloat] {
    var previous: TranscriptTypography.BlockRole?
    return blocks.map { block in
        let role = block.typographyRole
        let gap = TranscriptTypography.gap(after: previous, before: role)
        previous = role
        return gap
    }
}

@Suite("task-40: transcript typography integration")
struct AcceptanceTranscriptTypographyIntegrationTests {
    @Test("ChatTranscriptBlock.typographyRole の既存ケースと commandGroup の対応")
    func typographyRoleMatchesFrozenTable() {
        #expect(ChatTranscriptBlock.single(typographyUser("u1")).typographyRole == .user)
        #expect(ChatTranscriptBlock.single(typographyAgent("a1")).typographyRole == .answer)
        #expect(
            ChatTranscriptBlock.commandGroup(id: "c1", items: [typographyCommand("c1")]).typographyRole
                == .process
        )
        #expect(
            ChatTranscriptBlock.single(
                .reasoning(id: "r1", text: "thinking", timestamp: typographyTestTime)
            ).typographyRole == .process,
            Comment(rawValue: "reasoning")
        )
        #expect(
            ChatTranscriptBlock.single(typographyCommand("c-single")).typographyRole == .process,
            Comment(rawValue: "commandExecution")
        )
        #expect(
            ChatTranscriptBlock.single(
                .fileChange(
                    id: "f1",
                    changes: [FilePatchChange(path: "a.swift", diff: "", kind: "edit")],
                    timestamp: typographyTestTime
                )
            ).typographyRole == .process,
            Comment(rawValue: "fileChange")
        )
        #expect(
            ChatTranscriptBlock.single(
                .subAgentMarker(
                    id: "s1",
                    subagentType: "Explore",
                    description: "search",
                    status: .running
                )
            ).typographyRole == .process,
            Comment(rawValue: "subAgentMarker")
        )
        #expect(
            ChatTranscriptBlock.single(
                .taskList(
                    id: "t1",
                    tasks: [AgentTaskItem(id: "task-1", title: "調べる", status: .pending)],
                    timestamp: typographyTestTime
                )
            ).typographyRole == .process,
            Comment(rawValue: "taskList")
        )
        let question = ChatUserQuestion(
            question: "どちらにしますか？",
            header: "方式",
            options: [ChatUserQuestionOption(label: "A", description: nil)],
            multiSelect: false
        )
        #expect(
            ChatTranscriptBlock.single(
                .userQuestion(
                    id: "q1",
                    requestId: "req-1",
                    questions: [question],
                    answers: nil,
                    state: .pending,
                    timestamp: typographyTestTime
                )
            ).typographyRole == .process,
            Comment(rawValue: "userQuestion")
        )
        #expect(
            ChatTranscriptBlock.single(
                .error(id: "e1", message: "boom", timestamp: typographyTestTime)
            ).typographyRole == .auxiliary,
            Comment(rawValue: "error")
        )
        #expect(
            ChatTranscriptBlock.single(
                .turnCost(id: "cost1", costUSD: 0.12, timestamp: typographyTestTime)
            ).typographyRole == .auxiliary,
            Comment(rawValue: "turnCost")
        )
    }

    @Test("2件の連続コマンドは既存どおり1グループで、ID・順序・件数が変わらない")
    func twoCommandsStayOneGroup() {
        let items = [typographyCommand("c1"), typographyCommand("c2")]
        let blocks = ChatTranscriptGrouping.blocks(from: items)

        #expect(blocks.count == 1)
        guard case .commandGroup(let id, let grouped) = blocks[0] else {
            Issue.record("expected commandGroup, got \(blocks[0])")
            return
        }
        #expect(id == "c1")
        #expect(blocks[0].id == "c1")
        #expect(grouped.map(\.id) == ["c1", "c2"])
        #expect(flattenTranscript(blocks) == items)
        #expect(blocks[0].typographyRole == .process)
    }

    @Test("ユーザー→回答→回答→処理グループ→回答→料金→ユーザーの gap は先頭 0・以降すべて 14")
    func mixedConversationGapSeries() {
        let items: [ChatItem] = [
            typographyUser("u1"),
            typographyAgent("a1"),
            typographyAgent("a2"),
            typographyCommand("c1"),
            typographyCommand("c2"),
            typographyAgent("a3"),
            .turnCost(id: "cost1", costUSD: 0.25, timestamp: typographyTestTime),
            typographyUser("u2"),
        ]
        let blocks = ChatTranscriptGrouping.blocks(from: items)
        #expect(blocks.map(\.id) == ["u1", "a1", "a2", "c1", "a3", "cost1", "u2"])
        #expect(blocks.map(\.typographyRole) == [
            .user, .answer, .answer, .process, .answer, .auxiliary, .user,
        ])
        // 2026-09 UI 再設計でユーザー承認（B2）: 種類別の [0, 16, 8, 8, 16, 8, 24] から一律 14 へ。
        #expect(gaps(for: blocks) == [0, 14, 14, 14, 14, 14, 14])
        #expect(flattenTranscript(blocks) == items)
    }

    @Test("表示範囲を途中から開始したとき、先頭ブロックへ 24pt 等の余白を持ち越さない")
    func visibleSliceDoesNotCarryMajorSectionOntoFirstBlock() {
        let items: [ChatItem] = [
            typographyUser("u1"),
            typographyAgent("a1"),
            typographyAgent("a2"),
            typographyCommand("c1"),
            typographyCommand("c2"),
            typographyAgent("a3"),
            .turnCost(id: "cost1", costUSD: 0.25, timestamp: typographyTestTime),
            typographyUser("u2"),
        ]
        let allBlocks = ChatTranscriptGrouping.blocks(from: items)
        // B2（ユーザー承認の凍結テスト変更）: 種類によらず一律 14。
        #expect(TranscriptTypography.gap(after: .auxiliary, before: .user) == 14)

        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 1)
        #expect(slice.blocks.count == 1)
        #expect(slice.blocks[0].id == "u2")
        #expect(slice.blocks[0].content.typographyRole == .user)
        #expect(gaps(for: slice.blocks.map(\.content)) == [0])
        #expect(
            TranscriptTypography.gap(after: nil, before: slice.blocks[0].content.typographyRole) == 0
        )

        let two = ChatTranscriptGrouping.visibleSlice(fromBlocks: allBlocks, blockLimit: 2)
        #expect(two.blocks.map(\.id) == ["cost1", "u2"])
        #expect(gaps(for: two.blocks.map(\.content)) == [0, 14])
    }

    @Test("ChatTypography の既存 API は従来の Markdown 基準値を返し、bodyPointSize は正本の body と一致する")
    func chatTypographyDelegatesAndBodyPointSizeMatchesCanonicalBody() {
        // 2026-09-24 ユーザー承認（「両方モックに合わせる」）: 本文 15→13、インラインコード 13.5→12。
        #expect(ChatTypography.bodyFontSize(scale: 1.0) == 13)
        #expect(ChatTypography.codeFontSize(scale: 1.0) == 12)
        #expect(ChatTypography.heading1FontSize(scale: 1.0) == 26)
        #expect(ChatTypography.heading2FontSize(scale: 1.0) == 19)
        #expect(ChatTypography.heading3FontSize(scale: 1.0) == 16)

        #expect(ChatTypography.bodyFontSize(scale: 0.8) == 13 * 0.8)
        #expect(ChatTypography.codeFontSize(scale: 2.0) == 12 * 2.0)
        #expect(ChatTypography.heading1FontSize(scale: 1.5) == 26 * 1.5)

        #expect(
            ChatTypography.bodyFontSize(scale: 1.0)
                == TranscriptTypography.pointSize(for: .body, scale: 1.0)
        )
        #expect(
            ChatTypography.codeFontSize(scale: 1.2)
                == TranscriptTypography.pointSize(for: .inlineCode, scale: 1.2)
        )
        #expect(
            ChatTypography.heading1FontSize(scale: 1.0)
                == TranscriptTypography.pointSize(for: .heading1, scale: 1.0)
        )
        #expect(
            ChatTypography.heading2FontSize(scale: 1.0)
                == TranscriptTypography.pointSize(for: .heading2, scale: 1.0)
        )
        #expect(
            ChatTypography.heading3FontSize(scale: 1.0)
                == TranscriptTypography.pointSize(for: .heading3, scale: 1.0)
        )

        #expect(ChatScaledFont.bodyPointSize(scale: 1.0) == 13)
        #expect(
            ChatScaledFont.bodyPointSize(scale: 1.0)
                == TranscriptTypography.pointSize(for: .body, scale: 1.0)
        )
        #expect(
            ChatScaledFont.bodyPointSize(scale: 2.0)
                == TranscriptTypography.pointSize(for: .body, scale: 2.0)
        )
        #expect(ChatScaledFont.bodyPointSize(scale: 0.8) == 13 * 0.8)
    }
}
