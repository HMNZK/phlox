import Testing
@testable import SessionFeature

// 非 Codex セッションで `/` を打つと候補が消える不具合の回帰テスト。
// 非 Codex では毎キーストロークで updateExternalCandidates(nil) が呼ばれる
// （外部候補を一度も設定していなくても呼ばれる）。この呼び出しは候補を空にせず、
// 通常経路（slashProvider 等）で現在のクエリの候補を再計算しなければならない。

@MainActor
@Suite("Whitebox: 外部候補の解除で通常候補が消えない")
struct ComposerExternalCandidatesReleaseWhiteboxTests {

    @Test("外部候補を一度も設定していなくても、解除呼び出しで通常候補が消えない")
    func releasingUnsetExternalCandidatesKeepsNormalCandidates() {
        let controller = ComposerSuggestionController(
            slashProvider: {
                [
                    SuggestionCandidate(title: "/foo", insertionText: "/foo", kind: .slashCommand),
                    SuggestionCandidate(title: "/bar", insertionText: "/bar", kind: .slashCommand),
                ]
            },
            fileProvider: { _ in [] }
        )

        controller.update(text: "/fo", cursorUTF16: 3)
        #expect(controller.candidates.map(\.title) == ["/foo"])

        // 非 Codex セッションが毎キーストロークで呼ぶ経路（externalCandidates は一度も
        // 設定されていない＝既に nil）。これで候補が消えてはならない。
        controller.updateExternalCandidates(nil)

        #expect(
            controller.candidates.map(\.title) == ["/foo"],
            "外部候補の解除で候補を空にせず、通常経路の候補を保つこと"
        )
    }

    @Test("外部候補が設定された後の解除でも、通常経路の候補へ戻る")
    func releasingSetExternalCandidatesRestoresNormalCandidates() {
        let controller = ComposerSuggestionController(
            slashProvider: {
                [SuggestionCandidate(title: "/foo", insertionText: "/foo", kind: .slashCommand)]
            },
            fileProvider: { _ in [] }
        )

        controller.update(text: "/fo", cursorUTF16: 3)
        controller.updateExternalCandidates([
            SuggestionCandidate(title: "/foo", insertionText: "/foo-skill", kind: .slashCommand),
        ])
        #expect(controller.candidates.map(\.insertionText) == ["/foo-skill"])

        controller.updateExternalCandidates(nil)

        #expect(
            controller.candidates.map(\.insertionText) == ["/foo"],
            "外部候補の解除で通常経路（slashProvider）の候補へ戻ること"
        )
    }

    @Test("Codex 経路（外部候補の設定）は解除しない限り従来どおり外部候補だけを表示する")
    func externalCandidatesStillWinWhileSet() {
        let controller = ComposerSuggestionController(
            slashProvider: {
                [SuggestionCandidate(title: "/foo", insertionText: "/foo", kind: .slashCommand)]
            },
            fileProvider: { _ in [] }
        )

        controller.update(text: "/fo", cursorUTF16: 3)
        controller.updateExternalCandidates([
            SuggestionCandidate(title: "/foo", insertionText: "/foo-skill", kind: .slashCommand),
        ])
        controller.update(text: "/fo", cursorUTF16: 3)

        #expect(
            controller.candidates.map(\.insertionText) == ["/foo-skill"],
            "外部候補が非 nil の間は、update() を再度呼んでも外部候補だけを表示すること"
        )
    }
}
