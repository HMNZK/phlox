import XCTest
@testable import PhloxCore

// E1-1 / Architecture Y（ADR 0001）検証。
//
// sibling Phlox の `AgentDomain` を SSOT として共有し、`PhloxCore` が `@_exported import` で
// 再エクスポートする構成が iOS テストターゲットから正しく解決・コンパイル・動作することを検証する。
// ここでのテストは ea13a47e（ローカルコピー A1 版）が AgentDomain に対して持っていた
// カバレッジを、Architecture Y（共有 AgentDomain）上で復元したものである。
//
// 検証対象:
//   - PhloxCore 再エクスポート経路（supportedAgentKinds）
//   - SessionStatus / HookEvent / reduce(_:applying:)（ステータス遷移の純粋関数）
//   - AgentKind / AgentRegistry / AgentCatalog（CLI レジストリ）
//   - AgentRef（builtin/custom）の Codable
//   - SessionID の Codable / 表現
//   - FlowerNameGenerator（命名生成の不変条件）
final class PhloxCoreTests: XCTestCase {

    // MARK: - PhloxCore 再エクスポート（Architecture Y の検証点）

    func testPhloxCoreReExportsSharedAgentKinds() {
        // PhloxCore 経由で共有 AgentDomain の AgentKind 全列挙へアクセスできる。
        XCTAssertFalse(PhloxCore.supportedAgentKinds.isEmpty)
        XCTAssertEqual(PhloxCore.supportedAgentKinds, AgentKind.allCases)
    }

    func testSharedAgentDomainCoreKindsPresent() {
        XCTAssertTrue(PhloxCore.supportedAgentKinds.contains(.claudeCode))
        XCTAssertTrue(PhloxCore.supportedAgentKinds.contains(.codex))
        XCTAssertTrue(PhloxCore.supportedAgentKinds.contains(.cursor))
    }

    // MARK: - SessionStatus / reduce: starting

    func testStarting_sessionStartBecomesIdle() {
        XCTAssertEqual(reduce(.starting, applying: .sessionStart), .idle)
    }

    func testStarting_notificationApprovalBecomesAwaiting() {
        let message = "Do you want to Allow this?"
        XCTAssertEqual(
            reduce(.starting, applying: .notification(message: message)),
            .awaitingApproval(prompt: message)
        )
    }

    func testStarting_notificationNonApprovalStaysStarting() {
        XCTAssertEqual(
            reduce(.starting, applying: .notification(message: "Connected to server")),
            .starting
        )
    }

    func testStarting_workEventsBecomeRunning() {
        for event in [HookEvent.preToolUse(toolName: "Shell"),
                      .postToolUse(toolName: "Read"),
                      .userPromptSubmit(turnId: nil)] {
            XCTAssertEqual(reduce(.starting, applying: event), .running, "event: \(event)")
        }
    }

    func testStarting_stopBecomesIdle() {
        XCTAssertEqual(reduce(.starting, applying: .stop(turnId: nil)), .idle)
    }

    // MARK: - SessionStatus / reduce: idle

    func testIdle_sessionStartStaysIdle() {
        XCTAssertEqual(reduce(.idle, applying: .sessionStart), .idle)
    }

    func testIdle_notificationApprovalBecomesAwaiting() {
        let message = "permission required"
        XCTAssertEqual(
            reduce(.idle, applying: .notification(message: message)),
            .awaitingApproval(prompt: message)
        )
    }

    func testIdle_notificationNonApprovalStaysIdle() {
        XCTAssertEqual(reduce(.idle, applying: .notification(message: "Ready")), .idle)
    }

    func testIdle_workEventsBecomeRunning() {
        for event in [HookEvent.preToolUse(toolName: "Grep"),
                      .postToolUse(toolName: "Write"),
                      .userPromptSubmit(turnId: nil)] {
            XCTAssertEqual(reduce(.idle, applying: event), .running, "event: \(event)")
        }
    }

    func testIdle_stopStaysIdle() {
        XCTAssertEqual(reduce(.idle, applying: .stop(turnId: nil)), .idle)
    }

    // MARK: - SessionStatus / reduce: running

    func testRunning_sessionStartBecomesIdle() {
        XCTAssertEqual(reduce(.running, applying: .sessionStart), .idle)
    }

    func testRunning_notificationApprovalBecomesAwaiting() {
        let message = "Please approve this action"
        XCTAssertEqual(
            reduce(.running, applying: .notification(message: message)),
            .awaitingApproval(prompt: message)
        )
    }

    func testRunning_notificationNonApprovalStaysRunning() {
        XCTAssertEqual(reduce(.running, applying: .notification(message: "Done")), .running)
    }

    func testRunning_workEventsStayRunning() {
        for event in [HookEvent.preToolUse(toolName: "Grep"),
                      .postToolUse(toolName: "Write"),
                      .userPromptSubmit(turnId: nil)] {
            XCTAssertEqual(reduce(.running, applying: event), .running, "event: \(event)")
        }
    }

    func testRunning_stopBecomesIdle() {
        XCTAssertEqual(reduce(.running, applying: .stop(turnId: nil)), .idle)
    }

    // MARK: - SessionStatus / reduce: ExitPlanMode（プラン承認）

    func testRunning_preToolUseExitPlanModeBecomesAwaiting() {
        XCTAssertEqual(
            reduce(.running, applying: .preToolUse(toolName: "ExitPlanMode")),
            .awaitingApproval(prompt: "Plan approval requested")
        )
    }

    func testIdle_preToolUseExitPlanModeBecomesAwaiting() {
        XCTAssertEqual(
            reduce(.idle, applying: .preToolUse(toolName: "ExitPlanMode")),
            .awaitingApproval(prompt: "Plan approval requested")
        )
    }

    func testRunning_preToolUseNonExitPlanModeStaysRunning() {
        XCTAssertEqual(reduce(.running, applying: .preToolUse(toolName: "Shell")), .running)
    }

    // MARK: - SessionStatus / reduce: awaitingApproval

    func testAwaitingApproval_sessionStartBecomesIdle() {
        XCTAssertEqual(reduce(.awaitingApproval(prompt: "Allow?"), applying: .sessionStart), .idle)
    }

    func testAwaitingApproval_userPromptSubmitBecomesRunning() {
        XCTAssertEqual(
            reduce(.awaitingApproval(prompt: "Allow?"), applying: .userPromptSubmit(turnId: nil)),
            .running
        )
    }

    func testAwaitingApproval_toolEventsBecomeRunning() {
        for event in [HookEvent.preToolUse(toolName: "Shell"),
                      .postToolUse(toolName: "Read")] {
            XCTAssertEqual(
                reduce(.awaitingApproval(prompt: "Allow?"), applying: event),
                .running,
                "event: \(event)"
            )
        }
    }

    func testAwaitingApproval_notificationApprovalUpdatesPrompt() {
        let message = "Do you want to proceed?"
        XCTAssertEqual(
            reduce(.awaitingApproval(prompt: "old"), applying: .notification(message: message)),
            .awaitingApproval(prompt: message)
        )
    }

    func testAwaitingApproval_notificationNonApprovalStaysAwaiting() {
        XCTAssertEqual(
            reduce(.awaitingApproval(prompt: "Allow?"), applying: .notification(message: "Done")),
            .awaitingApproval(prompt: "Allow?")
        )
    }

    func testAwaitingApproval_stopStaysAwaiting() {
        XCTAssertEqual(
            reduce(.awaitingApproval(prompt: "approve?"), applying: .stop(turnId: nil)),
            .awaitingApproval(prompt: "approve?")
        )
    }

    // MARK: - SessionStatus / reduce: terminal states

    func testCompleted_isTerminal() {
        for event in [HookEvent.sessionStart,
                      .notification(message: "late message"),
                      .stop(turnId: nil),
                      .preToolUse(toolName: "Shell"),
                      .userPromptSubmit(turnId: nil)] {
            XCTAssertEqual(reduce(.completed(exitCode: 0), applying: event), .completed(exitCode: 0))
        }
    }

    func testError_isTerminal() {
        let message = "something went wrong"
        for event in [HookEvent.sessionStart,
                      .notification(message: "late message"),
                      .stop(turnId: nil),
                      .postToolUse(toolName: "Read")] {
            XCTAssertEqual(reduce(.error(message: message), applying: event), .error(message: message))
        }
    }

    func testApprovalPatternsDetectedCaseInsensitive() {
        let messages = ["Please Allow access", "needs your approve", "permission denied?",
                        "Do you want to continue", "Continue? y/n",
                        "ALLOW", "APPROVE", "PERMISSION", "DO YOU WANT", "Y/N"]
        for message in messages {
            XCTAssertEqual(
                reduce(.running, applying: .notification(message: message)),
                .awaitingApproval(prompt: message),
                "message: \(message)"
            )
        }
    }

    // MARK: - AgentKind / AgentRegistry

    func testAgentKind_rawValuesAreStable() {
        // Mac wire format との語彙一致（共有 SSOT の rawValue 契約）。
        XCTAssertEqual(AgentKind.claudeCode.rawValue, "claudeCode")
        XCTAssertEqual(AgentKind.codex.rawValue, "codex")
        XCTAssertEqual(AgentKind.cursor.rawValue, "cursor")
    }

    func testAgentKind_binaryNames() {
        XCTAssertEqual(AgentKind.claudeCode.binaryName, "claude")
        XCTAssertEqual(AgentKind.codex.binaryName, "codex")
        XCTAssertEqual(AgentKind.cursor.binaryName, "cursor-agent")
    }

    func testAgentKind_displayAndSymbolNamesNonEmpty() {
        for kind in AgentKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "displayName empty for \(kind)")
            XCTAssertFalse(kind.symbolName.isEmpty, "symbolName empty for \(kind)")
        }
    }

    func testAgentKind_codableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(AgentKind.allCases)
        let decoded = try JSONDecoder().decode([AgentKind].self, from: encoded)
        XCTAssertEqual(decoded, AgentKind.allCases)
    }

    func testAgentRegistry_hasDescriptorForEveryKind() {
        XCTAssertEqual(AgentRegistry.descriptors.count, AgentKind.allCases.count)
        for kind in AgentKind.allCases {
            XCTAssertNotNil(AgentRegistry.descriptors[kind], "missing descriptor for \(kind)")
        }
    }

    func testAgentRegistry_binaryNamesMatchAccessors() {
        for kind in AgentKind.allCases {
            XCTAssertEqual(AgentRegistry.descriptor(for: kind).binaryName, kind.binaryName)
        }
    }

    func testAgentRegistry_claudeFollowsNativeSessionIDFromHook() {
        XCTAssertTrue(AgentRegistry.descriptor(for: .claudeCode).launchSpec.followsNativeSessionIDFromHook)
        XCTAssertFalse(AgentRegistry.descriptor(for: .codex).launchSpec.followsNativeSessionIDFromHook)
    }

    func testAgentRegistry_optionalBinaryKindsExcludeClaudeCode() {
        XCTAssertFalse(AgentRegistry.optionalBinaryKinds.contains(.claudeCode))
        XCTAssertTrue(AgentRegistry.optionalBinaryKinds.contains(.codex))
    }

    // MARK: - AgentRef（builtin / custom）

    func testAgentRef_builtinIdAndKind() {
        let ref = AgentRef.builtin(.codex)
        XCTAssertEqual(ref.id, "codex")
        XCTAssertEqual(ref.builtinKind, .codex)
    }

    func testAgentRef_customIdAndNilKind() {
        let ref = AgentRef.custom("myagent")
        XCTAssertEqual(ref.id, "myagent")
        XCTAssertNil(ref.builtinKind)
    }

    func testAgentRef_builtinCodableRoundTrip() throws {
        let refs: [AgentRef] = [.builtin(.claudeCode), .builtin(.cursor)]
        let decoded = try JSONDecoder().decode([AgentRef].self, from: JSONEncoder().encode(refs))
        XCTAssertEqual(decoded, refs)
    }

    func testAgentRef_customCodableRoundTrip() throws {
        let refs: [AgentRef] = [.custom("teamcli"), .builtin(.codex)]
        let decoded = try JSONDecoder().decode([AgentRef].self, from: JSONEncoder().encode(refs))
        XCTAssertEqual(decoded, refs)
    }

    // MARK: - AgentCatalog

    func testAgentCatalog_builtinsContainAllKinds() {
        let catalog = AgentCatalog.builtins
        for kind in AgentKind.allCases {
            XCTAssertNotNil(catalog.descriptor(for: .builtin(kind)), "missing builtin \(kind)")
        }
    }

    func testAgentCatalog_mergesCustomDescriptor() {
        let custom = AgentDescriptor(
            ref: .custom("teamcli"),
            displayName: "Team CLI",
            binaryName: "teamcli",
            symbolName: "terminal",
            colorRGB: AgentRGB(0x10, 0x20, 0x30),
            bypassKey: "phlox.bypass.teamcli",
            launchSpec: AgentLaunchSpec()
        )
        let catalog = AgentCatalog(customDescriptors: [custom])
        XCTAssertEqual(catalog.allDescriptors.count, AgentRegistry.allDescriptors.count + 1)
        XCTAssertNotNil(catalog.descriptor(for: .custom("teamcli")))
        XCTAssertNotNil(catalog.descriptor(for: .builtin(.claudeCode)))
    }

    func testAgentCatalog_ignoresCustomCollidingWithBuiltinID() {
        let collider = AgentDescriptor(
            ref: .custom("claudeCode"),
            displayName: "Fake",
            binaryName: "fake",
            symbolName: "terminal",
            colorRGB: AgentRGB(0, 0, 0),
            bypassKey: "phlox.bypass.fake",
            launchSpec: AgentLaunchSpec()
        )
        let catalog = AgentCatalog(customDescriptors: [collider])
        XCTAssertEqual(catalog.allDescriptors.count, AgentRegistry.allDescriptors.count)
    }

    // MARK: - SessionID

    func testSessionID_descriptionMatchesUUID() {
        let uuid = UUID()
        XCTAssertEqual(SessionID(rawValue: uuid).description, uuid.uuidString)
    }

    func testSessionID_codableRoundTrip() throws {
        let ids = [SessionID(), SessionID()]
        let decoded = try JSONDecoder().decode([SessionID].self, from: JSONEncoder().encode(ids))
        XCTAssertEqual(decoded, ids)
    }

    // MARK: - FlowerNameGenerator

    func testFlowerName_picksFirstAvailableDeterministically() {
        XCTAssertEqual(
            FlowerNameGenerator.random(avoiding: [], using: { _ in 0 }),
            FlowerNameGenerator.names[0]
        )
    }

    func testFlowerName_avoidsUsedIncludingTrimAndCase() {
        let used: Set<String> = ["  rose ", "TULIP", FlowerNameGenerator.names[2]]
        XCTAssertEqual(
            FlowerNameGenerator.random(avoiding: used, using: { _ in 0 }),
            FlowerNameGenerator.names[3]
        )
    }

    func testFlowerName_addsNumberedSuffixWhenExhausted() {
        let used = Set(FlowerNameGenerator.names)
        XCTAssertEqual(FlowerNameGenerator.random(avoiding: used, using: { _ in 0 }), "Rose 2")
    }
}
