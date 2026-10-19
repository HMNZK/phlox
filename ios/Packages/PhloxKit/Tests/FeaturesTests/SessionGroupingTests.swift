import Testing
import Foundation
import PhloxCore
@testable import Features

@Suite struct SessionGroupingTests {
    private let projectP = ProjectSummary(id: "p", name: "Phlox")
    private let projectQ = ProjectSummary(id: "q", name: "SimpleBudget")

    private func session(
        _ id: String,
        status: SessionStatus = .running,
        projectID: String? = nil,
        projectName: String? = nil,
        parentID: String? = nil,
        unread: Bool = false,
        stalled: Bool = false,
        since: Date? = nil
    ) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: status,
            projectId: projectID,
            projectName: projectName,
            isStalled: stalled,
            hasUnseenCompletion: unread,
            parentSessionId: parentID,
            statusEnteredAt: since,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func fourAttentionStatesAreSeparatedAndNotDuplicatedInProjects() {
        let sessions = [
            session("approval", status: .awaitingApproval(prompt: "p"), projectID: "p", projectName: "Phlox"),
            session("question", status: .awaitingUserQuestion, projectID: "p", projectName: "Phlox"),
            session("error", status: .error(message: "e"), projectID: "p", projectName: "Phlox"),
            session("stalled", status: .running, projectID: "p", projectName: "Phlox", stalled: true),
            session("running", projectID: "p", projectName: "Phlox"),
        ]

        let projection = SessionListProjection.make(sessions: sessions, projects: [projectP])

        #expect(projection.attentionSessions.map(\.id) == ["approval", "question", "error", "stalled"])
        #expect(projection.projectGroups.first?.roots.map(\.id) == ["running"])
        #expect(projection.projectGroups.first?.allSessions.map(\.id) == sessions.map(\.id))
        #expect(projection.projectGroups.first?.sessionCount == sessions.count)
    }

    @Test func projectGroupsFollowAPIOrderAndOmitProjectsWithoutSessions() {
        let sessions = [
            session("p-session", projectID: "p", projectName: "Phlox"),
            session("q-session", projectID: "q", projectName: "SimpleBudget"),
        ]
        let projects = [projectQ, projectP, ProjectSummary(id: "empty", name: "Empty")]

        let projection = SessionListProjection.make(sessions: sessions, projects: projects)

        #expect(projection.projectGroups.map(\.id) == ["id:q", "id:p"])
        #expect(projection.otherGroup == nil)
    }

    @Test func attentionOnlyProjectsLeaveOnlyTheAttentionSection() {
        let sessions = [
            session("approval", status: .awaitingApproval(prompt: "p"), projectID: "p", projectName: "Phlox"),
            session("question", status: .awaitingUserQuestion, projectID: "q", projectName: "SimpleBudget"),
        ]

        let projection = SessionListProjection.make(sessions: sessions, projects: [projectP, projectQ])

        #expect(projection.attentionSessions.map(\.id) == ["approval", "question"])
        #expect(projection.projectGroups.isEmpty)
        #expect(projection.otherGroup == nil)
    }

    @Test func sessionsWithSameProjectIDStayGroupedAcrossNameChanges() {
        let sessions = [
            session("first", projectID: "p", projectName: "Alpha"),
            session("other", projectID: "q", projectName: "Beta"),
            session("renamed", projectID: "p", projectName: "Alpha Renamed"),
        ]

        let projection = SessionListProjection.make(sessions: sessions)

        #expect(projection.projectGroups.map(\.id) == ["id:p", "id:q"])
        #expect(projection.projectGroups.first?.title == "Alpha")
        #expect(projection.projectGroups.first?.allSessions.map(\.id) == ["first", "renamed"])
    }

    @Test func nilProjectOrderKeepsReceivedProjectOrderAndPutsUnassignedLast() {
        let sessions = [
            session("first", projectName: "Garden"),
            session("unassigned", projectName: nil),
            session("second", projectName: "Phlox"),
        ]

        let projection = SessionListProjection.make(sessions: sessions)

        #expect(projection.projectGroups.map(\.id) == ["name:Garden", "name:Phlox"])
        #expect(projection.otherGroup?.roots.map(\.id) == ["unassigned"])
        #expect(projection.otherGroup?.title == "その他")
        #expect(projection.otherGroup?.isOther == true)
    }

    @Test func childrenAreNestedOnlyWhenParentIsInTheSameProject() {
        let sessions = [
            session("root", projectID: "p", projectName: "Phlox"),
            session("child", projectID: "p", projectName: "Phlox", parentID: "root"),
            session("grandchild", projectID: "p", projectName: "Phlox", parentID: "child"),
            session("cross-project-child", projectID: "q", projectName: "SimpleBudget", parentID: "root"),
            session("orphan", projectID: "p", projectName: "Phlox", parentID: "missing"),
        ]

        let projection = SessionListProjection.make(sessions: sessions, projects: [projectP, projectQ])
        let phlox = projection.projectGroups[0]
        let simpleBudget = projection.projectGroups[1]
        let root = phlox.roots.first { $0.id == "root" }

        #expect(root?.children.map(\.id) == ["child"])
        #expect(root?.children.first?.children.map(\.id) == ["grandchild"])
        #expect(root?.descendantCount == 2)
        #expect(root?.collapsedChildCountLabel(isExpanded: false) == "+2")
        #expect(root?.collapsedChildCountLabel(isExpanded: true) == nil)
        #expect(phlox.roots.map(\.id) == ["root", "orphan"])
        #expect(phlox.roots.last?.collapsedChildCountLabel(isExpanded: false) == nil)
        #expect(simpleBudget.roots.map(\.id) == ["cross-project-child"])
    }

    @Test func collapsedSummaryCountsOnlyDisplayedRowsAndDescendants() throws {
        let sessions = [
            session("root", projectID: "p", projectName: "Phlox"),
            session("child", projectID: "p", projectName: "Phlox", parentID: "root"),
            session("grandchild", projectID: "p", projectName: "Phlox", parentID: "child"),
            session("approval", status: .awaitingApproval(prompt: "p"), projectID: "p", projectName: "Phlox"),
            session("question", status: .awaitingUserQuestion, projectID: "p", projectName: "Phlox"),
            session("error", status: .error(message: "e"), projectID: "p", projectName: "Phlox"),
            session("stalled", status: .running, projectID: "p", projectName: "Phlox", stalled: true),
            session("unread-1", status: .completed(exitCode: 0), projectID: "p", projectName: "Phlox", unread: true),
            session("unread-2", status: .completed(exitCode: 0), projectID: "p", projectName: "Phlox", unread: true),
            session("unread-3", status: .completed(exitCode: 0), projectID: "p", projectName: "Phlox", unread: true),
        ]

        let projection = SessionListProjection.make(sessions: sessions, projects: [projectP])
        let summary = try #require(projection.projectGroups.first?.collapsedSummary)

        #expect(summary.entries.map(\.label) == [
            "実行中 3", "未読 3",
        ])
        #expect(projection.attentionSessions.map(\.id) == ["approval", "question", "error", "stalled"])
    }

    @Test func attentionOrdersOldestStatusFirst() {
        let sessions = [
            session("new", status: .awaitingUserQuestion, since: Date(timeIntervalSince1970: 30)),
            session("old", status: .error(message: "e"), since: Date(timeIntervalSince1970: 10)),
            session("middle", status: .awaitingApproval(prompt: "p"), since: Date(timeIntervalSince1970: 20)),
            session("running", since: Date(timeIntervalSince1970: 0)),
        ]
        #expect(SessionListProjection.make(sessions: sessions).attentionSessions.map(\.id) == ["old", "middle", "new"])
    }

    @Test func attentionPlacesMissingTimesLast() {
        let sessions = [
            session("unknown-first", status: .awaitingUserQuestion),
            session("known", status: .running, stalled: true, since: Date(timeIntervalSince1970: 30)),
            session("unknown-second", status: .error(message: "e")),
        ]
        #expect(SessionListProjection.make(sessions: sessions).attentionSessions.map(\.id) == ["known", "unknown-first", "unknown-second"])
    }

    @Test func attentionPreservesReceivedOrderForEqualTimes() {
        let time = Date(timeIntervalSince1970: 10)
        let sessions = [
            session("z", status: .awaitingUserQuestion, since: time),
            session("a", status: .error(message: "e"), since: time),
            session("m", status: .awaitingApproval(prompt: "p"), since: time),
        ]
        #expect(SessionListProjection.make(sessions: sessions).attentionSessions.map(\.id) == ["z", "a", "m"])
    }

    @Test func otherSummaryExcludesAttentionAndCountsPromotedDescendants() throws {
        let sessions = [
            session("attention-parent", status: .awaitingUserQuestion),
            session("child", parentID: "attention-parent"),
            session("grandchild", status: .completed(exitCode: 0), parentID: "child", unread: true),
            session("attention-child", status: .error(message: "e"), parentID: "child"),
        ]
        let projection = SessionListProjection.make(sessions: sessions)
        let other = try #require(projection.otherGroup)
        #expect(other.roots.map(\.id) == ["child"])
        #expect(other.roots.first?.children.map(\.id) == ["grandchild"])
        #expect(other.collapsedSummary.entries.map(\.label) == ["実行中 1", "未読 1"])
        #expect(projection.attentionSessions.map(\.id) == ["attention-parent", "attention-child"])
    }

    @Test func unreadNameUsesPrimarySemiboldWhileOtherNamesStaySecondary() {
        let unread = SessionListRowPresentation(
            session: session("unread", status: .completed(exitCode: 0), unread: true),
            depth: 0
        )
        let running = SessionListRowPresentation(session: session("running"), depth: 1)

        #expect(unread.nameTone == .primary)
        #expect(unread.isSemibold)
        #expect(unread.statusLabel == "完了")
        #expect(unread.accessibilityLabel == "unread、完了、未読")
        #expect(running.nameTone == .secondary)
        #expect(!running.isSemibold)
        #expect(running.statusLabel == "実行中")
        #expect(running.accessibilityLabel == "running、実行中、1 段下の子セッション")
    }

    @Test func statusWordsMatchTheSharedVocabulary() {
        let cases: [(Session, String?)] = [
            (session("idle", status: .idle), nil),
            (session("starting", status: .starting), "起動中"),
            (session("running", status: .running), "実行中"),
            (session("approval", status: .awaitingApproval(prompt: "p")), "承認待ち"),
            (session("question", status: .awaitingUserQuestion), "質問あり"),
            (session("error", status: .error(message: "e")), "エラー"),
            (session("stalled", status: .running, stalled: true), "無応答"),
            (session("done", status: .completed(exitCode: 0)), "完了"),
        ]

        for (session, expectedLabel) in cases {
            #expect(SessionListRowPresentation(session: session, depth: 0).statusLabel == expectedLabel)
        }
    }

    @Test func accessibilityLabelsCoverHeadersDisclosuresAndProjectChatAction() {
        #expect(SessionListAccessibility.projectHeader(name: "Phlox", count: 4, isExpanded: true) == "Phlox、4 件、展開中")
        #expect(SessionListAccessibility.childDisclosure(name: "Parent", count: 3, isExpanded: false) == "Parent の子セッション 3 件、折りたたみ中")
        #expect(SessionListAccessibility.addSession(projectName: "Phlox") == "Phlox で新規チャット")
    }
}
