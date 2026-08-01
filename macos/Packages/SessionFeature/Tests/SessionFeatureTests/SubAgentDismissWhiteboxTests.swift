import Foundation
import Testing
@testable import SessionFeature

@Suite("SubAgent dismiss whitebox")
@MainActor
struct SubAgentDismissWhiteboxTests {
    @Test
    func dismissKeepsSubAgentButRemovesItFromStripAndClearsSelection() {
        let model = ChatSubAgentModel()
        model.upsertSubAgent(
            toolUseId: "toolu_drop",
            subagentType: "Explore",
            description: "drop",
            status: .failed,
            summary: nil,
            outputFile: nil
        )
        model.selectSubAgent("toolu_drop")

        model.dismissSubAgent("toolu_drop")

        #expect(model.subAgents.contains { $0.id == "toolu_drop" })
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_drop" })
        #expect(model.selectedSubAgentId == nil)
    }

    @Test
    func dismissingUnselectedSubAgentDoesNotChangeSelection() {
        let model = ChatSubAgentModel()
        model.upsertSubAgent(
            toolUseId: "toolu_selected",
            subagentType: "Explore",
            description: "selected",
            status: .running,
            summary: nil,
            outputFile: nil
        )
        model.upsertSubAgent(
            toolUseId: "toolu_other",
            subagentType: "Explore",
            description: "other",
            status: .running,
            summary: nil,
            outputFile: nil
        )
        model.selectSubAgent("toolu_selected")

        model.dismissSubAgent("toolu_other")

        #expect(model.selectedSubAgentId == "toolu_selected")
        #expect(model.stripSubAgents.contains { $0.id == "toolu_selected" })
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_other" })
    }

    @Test
    func dismissedSubAgentStaysOutAfterUpsert() {
        let model = ChatSubAgentModel()
        model.upsertSubAgent(
            toolUseId: "toolu_sticky",
            subagentType: "Explore",
            description: "before",
            status: .running,
            summary: nil,
            outputFile: nil
        )
        model.dismissSubAgent("toolu_sticky")

        model.upsertSubAgent(
            toolUseId: "toolu_sticky",
            subagentType: "",
            description: "",
            status: .failed,
            summary: "updated",
            outputFile: nil
        )

        #expect(model.subAgents.contains { $0.id == "toolu_sticky" && $0.status == .failed })
        #expect(!model.stripSubAgents.contains { $0.id == "toolu_sticky" })
    }

    @Test
    func dismissButtonIsVisibleAndInteractiveOnlyWhileHovering() {
        let hidden = SubAgentDismissButtonPresentation.state(isHovering: false)
        #expect(!hidden.isVisible)
        #expect(!hidden.allowsHitTesting)

        let visible = SubAgentDismissButtonPresentation.state(isHovering: true)
        #expect(visible.isVisible)
        #expect(visible.allowsHitTesting)
    }
}
