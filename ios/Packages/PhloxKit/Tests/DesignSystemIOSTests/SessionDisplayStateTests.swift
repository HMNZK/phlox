import XCTest
import SwiftUI
import AgentDomain
import DesignSystem
import PhloxCore
@testable import DesignSystemIOS

final class SessionDisplayStateTests: XCTestCase {
    func testSessionUsesSharedDisplayStateRules() {
        let runningAndStalled = makeSession(status: .running, isStalled: true)
        let idleAndUnseen = makeSession(status: .idle, hasUnseenCompletion: true)
        let approvalAndStalled = makeSession(status: .awaitingApproval(prompt: "p"), isStalled: true)

        XCTAssertEqual(runningAndStalled.displayState, .stalled)
        XCTAssertEqual(idleAndUnseen.displayState, .doneUnread)
        XCTAssertEqual(approvalAndStalled.displayState, .approval)
        XCTAssertTrue(makeSession(backend: "pty").isPTY)
        XCTAssertFalse(makeSession(backend: "appServer").isPTY)
    }

    func testVocabularyMapsAllNineSharedStates() {
        let locale = Locale(identifier: "ja_JP")
        let cases: [(SessionDisplayState, String?, Color?, IOSStatusWeight?)] = [
            (.idle, nil, nil, nil),
            (.starting, "起動中", IOSColor.text.tertiary, .regular),
            (.running, "実行中", IOSColor.text.secondary, .medium),
            (.approval, "承認待ち", IOSColor.status.approval, .semibold),
            (.question, "質問あり", IOSColor.status.question, .semibold),
            (.error, "エラー", IOSColor.status.error, .semibold),
            (.stalled, "無応答", IOSColor.status.stalled, .semibold),
            (.doneUnread, "完了", IOSColor.text.tertiary, .regular),
            (.done, "完了", IOSColor.text.tertiary, .regular),
        ]

        for (state, label, color, weight) in cases {
            let presentation = IOSStatusVocabulary.presentation(for: state, locale: locale)
            XCTAssertEqual(presentation.label, label, "\(state)")
            XCTAssertEqual(presentation.color, color, "\(state)")
            XCTAssertEqual(presentation.weight, weight, "\(state)")
        }
    }

    private func makeSession(
        status: SessionStatus = .running,
        backend: String = "appServer",
        isStalled: Bool = false,
        hasUnseenCompletion: Bool = false
    ) -> Session {
        Session(
            id: UUID().uuidString,
            name: "session",
            agent: .claudeCode,
            status: status,
            backend: backend,
            isStalled: isStalled,
            hasUnseenCompletion: hasUnseenCompletion,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
