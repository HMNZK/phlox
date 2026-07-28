// task-1 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-1.md
// 目的: 「このセッションが実際に受け付けるスラッシュコマンド名の一覧」を運ぶ
//       公開イベント case を NormalizedChatEvent に凍結する。
//       名前は先頭の "/" を含まない素の名前（Claude Code stream-json の
//       system/init の slash_commands と同じ表現）で運ぶ。

import Testing
import StructuredChatKit

private func commands(of event: NormalizedChatEvent) -> [String]? {
    if case let .availableCommandsUpdated(commands) = event { return commands }
    return nil
}

@Suite("Acceptance: 利用可能スラッシュコマンドの公開イベント（task-1）")
struct AcceptanceAvailableCommandsEventTests {

    @Test("コマンド名の配列をそのまま順序を保って運ぶ")
    func carriesCommandNamesInOrder() throws {
        let event = NormalizedChatEvent.availableCommandsUpdated(
            commands: ["compact", "clear", "model", "agentic-loop"]
        )

        let payload = try #require(commands(of: event))
        #expect(payload == ["compact", "clear", "model", "agentic-loop"])
    }

    @Test("名前は先頭の / を含まない素の名前で運ぶ")
    func namesAreCarriedWithoutLeadingSlash() throws {
        let event = NormalizedChatEvent.availableCommandsUpdated(commands: ["config"])

        let payload = try #require(commands(of: event))
        #expect(payload == ["config"], "\"/config\" ではなく \"config\" を運ぶこと")
    }

    @Test("空の一覧も表現できる")
    func carriesEmptyList() throws {
        let event = NormalizedChatEvent.availableCommandsUpdated(commands: [])

        let payload = try #require(commands(of: event))
        #expect(payload.isEmpty)
    }

    @Test("中身が同じなら等しく、違えば等しくない")
    func equalityFollowsPayload() {
        #expect(
            NormalizedChatEvent.availableCommandsUpdated(commands: ["compact", "clear"])
                == NormalizedChatEvent.availableCommandsUpdated(commands: ["compact", "clear"])
        )
        #expect(
            NormalizedChatEvent.availableCommandsUpdated(commands: ["compact"])
                != NormalizedChatEvent.availableCommandsUpdated(commands: ["clear"])
        )
    }
}
