import XCTest
@testable import PhloxCore

// E1-3（Architecture Y スコープ）検証。
//
// PhloxCore の iOS 向け集約ドメインモデル（Session / Approval / ApprovalDecision /
// ConnectionConfig）と `needsAttention` 導出ヘルパーの構築・不変条件を検証する。
//
// 重要な前提（ADR 0001 / Architecture Y）:
//   - SessionStatus / AgentKind は sibling Phlox の共有 AgentDomain が SSOT。
//     ここでは再定義せず、PhloxCore の集約モデルとの結合のみを検証する。
//   - SessionStatus は associated value を持つリッチ enum。GET /sessions の wire format は
//     associated value を落とした flat 文字列（Mac 側 statusString）であり、その復元は E3-1 の責務。
//     本テストは wire/JSON デコードを一切行わない（純粋モデル + 導出ロジックのみ）。
final class SessionModelTests: XCTestCase {

    // MARK: - Session 構築

    func testSession_constructsWithExplicitFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .running,
            needsAttention: false,
            subtitle: "実行中 · 2分前",
            updatedAt: now
        )
        XCTAssertEqual(session.id, "s1")
        XCTAssertEqual(session.name, "Rose")
        XCTAssertEqual(session.agent, .claudeCode)
        XCTAssertEqual(session.status, .running)
        XCTAssertFalse(session.needsAttention)
        XCTAssertEqual(session.subtitle, "実行中 · 2分前")
        XCTAssertEqual(session.updatedAt, now)
    }

    func testSession_idIsIdentifiable() {
        let session = Session(
            id: "abc",
            name: "Tulip",
            agent: .codex,
            status: .idle,
            needsAttention: false,
            subtitle: "",
            updatedAt: Date()
        )
        // Identifiable の id は格納プロパティ id と一致する。
        XCTAssertEqual(session.id, "abc")
    }

    func testSession_convenienceInitDerivesNeedsAttentionFromStatus() {
        // 便宜イニシャライザは status から needsAttention を一貫導出する。
        let awaiting = Session(
            id: "s2",
            name: "Lily",
            agent: .cursor,
            status: .awaitingApproval(prompt: "ControlServer.swift を削除しますか？"),
            subtitle: "承認待ち",
            updatedAt: Date()
        )
        XCTAssertTrue(awaiting.needsAttention)

        let running = Session(
            id: "s3",
            name: "Iris",
            agent: .cursor,
            status: .running,
            subtitle: "",
            updatedAt: Date()
        )
        XCTAssertFalse(running.needsAttention)
    }

    func testSession_equatable() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Session(id: "x", name: "N", agent: .codex, status: .idle,
                        needsAttention: false, subtitle: "s", updatedAt: now)
        let b = Session(id: "x", name: "N", agent: .codex, status: .idle,
                        needsAttention: false, subtitle: "s", updatedAt: now)
        XCTAssertEqual(a, b)
    }

    // MARK: - needsAttention 導出（全 6 SessionStatus ケース）

    func testNeedsAttention_trueOnlyForAwaitingApproval() {
        XCTAssertTrue(SessionStatus.awaitingApproval(prompt: "approve?").needsAttention)
    }

    func testNeedsAttention_falseForAllNonApprovalStatuses() {
        let nonAttention: [SessionStatus] = [
            .starting,
            .idle,
            .running,
            .completed(exitCode: 0),
            .error(message: "boom"),
        ]
        for status in nonAttention {
            XCTAssertFalse(status.needsAttention, "expected false for \(status)")
        }
    }

    func testNeedsAttention_coversAllSixCases() {
        // 6 ケース（starting/idle/running/awaitingApproval/completed/error）を網羅し、
        // awaitingApproval のみ true であることを 1 箇所で固定する。
        let cases: [(SessionStatus, Bool)] = [
            (.starting, false),
            (.idle, false),
            (.running, false),
            (.awaitingApproval(prompt: "p"), true),
            (.completed(exitCode: 0), false),
            (.error(message: "e"), false),
        ]
        for (status, expected) in cases {
            XCTAssertEqual(status.needsAttention, expected, "mismatch for \(status)")
        }
    }

    func testNeedsAttention_independentOfAssociatedValues() {
        // associated value の中身に依らず awaitingApproval は常に true。
        XCTAssertTrue(SessionStatus.awaitingApproval(prompt: "").needsAttention)
        XCTAssertTrue(SessionStatus.awaitingApproval(prompt: "長いプロンプト…").needsAttention)
        // completed は exitCode に依らず false。
        XCTAssertFalse(SessionStatus.completed(exitCode: 1).needsAttention)
        XCTAssertFalse(SessionStatus.completed(exitCode: 137).needsAttention)
    }

    // MARK: - Approval 構築

    func testApproval_constructs() {
        let approval = Approval(
            id: "a1",
            sessionID: "s1",
            kind: .claudeCode,
            prompt: "ControlServer.swift を削除し続行しますか？"
        )
        XCTAssertEqual(approval.id, "a1")
        XCTAssertEqual(approval.sessionID, "s1")
        XCTAssertEqual(approval.kind, .claudeCode)
        XCTAssertEqual(approval.prompt, "ControlServer.swift を削除し続行しますか？")
    }

    func testApproval_equatable() {
        let a = Approval(id: "a", sessionID: "s", kind: .codex, prompt: "p")
        let b = Approval(id: "a", sessionID: "s", kind: .codex, prompt: "p")
        XCTAssertEqual(a, b)
    }

    // MARK: - ApprovalDecision raw 値（安定契約）

    func testApprovalDecision_rawValuesAreStable() {
        XCTAssertEqual(ApprovalDecision.accept.rawValue, "accept")
        XCTAssertEqual(ApprovalDecision.decline.rawValue, "decline")
        XCTAssertEqual(ApprovalDecision.acceptForSession.rawValue, "acceptForSession")
        XCTAssertEqual(ApprovalDecision.cancel.rawValue, "cancel")
    }

    func testApprovalDecision_hasExactlyFourCases() {
        // Codex 4 択（カンプ ⑧）。増減は wire 契約違反として検知する。
        XCTAssertEqual(ApprovalDecision.allCases.count, 4)
        XCTAssertEqual(
            Set(ApprovalDecision.allCases),
            [.accept, .decline, .acceptForSession, .cancel]
        )
    }

    func testApprovalDecision_roundTripsViaRawValue() {
        for decision in ApprovalDecision.allCases {
            XCTAssertEqual(ApprovalDecision(rawValue: decision.rawValue), decision)
        }
    }

    // MARK: - ConnectionConfig 構築（token を含まないこと）

    func testConnectionConfig_constructs() {
        let config = ConnectionConfig(host: "100.64.0.1", port: 8765)
        XCTAssertEqual(config.host, "100.64.0.1")
        XCTAssertEqual(config.port, 8765)
    }

    func testConnectionConfig_isMutable() {
        // host/port は var（設定画面で変更可能）。token は別管理（PhloxSecurity）。
        var config = ConnectionConfig(host: "a", port: 1)
        config.host = "b"
        config.port = 2
        XCTAssertEqual(config.host, "b")
        XCTAssertEqual(config.port, 2)
    }

    // MARK: - AgentKind raw 値が Mac wire と一致（ドリフト防止）

    func testAgentKind_rawValuesMatchMacWire() {
        // Mac 側 GET /sessions は `kind` を agentRef.id（builtin = AgentKind.rawValue）で送る。
        // 中核 3 種を固定し、Mac 側との語彙ドリフトを検知する。
        XCTAssertEqual(AgentKind.claudeCode.rawValue, "claudeCode")
        XCTAssertEqual(AgentKind.codex.rawValue, "codex")
        XCTAssertEqual(AgentKind.cursor.rawValue, "cursor")
    }

    func testAgentKind_decodableFromMacWireRawValue() {
        // Mac wire の生文字列から AgentKind を復元できる（E3-1 DTO の前提契約）。
        XCTAssertEqual(AgentKind(rawValue: "claudeCode"), .claudeCode)
        XCTAssertEqual(AgentKind(rawValue: "codex"), .codex)
        XCTAssertEqual(AgentKind(rawValue: "cursor"), .cursor)
    }
}
