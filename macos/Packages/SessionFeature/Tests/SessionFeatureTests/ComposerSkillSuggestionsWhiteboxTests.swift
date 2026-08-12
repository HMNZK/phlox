import Testing
@testable import SessionFeature

@MainActor
@Suite("Whitebox: 外部 skill 候補")
struct ComposerSkillSuggestionsWhiteboxTests {

    @Test("同名でも path の異なる候補を保持する")
    func sameNameDifferentPathsArePreserved() {
        let candidates = [
            candidate(path: "/one/review"),
            candidate(path: "/two/review"),
        ]
        let controller = makeController()

        controller.updateExternalCandidates(candidates)
        controller.update(text: "/rev", cursorUTF16: 4)

        #expect(controller.candidates.map(\.skillIdentity?.path) == ["/one/review", "/two/review"])
    }

    @Test("上下移動は外部候補の範囲内でクランプする")
    func selectionMovesWithinExternalCandidates() {
        let controller = makeController()
        controller.updateExternalCandidates([candidate(path: "/one/review"), candidate(path: "/two/review")])
        controller.update(text: "/rev", cursorUTF16: 4)

        controller.moveSelection(1)
        #expect(controller.selectedIndex == 1)
        controller.moveSelection(1)
        #expect(controller.selectedIndex == 1)
        controller.moveSelection(-2)
        #expect(controller.selectedIndex == 0)
    }

    @Test("確定時に選択した候補と同じ identity を callback へ渡す")
    func acceptCallsSkillCallbackWithExactIdentity() {
        let identity = SkillIdentity(name: "review", path: "/two/review")
        let controller = makeController()
        var accepted: SkillIdentity?
        controller.onAcceptSkill = { accepted = $0 }
        controller.updateExternalCandidates([
            SuggestionCandidate(
                title: "/review",
                insertionText: "/review",
                kind: .slashCommand,
                skillIdentity: identity
            ),
        ])
        controller.update(text: "/rev", cursorUTF16: 4)

        #expect(controller.acceptSelected() == SuggestionReplacement(range: 0..<4, text: "/review "))
        #expect(accepted == identity)
    }

    private func makeController() -> ComposerSuggestionController {
        ComposerSuggestionController(slashProvider: { [] }, fileProvider: { _ in [] })
    }

    private func candidate(path: String) -> SuggestionCandidate {
        SuggestionCandidate(
            title: "/review",
            insertionText: "/review",
            kind: .slashCommand,
            skillIdentity: SkillIdentity(name: "review", path: path)
        )
    }
}
