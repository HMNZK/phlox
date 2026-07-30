import Testing
import PhloxCore
import ChatRenderKit
import DesignSystemIOS
@testable import Features

// task-5 の受け入れテスト（PM が著す不変の契約）。
// 目的:
//   ①Reasoning は、見出しと本文が同一なら開閉トグルを出さず 1 行で描く（ADR 0147）
//   ②サブエージェント詳細画面も、セッション詳細と同じ器・同じ見出し規則で描く

@Suite("iOS Reasoning: 見出しと本文が同一なら 1 行")
struct AcceptanceIOSReasoningTests {
    @Test("判定は共有実装に委ねる（規則を二重に持たない）", arguments: [
        "短い一文",
        "# 見出し\n本文がある",
        "   ",
    ])
    func presentationMatchesSharedRule(_ text: String) {
        let shared = ChatReasoningPresentation(text: text)
        let presentation = DSReasoningText.presentation(for: text)
        #expect(presentation.headline == shared.headline)
        #expect(presentation.trimmedText == shared.trimmedText)
        #expect(presentation.usesDisclosure == shared.usesDisclosure)
    }

    @Test("見出しと本文が同一ならトグルを描かない（トグルが渡されていても）")
    func noToggleWhenHeadlineEqualsBody() {
        #expect(DSReasoningText.showsDisclosure(text: "短い一文", hasToggle: true) == false)
    }

    @Test("見出しと本文が異なり、トグルが渡されていれば開閉式")
    func toggleWhenBodyIsLonger() {
        #expect(DSReasoningText.showsDisclosure(text: "# 見出し\n本文がある", hasToggle: true) == true)
    }

    @Test("トグルが渡されない使い方（サブエージェント詳細）は従来どおり全文表示で、トグルを出さない")
    func noToggleWhenCallerPassesNone() {
        #expect(DSReasoningText.showsDisclosure(text: "# 見出し\n本文がある", hasToggle: false) == false)
    }
}

@Suite("iOS サブエージェント詳細: セッション詳細と同じ器")
struct AcceptanceIOSSubAgentRowTests {
    @Test("メッセージ種別から行の種類を決める規則は 1 つだけ持つ")
    func rowKindIsShared() {
        #expect(ChatRowKind.forMessage(.command(id: "1", command: "ls", output: "")) == .commandCard)
        #expect(ChatRowKind.forMessage(.fileChange(id: "2", changes: [])) == .fileChangeCard)
        #expect(ChatRowKind.forMessage(.reasoning(id: "3", text: "x")) == .reasoning)
        #expect(ChatRowKind.forMessage(.user(id: "4", text: "x")) == .userBubble)
        #expect(ChatRowKind.forMessage(.agent(id: "5", text: "x")) == .agentBubble)
        #expect(ChatRowKind.forMessage(.error(id: "6", message: "x")) == .error)
    }

    @Test("コマンド行の見出しは、セッション詳細と同じ規則（ツール名ラベル＋コマンド本体）で作る")
    func commandCardRuleIsShared() {
        let data = SessionDetailCommandCardData(command: "Read /tmp/a.txt", output: "out")
        #expect(data.toolLabel == "Read")
        #expect(data.commandBody == "/tmp/a.txt")
    }

    @Test("ファイル変更の見出しは、セッション詳細と同じ規則（動詞＋ファイル名）で作る")
    func fileChangeRuleIsShared() {
        let diff = "@@ -1,1 +1,1 @@\n+added"
        let data = SessionDetailDiffCodeViewData(changes: [ChatFileChange(path: "a/b/foo.swift", diff: diff, kind: "edit")])
        #expect(data.title == "編集済み foo.swift")
        #expect(data.additions == 1)
        #expect(data.isExpandedByDefault == false)
    }
}
