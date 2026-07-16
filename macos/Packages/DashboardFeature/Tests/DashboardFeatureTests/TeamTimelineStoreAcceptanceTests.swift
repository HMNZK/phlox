import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

/// task-2 受け入れテスト（PM 著・実装役は編集禁止）: `TeamTimelineStore` の再構築契約。
///
/// 契約の核心 = 「signature が前回適用値と等しい間は再構築しない（makeSources を呼ばない）。
/// 変わったときだけ再構築し、items は `TeamTimelineModel.merge` と同じ順序規則で並ぶ」。
/// これにより body 評価・tick がどれだけ高頻度でも、実際の再計算は入力変化時に限定される。
@MainActor
@Suite struct TeamTimelineStoreAcceptanceTests {
    @Test func firstRefreshBuildsMergedItemsAndPublishesSources() {
        let store = TeamTimelineStore()
        var buildCount = 0
        let sources = [
            source(
                "00000000-0000-0000-0000-000000000001",
                messages: [
                    message("a-late", timestamp: Date(timeIntervalSince1970: 30)),
                ]
            ),
            source(
                "00000000-0000-0000-0000-000000000002",
                messages: [
                    message("b-early", timestamp: Date(timeIntervalSince1970: 10)),
                    message("b-middle", timestamp: Date(timeIntervalSince1970: 20)),
                ]
            ),
        ]

        let rebuilt = store.refreshIfNeeded(signature: TeamTimelineSignature(["rev-1"])) {
            buildCount += 1
            return sources
        }

        #expect(rebuilt)
        #expect(buildCount == 1)
        #expect(store.sources == sources)
        #expect(store.items.map(\.sourceMessageID) == ["b-early", "b-middle", "a-late"])
    }

    @Test func equalSignatureDoesNotRebuildEvenIfSourcesWouldDiffer() {
        let store = TeamTimelineStore()
        let initial = [
            source(
                "00000000-0000-0000-0000-000000000001",
                messages: [message("keep", timestamp: Date(timeIntervalSince1970: 10))]
            ),
        ]
        _ = store.refreshIfNeeded(signature: TeamTimelineSignature(["rev-1"])) { initial }

        var secondBuildCount = 0
        let rebuilt = store.refreshIfNeeded(signature: TeamTimelineSignature(["rev-1"])) {
            secondBuildCount += 1
            return [
                source(
                    "00000000-0000-0000-0000-000000000001",
                    messages: [message("must-not-appear", timestamp: Date(timeIntervalSince1970: 99))]
                ),
            ]
        }

        #expect(rebuilt == false)
        #expect(secondBuildCount == 0)
        #expect(store.items.map(\.sourceMessageID) == ["keep"])
    }

    @Test func changedSignatureRebuildsWithLatestSources() {
        let store = TeamTimelineStore()
        _ = store.refreshIfNeeded(signature: TeamTimelineSignature(["rev-1"])) {
            [
                source(
                    "00000000-0000-0000-0000-000000000001",
                    messages: [message("old", timestamp: Date(timeIntervalSince1970: 10))]
                ),
            ]
        }

        let rebuilt = store.refreshIfNeeded(signature: TeamTimelineSignature(["rev-2"])) {
            [
                source(
                    "00000000-0000-0000-0000-000000000001",
                    messages: [
                        message("old", timestamp: Date(timeIntervalSince1970: 10)),
                        message("streamed-delta", timestamp: Date(timeIntervalSince1970: 20)),
                    ]
                ),
            ]
        }

        #expect(rebuilt)
        #expect(store.items.map(\.sourceMessageID) == ["old", "streamed-delta"])
    }

    @Test func changedSignatureCanEmptyTheTimeline() {
        let store = TeamTimelineStore()
        _ = store.refreshIfNeeded(signature: TeamTimelineSignature(["rev-1"])) {
            [
                source(
                    "00000000-0000-0000-0000-000000000001",
                    messages: [message("gone", timestamp: Date(timeIntervalSince1970: 10))]
                ),
            ]
        }

        let rebuilt = store.refreshIfNeeded(signature: TeamTimelineSignature(["rev-2"])) { [] }

        #expect(rebuilt)
        #expect(store.sources.isEmpty)
        #expect(store.items.isEmpty)
    }

    @Test func signatureEqualityIsComponentWiseAndOrderSensitive() {
        #expect(TeamTimelineSignature(["a", "b"]) == TeamTimelineSignature(["a", "b"]))
        #expect(TeamTimelineSignature(["a", "b"]) != TeamTimelineSignature(["b", "a"]))
        #expect(TeamTimelineSignature(["a"]) != TeamTimelineSignature(["a", ""]))
    }

    private func source(
        _ uuid: String,
        messages: [TeamTimelineSourceMessage]
    ) -> TeamTimelineSource {
        TeamTimelineSource(
            id: SessionID(rawValue: UUID(uuidString: uuid)!),
            displayName: "Session",
            agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
            messages: messages
        )
    }

    private func message(_ id: String, timestamp: Date?) -> TeamTimelineSourceMessage {
        TeamTimelineSourceMessage(
            id: id,
            timestamp: timestamp,
            content: .terminalText(id)
        )
    }
}
