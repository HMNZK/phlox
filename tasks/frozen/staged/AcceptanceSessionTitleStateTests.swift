// task-44（UX-01b）受け入れテスト。SessionTitleState の正規化・遷移・有効名。
//
// ベースラインでの red 理由: `SessionTitleState` / `SessionTitleSource` は本タスクが
// 新設する API で、baseline_commit には存在しない（参照未解決でコンパイル不能＝red）。
//
// 契約: tasks/task-44.md 公開名前状態 API・リテラル期待値・状態遷移・成功基準 1。
// 期待値は契約の独立リテラル。被検査関数や SessionTitleDeriver の戻り値から生成しない。
// 実装役はアサーションを変更禁止。

import Foundation
import Testing
import AgentDomain

@Suite("task-44: SessionTitleState")
struct AcceptanceSessionTitleStateTests {
    private func expectState(
        _ state: SessionTitleState,
        _ name: String,
        _ source: SessionTitleSource,
        _ flowerName: String?,
        _ fullDerivedTitle: String?,
        _ label: String
    ) {
        #expect(state.name == name, Comment(rawValue: "\(label) name"))
        #expect(state.source == source, Comment(rawValue: "\(label) source"))
        #expect(state.flowerName == flowerName, Comment(rawValue: "\(label) flowerName"))
        #expect(state.fullDerivedTitle == fullDerivedTitle, Comment(rawValue: "\(label) fullDerivedTitle"))
    }

    private func reinit(_ state: SessionTitleState) -> SessionTitleState {
        SessionTitleState(
            name: state.name,
            source: state.source,
            flowerName: state.flowerName,
            fullDerivedTitle: state.fullDerivedTitle
        )
    }

    // MARK: - generated / legacy

    @Test("generated(flowerName: \" Rose \\n\") → (Rose, flower, Rose, nil)")
    func generatedTrimsFlowerName() {
        let state = SessionTitleState.generated(flowerName: " Rose \n")
        expectState(state, "Rose", .flower, "Rose", nil, "generated trim")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent generated trim"))
    }

    @Test("generated(flowerName: \" \\n\") → (\"\", manual, nil, nil)")
    func generatedBlankBecomesManual() {
        let state = SessionTitleState.generated(flowerName: " \n")
        expectState(state, "", .manual, nil, nil, "generated blank")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent generated blank"))
    }

    @Test("legacy(name: \" Rose \") は入力名をそのまま手動保持し花名を推測しない")
    func legacyKeepsRawName() {
        let state = SessionTitleState.legacy(name: " Rose ")
        expectState(state, " Rose ", .manual, nil, nil, "legacy")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent legacy"))
    }

    // MARK: - 公開 initializer リテラル

    @Test("flower で name と正規化花名が一致すれば flower のまま")
    func flowerMatchingNameStaysFlower() {
        let state = SessionTitleState(
            name: "Rose",
            source: .flower,
            flowerName: " Rose ",
            fullDerivedTitle: nil
        )
        expectState(state, "Rose", .flower, "Rose", nil, "flower match")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent flower match"))
    }

    @Test("flower で name と花名が不一致なら manual へ退避し name を置換しない")
    func flowerNameMismatchBecomesManual() {
        let state = SessionTitleState(
            name: "Lily",
            source: .flower,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        expectState(state, "Lily", .manual, "Rose", nil, "flower mismatch")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent flower mismatch"))
    }

    @Test("flower で空花名なら manual へ退避し name を残す")
    func flowerBlankFlowerNameBecomesManual() {
        let state = SessionTitleState(
            name: "Rose",
            source: .flower,
            flowerName: " \n",
            fullDerivedTitle: nil
        )
        expectState(state, "Rose", .manual, nil, nil, "flower blank flowerName")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent flower blank"))
    }

    @Test("flower で空文字の導出全文は不整合で manual へ退避する")
    func flowerEmptyDerivedTitleBecomesManual() {
        let state = SessionTitleState(
            name: "Rose",
            source: .flower,
            flowerName: "Rose",
            fullDerivedTitle: ""
        )
        expectState(state, "Rose", .manual, "Rose", nil, "flower empty derived")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent flower empty derived"))
    }

    @Test("derived で導出全文 nil は不整合で manual へ退避する")
    func derivedNilFullTitleBecomesManual() {
        let state = SessionTitleState(
            name: "修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: nil
        )
        expectState(state, "修正", .manual, "Rose", nil, "derived nil full")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent derived nil"))
    }

    @Test("derived で導出全文が name と一致しないなら manual へ退避する")
    func derivedMismatchedFullTitleBecomesManual() {
        let state = SessionTitleState(
            name: "修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "別件"
        )
        expectState(state, "修正", .manual, "Rose", nil, "derived mismatch")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent derived mismatch"))
    }

    @Test("derived で保存全文が複数行なら正規化済み単一行ではないので manual へ退避する")
    func derivedMultilineFullTitleBecomesManual() {
        let state = SessionTitleState(
            name: "修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "修正\n詳細"
        )
        expectState(state, "修正", .manual, "Rose", nil, "derived multiline")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent derived multiline"))
    }

    @Test("derived で花名が空白なら nil にし、正規化済み単一行なら derived のまま")
    func derivedValidFullTitleKeepsDerivedAndDropsBlankFlower() {
        let state = SessionTitleState(
            name: "修正",
            source: .derived,
            flowerName: " \n",
            fullDerivedTitle: "修正"
        )
        expectState(state, "修正", .derived, nil, "修正", "derived valid")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent derived valid"))
    }

    @Test("manual は入力 name を破壊せず花名を正規化し導出全文を必ず nil にする")
    func manualKeepsRawNameAndClearsDerived() {
        let state = SessionTitleState(
            name: " 手動\n名 ",
            source: .manual,
            flowerName: " Rose ",
            fullDerivedTitle: "旧候補"
        )
        expectState(state, " 手動\n名 ", .manual, "Rose", nil, "manual keep")
        #expect(reinit(state) == state, Comment(rawValue: "idempotent manual"))
    }

    // MARK: - 状態遷移

    @Test("/review では flower を維持する")
    func reviewDoesNotLeaveFlower() {
        let start = SessionTitleState.generated(flowerName: "Rose")
        let next = start.receivingUserMessage("/review")
        expectState(next, "Rose", .flower, "Rose", nil, "/review keeps flower")
        #expect(next == start, Comment(rawValue: "/review unchanged identity"))
    }

    @Test("flower にログイン画面を修正\\n詳細 を渡すと derived。花名を保持する")
    func flowerEligibleMessageBecomesDerived() {
        let start = SessionTitleState.generated(flowerName: "Rose")
        let next = start.receivingUserMessage("ログイン画面を修正\n詳細")
        expectState(
            next,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "eligible derived"
        )
    }

    @Test("二度目の適格本文では derived を変えない")
    func secondEligibleMessageDoesNotChangeDerived() {
        let derived = SessionTitleState.generated(flowerName: "Rose")
            .receivingUserMessage("ログイン画面を修正\n詳細")
        let again = derived.receivingUserMessage("通知を修正")
        expectState(
            again,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "second eligible"
        )
        #expect(again == derived, Comment(rawValue: "second eligible identity"))
    }

    @Test("derived への再配送でも導出名を変えない")
    func redeliveryDoesNotChangeDerived() {
        let derived = SessionTitleState.generated(flowerName: "Rose")
            .receivingUserMessage("ログイン画面を修正\n詳細")
        let again = derived.receivingUserMessage("ログイン画面を修正\n詳細")
        #expect(again == derived, Comment(rawValue: "redelivery identity"))
    }

    @Test("manual への本文は無変更")
    func manualIgnoresUserMessage() {
        let manual = SessionTitleState.legacy(name: " 手動\n名 ")
        let next = manual.receivingUserMessage("ログイン画面を修正\n詳細")
        expectState(next, " 手動\n名 ", .manual, nil, nil, "manual ignores body")
        #expect(next == manual, Comment(rawValue: "manual identity"))
    }

    @Test("通常手動 rename は前後だけ除去し花名を保持し導出全文を解除する")
    func renamedBecomesManualKeepingFlower() {
        let derived = SessionTitleState.generated(flowerName: "Rose")
            .receivingUserMessage("ログイン画面を修正\n詳細")
        let renamed = derived.renamed(to: " 通知を修正 \n")
        expectState(renamed, "通知を修正", .manual, "Rose", nil, "rename")
    }

    @Test("花名と同じ文字列へ rename しても flower に戻さない")
    func renameToFlowerNameStaysManual() {
        let flower = SessionTitleState.generated(flowerName: "Rose")
        let renamed = flower.renamed(to: "Rose")
        expectState(renamed, "Rose", .manual, "Rose", nil, "rename to flower")
    }

    @Test("空欄へ rename すると空名の manual になり以後も自動命名しない")
    func renameToBlankStaysEmptyManual() {
        let flower = SessionTitleState.generated(flowerName: "Rose")
        let renamed = flower.renamed(to: " \n")
        expectState(renamed, "", .manual, "Rose", nil, "rename blank")
        let afterMessage = renamed.receivingUserMessage("ログイン画面を修正\n詳細")
        expectState(afterMessage, "", .manual, "Rose", nil, "empty manual ignores body")
    }

    @Test("内部改行・空白を含む長い手動名を rename 後も保持する")
    func renamedKeepsInternalNewlinesAndLength() {
        let longName = "手動名の内部空白 と\n改行を含む長い名前ABCDEFG"
        let renamed = SessionTitleState.generated(flowerName: "Rose")
            .renamed(to: " \(longName) ")
        expectState(renamed, longName, .manual, "Rose", nil, "long manual")
    }

    // MARK: - effectiveName

    @Test("空名の fallback は abc123 をそのまま返す")
    func emptyNameUsesFallbackLiteral() {
        let empty = SessionTitleState.generated(flowerName: " \n")
        #expect(empty.effectiveName(fallback: "abc123") == "abc123", Comment(rawValue: "empty fallback"))
    }

    @Test("effectiveName は前後だけ除去し文字数では短縮しない")
    func effectiveNameTrimsButDoesNotShorten() {
        let longName = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789長い手動名"
        let state = SessionTitleState.legacy(name: " \(longName) \n")
        #expect(
            state.effectiveName(fallback: "abc123") == longName,
            Comment(rawValue: "no length truncation")
        )
    }

    @Test("effectiveName は内部改行を落とさない")
    func effectiveNameKeepsInternalNewlines() {
        let state = SessionTitleState.legacy(name: " 手動\n名 ")
        #expect(state.effectiveName(fallback: "abc123") == "手動\n名", Comment(rawValue: "internal newline"))
    }

    @Test("SessionTitleSource の rawValue は flower / derived / manual")
    func sourceRawValuesMatchContract() {
        #expect(SessionTitleSource.flower.rawValue == "flower")
        #expect(SessionTitleSource.derived.rawValue == "derived")
        #expect(SessionTitleSource.manual.rawValue == "manual")
    }
}
