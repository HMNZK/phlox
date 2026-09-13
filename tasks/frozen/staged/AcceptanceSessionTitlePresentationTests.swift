// 実パス: macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitlePresentationTests.swift
//
// task-45（UX-01c）の受け入れテスト。
//
// ベースラインでの red 理由: `SessionTitlePresentation` は本タスクが新設する API で、
// baseline には存在しない。依存の `SessionTitleState` も task-44 成立前の作業ツリーでは
// 未実装のため、参照未解決でコンパイル不能＝red が正常。
//
// 契約: tasks/task-45.md 成功基準 1。期待値は独立リテラルであり、
// `SessionTitlePresentation` や `SessionTitleDeriver` の戻り値から生成しない。
// 実装役はアサーションを変更禁止。

import Foundation
import Testing
import AgentDomain

@Suite("task-45: session title presentation")
struct AcceptanceSessionTitlePresentationTests {
    private let fallback = "abc123"
    private let workspace = "/tmp/project"

    private func make(
        _ state: SessionTitleState,
        workspacePath: String = "/tmp/project"
    ) -> SessionTitlePresentation {
        SessionTitlePresentation(state: state, fallback: "abc123", workspacePath: workspacePath)
    }

    @Test("generated Rose: primary/secondary/fullTitle/AX")
    func generatedRoseFields() {
        let presented = make(.generated(flowerName: "Rose"))
        #expect(presented.primary == "Rose", Comment(rawValue: "generated primary"))
        #expect(presented.secondary == nil, Comment(rawValue: "generated secondary"))
        #expect(presented.fullTitle == "Rose", Comment(rawValue: "generated fullTitle"))
        #expect(presented.accessibilityValue == "Rose", Comment(rawValue: "generated AX"))
    }

    @Test("derived ログイン画面を修正 / 元花名 Rose")
    func derivedLoginFixWithFlower() {
        let state = SessionTitleState(
            name: "ログイン画面を修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "ログイン画面を修正"
        )
        let presented = make(state)
        #expect(presented.primary == "ログイン画面を修正", Comment(rawValue: "derived primary"))
        #expect(presented.secondary == "Rose", Comment(rawValue: "derived secondary"))
        #expect(presented.fullTitle == "ログイン画面を修正", Comment(rawValue: "derived fullTitle"))
        #expect(presented.accessibilityValue == "ログイン画面を修正", Comment(rawValue: "derived AX"))
    }

    @Test("manual 通知を修正 / 元花名 Rose")
    func manualNoticeFixWithFlower() {
        let state = SessionTitleState(
            name: "通知を修正",
            source: .manual,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "通知を修正", Comment(rawValue: "manual primary"))
        #expect(presented.secondary == "Rose", Comment(rawValue: "manual secondary"))
        #expect(presented.fullTitle == "通知を修正", Comment(rawValue: "manual fullTitle"))
        #expect(presented.accessibilityValue == "通知を修正", Comment(rawValue: "manual AX"))
    }

    @Test("manual Rose / 元花名 Rose: 補助なし、全文は主名")
    func manualSameAsFlowerHidesSecondary() {
        let state = SessionTitleState(
            name: "Rose",
            source: .manual,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "Rose", Comment(rawValue: "same flower primary"))
        #expect(presented.secondary == nil, Comment(rawValue: "same flower secondary"))
        #expect(presented.fullTitle == "Rose", Comment(rawValue: "same flower fullTitle"))
        #expect(presented.accessibilityValue == "Rose", Comment(rawValue: "same flower AX"))
    }

    @Test("空 manual / 元花名 Rose: fallback と補助花名")
    func emptyManualKeepsFlowerAndUsesFallback() {
        let state = SessionTitleState(
            name: "",
            source: .manual,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "abc123", Comment(rawValue: "empty manual primary"))
        #expect(presented.secondary == "Rose", Comment(rawValue: "empty manual secondary"))
        #expect(presented.fullTitle == "abc123", Comment(rawValue: "empty manual fullTitle"))
        #expect(presented.accessibilityValue == "abc123", Comment(rawValue: "empty manual AX"))
    }

    @Test("legacy Rose: 補助なし")
    func legacyRoseFields() {
        let presented = make(.legacy(name: "Rose"))
        #expect(presented.primary == "Rose", Comment(rawValue: "legacy primary"))
        #expect(presented.secondary == nil, Comment(rawValue: "legacy secondary"))
        #expect(presented.fullTitle == "Rose", Comment(rawValue: "legacy fullTitle"))
        #expect(presented.accessibilityValue == "Rose", Comment(rawValue: "legacy AX"))
    }

    @Test("legacy 空名: fallback、補助なし")
    func legacyEmptyNameUsesFallback() {
        let presented = make(.legacy(name: ""))
        #expect(presented.primary == "abc123", Comment(rawValue: "legacy empty primary"))
        #expect(presented.secondary == nil, Comment(rawValue: "legacy empty secondary"))
        #expect(presented.fullTitle == "abc123", Comment(rawValue: "legacy empty fullTitle"))
        #expect(presented.accessibilityValue == "abc123", Comment(rawValue: "legacy empty AX"))
    }

    @Test("33 Character の manual: 切らず、元花名に従う")
    func thirtyThreeCharacterManualKeepsFullName() {
        let name = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567"
        #expect(name.count == 33, Comment(rawValue: "33 Character fixture"))
        let state = SessionTitleState(
            name: name,
            source: .manual,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "33 manual primary"))
        #expect(presented.secondary == "Rose", Comment(rawValue: "33 manual secondary follows flower"))
        #expect(presented.fullTitle == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "33 manual fullTitle"))
        #expect(presented.accessibilityValue == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "33 manual AX"))
    }

    @Test("33 Character の derived / 元花名 Rose: 主名は省略形、全文は 33 Character")
    func thirtyThreeCharacterDerivedUsesSavedFullTitle() {
        let full = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567"
        let truncated = "ABCDEFGHIJKLMNOPQRSTUVWXYZ12345…"
        #expect(full.count == 33, Comment(rawValue: "33 Character full fixture"))
        #expect(truncated.count == 32, Comment(rawValue: "31 Character + ellipsis"))
        let state = SessionTitleState(
            name: truncated,
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: full
        )
        let presented = make(state)
        #expect(presented.primary == "ABCDEFGHIJKLMNOPQRSTUVWXYZ12345…", Comment(rawValue: "33 derived primary"))
        #expect(presented.secondary == "Rose", Comment(rawValue: "33 derived secondary"))
        #expect(presented.fullTitle == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "33 derived fullTitle"))
        #expect(presented.accessibilityValue == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "33 derived AX"))
    }

    @Test("derived 全文 nil の不整合入力は task-44 正規化後の manual として表示")
    func inconsistentDerivedNilFullTitleBecomesManualDisplay() {
        let state = SessionTitleState(
            name: "修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "修正", Comment(rawValue: "inconsistent derived primary"))
        #expect(presented.secondary == "Rose", Comment(rawValue: "inconsistent derived secondary"))
        #expect(presented.fullTitle == "修正", Comment(rawValue: "inconsistent derived fullTitle"))
        #expect(presented.accessibilityValue == "修正", Comment(rawValue: "inconsistent derived AX"))
    }

    @Test("flower 不一致入力 name=Lily / 花名=Rose は手動として補助を出す")
    func mismatchedFlowerInputShowsLilyWithRoseSecondary() {
        let state = SessionTitleState(
            name: "Lily",
            source: .flower,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "Lily", Comment(rawValue: "mismatch primary"))
        #expect(presented.secondary == "Rose", Comment(rawValue: "mismatch secondary"))
        #expect(presented.fullTitle == "Lily", Comment(rawValue: "mismatch fullTitle"))
        #expect(presented.accessibilityValue == "Lily", Comment(rawValue: "mismatch AX"))
    }

    @Test("花名が空白だけの manual 修正は補助なし")
    func whitespaceOnlyFlowerNameOmitsSecondary() {
        let state = SessionTitleState(
            name: "修正",
            source: .manual,
            flowerName: " \n",
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "修正", Comment(rawValue: "blank flower primary"))
        #expect(presented.secondary == nil, Comment(rawValue: "blank flower secondary"))
        #expect(presented.fullTitle == "修正", Comment(rawValue: "blank flower fullTitle"))
        #expect(presented.accessibilityValue == "修正", Comment(rawValue: "blank flower AX"))
    }

    @Test("花名ありの help は全文・花名・作業場所を改行連結する")
    func helpTextWithFlowerJoinsThreeLines() {
        let state = SessionTitleState(
            name: "ログイン画面を修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "ログイン画面を修正"
        )
        let presented = make(state)
        #expect(
            presented.helpText == "ログイン画面を修正\n花名: Rose\n作業場所: /tmp/project",
            Comment(rawValue: "help with flower")
        )
    }

    @Test("花名なしの legacy Rose の help は花名行を省略する")
    func helpTextWithoutFlowerOmitsFlowerLine() {
        let presented = make(.legacy(name: "Rose"))
        #expect(
            presented.helpText == "Rose\n作業場所: /tmp/project",
            Comment(rawValue: "help without flower")
        )
    }

    @Test("空 workspace の末尾行は作業場所: で、パスを推測しない")
    func emptyWorkspaceHelpDoesNotInventPath() {
        let presented = make(.legacy(name: "Rose"), workspacePath: "")
        #expect(
            presented.helpText == "Rose\n作業場所: ",
            Comment(rawValue: "empty workspace help")
        )
        #expect(presented.helpText.hasSuffix("作業場所: "), Comment(rawValue: "empty workspace suffix"))
        #expect(!presented.helpText.contains("/tmp/project"), Comment(rawValue: "no guessed path"))
    }

    @Test("花名と primary が同じでも help の花名行を保持する")
    func helpKeepsFlowerLineWhenEqualToPrimary() {
        let presented = make(.generated(flowerName: "Rose"))
        #expect(
            presented.helpText == "Rose\n花名: Rose\n作業場所: /tmp/project",
            Comment(rawValue: "help keeps flower when equal")
        )
        let manualSame = make(
            SessionTitleState(
                name: "Rose",
                source: .manual,
                flowerName: "Rose",
                fullDerivedTitle: nil
            )
        )
        #expect(
            manualSame.helpText == "Rose\n花名: Rose\n作業場所: /tmp/project",
            Comment(rawValue: "manual same flower help")
        )
    }

    @Test("日本語の手動名を保持する")
    func japaneseManualNameIsKept() {
        let state = SessionTitleState(
            name: "通知の重複を修正",
            source: .manual,
            flowerName: nil,
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "通知の重複を修正", Comment(rawValue: "japanese primary"))
        #expect(presented.fullTitle == "通知の重複を修正", Comment(rawValue: "japanese fullTitle"))
        #expect(presented.accessibilityValue == "通知の重複を修正", Comment(rawValue: "japanese AX"))
        #expect(presented.secondary == nil, Comment(rawValue: "japanese secondary"))
    }

    @Test("長い英数字の手動名を保持する")
    func longAlphanumericManualNameIsKept() {
        let name = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567"
        let state = SessionTitleState(
            name: name,
            source: .manual,
            flowerName: nil,
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "alnum primary"))
        #expect(presented.fullTitle == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "alnum fullTitle"))
        #expect(presented.accessibilityValue == "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567", Comment(rawValue: "alnum AX"))
    }

    @Test("複合絵文字を含む手動名を保持する")
    func compoundEmojiManualNameIsKept() {
        let name = "👨‍👩‍👧‍👦修正"
        let state = SessionTitleState(
            name: name,
            source: .manual,
            flowerName: nil,
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "👨‍👩‍👧‍👦修正", Comment(rawValue: "emoji primary"))
        #expect(presented.fullTitle == "👨‍👩‍👧‍👦修正", Comment(rawValue: "emoji fullTitle"))
        #expect(presented.accessibilityValue == "👨‍👩‍👧‍👦修正", Comment(rawValue: "emoji AX"))
        #expect(presented.secondary == nil, Comment(rawValue: "emoji secondary"))
    }

    @Test("内部改行と内部空白を含む手動名を保持する")
    func internalNewlineAndSpacesInManualNameAreKept() {
        let state = SessionTitleState(
            name: "手動\n名  です",
            source: .manual,
            flowerName: nil,
            fullDerivedTitle: nil
        )
        let presented = make(state)
        #expect(presented.primary == "手動\n名  です", Comment(rawValue: "internal whitespace primary"))
        #expect(presented.fullTitle == "手動\n名  です", Comment(rawValue: "internal whitespace fullTitle"))
        #expect(presented.accessibilityValue == "手動\n名  です", Comment(rawValue: "internal whitespace AX"))
    }

    @Test("繰り返し構築しても同じ結果で、入力状態を変更しない")
    func repeatedConstructionIsStableAndDoesNotMutateState() {
        let state = SessionTitleState(
            name: "ログイン画面を修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "ログイン画面を修正"
        )
        let snapshotName = state.name
        let snapshotSource = state.source
        let snapshotFlower = state.flowerName
        let snapshotFull = state.fullDerivedTitle
        let first = make(state)
        let second = make(state)
        #expect(first == second, Comment(rawValue: "repeat equal"))
        #expect(first.primary == "ログイン画面を修正", Comment(rawValue: "repeat primary"))
        #expect(first.secondary == "Rose", Comment(rawValue: "repeat secondary"))
        #expect(first.fullTitle == "ログイン画面を修正", Comment(rawValue: "repeat fullTitle"))
        #expect(first.helpText == "ログイン画面を修正\n花名: Rose\n作業場所: /tmp/project", Comment(rawValue: "repeat help"))
        #expect(first.accessibilityValue == "ログイン画面を修正", Comment(rawValue: "repeat AX"))
        #expect(state.name == snapshotName, Comment(rawValue: "name unchanged"))
        #expect(state.source == snapshotSource, Comment(rawValue: "source unchanged"))
        #expect(state.flowerName == snapshotFlower, Comment(rawValue: "flower unchanged"))
        #expect(state.fullDerivedTitle == snapshotFull, Comment(rawValue: "fullDerived unchanged"))
        #expect(state.name == "ログイン画面を修正", Comment(rawValue: "name literal"))
        #expect(state.flowerName == "Rose", Comment(rawValue: "flower literal"))
        #expect(state.fullDerivedTitle == "ログイン画面を修正", Comment(rawValue: "fullDerived literal"))
    }

    @Test("公開 initializer は fallback と workspacePath を取る")
    func publicInitializerMatchesContract() {
        let state = SessionTitleState.generated(flowerName: "Rose")
        let presented = SessionTitlePresentation(
            state: state,
            fallback: "abc123",
            workspacePath: "/tmp/project"
        )
        let primary: String = presented.primary
        let fullTitle: String = presented.fullTitle
        let helpText: String = presented.helpText
        let accessibilityValue: String = presented.accessibilityValue
        #expect(primary == "Rose", Comment(rawValue: "public primary"))
        #expect(presented.secondary == nil, Comment(rawValue: "public secondary"))
        #expect(fullTitle == "Rose", Comment(rawValue: "public fullTitle"))
        #expect(helpText == "Rose\n花名: Rose\n作業場所: /tmp/project", Comment(rawValue: "public help"))
        #expect(accessibilityValue == "Rose", Comment(rawValue: "public AX"))
        #expect(fallback == "abc123", Comment(rawValue: "fallback literal unused except as argument"))
        #expect(workspace == "/tmp/project", Comment(rawValue: "workspace literal unused except as argument"))
    }
}
