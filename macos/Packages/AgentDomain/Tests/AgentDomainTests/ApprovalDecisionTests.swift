import Foundation
import Testing
@testable import AgentDomain

/// task-22 契約の凍結受け入れテスト。ControlServer/CodexAppServerKit で重複していた
/// `ApprovalDecision` を AgentDomain 正本へ統合する際、rawValue と JSON ワイヤ契約が
/// バイト等価で保存されることを pin する。実装者はこのファイルを編集しない。
@Suite struct ApprovalDecisionTests {
    @Test func rawValues_arePreserved() {
        #expect(ApprovalDecision.accept.rawValue == "accept")
        #expect(ApprovalDecision.decline.rawValue == "decline")
        #expect(ApprovalDecision.acceptForSession.rawValue == "acceptForSession")
        #expect(ApprovalDecision.cancel.rawValue == "cancel")
    }

    @Test func allCases_areExactlyFour() {
        #expect(Set(ApprovalDecision.allCases.map(\.rawValue))
            == ["accept", "decline", "acceptForSession", "cancel"])
    }

    @Test func codable_roundTrips_forEveryCase() throws {
        for decision in ApprovalDecision.allCases {
            let data = try JSONEncoder().encode(decision)
            let decoded = try JSONDecoder().decode(ApprovalDecision.self, from: data)
            #expect(decoded == decision)
        }
    }

    @Test func codable_wireValue_isRawString() throws {
        let data = try JSONEncoder().encode(ApprovalDecision.acceptForSession)
        #expect(String(data: data, encoding: .utf8) == "\"acceptForSession\"")
    }
}
