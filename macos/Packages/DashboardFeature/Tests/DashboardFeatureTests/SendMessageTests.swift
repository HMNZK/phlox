import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - sendMessage

@Test @MainActor
func sendMessage_deliversFormattedPayloadByRecipientName() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    let fromVM = dashboard.sessions[0]
    let toVM = dashboard.sessions[1]
    fromVM.name = "Alice"
    toVM.name = "Bob"

    let outcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "hello",
        submit: true,
        from: fromVM.id
    )

    #expect(outcome == .sent)
    #expect(ptyManager.writtenCalls.count == 2)
    let (bodyData, bodyTargetID) = ptyManager.writtenCalls[0]
    let (submitData, submitTargetID) = ptyManager.writtenCalls[1]
    #expect(bodyTargetID == toVM.id)
    #expect(submitTargetID == toVM.id)
    #expect(String(decoding: bodyData, as: UTF8.self) == "[from Alice] hello")
    #expect(String(decoding: submitData, as: UTF8.self) == "\r")
}

/// 外部送信(from: nil)では PTY へ素の text をそのまま渡し、"[from external]" 等のプレフィックスを付けない。
@Test @MainActor
func sendMessage_externalSend_deliversRawTextWithoutPrefix() async throws {
    let ptyManager = MockPTYManager()
    let messageStore = MockMessageStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream, messages: messageStore)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[0].name = "Bob"

    let outcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "hello from mobile",
        submit: true,
        from: nil
    )

    #expect(outcome == .sent)
    #expect(ptyManager.writtenCalls.count == 2)
    let (bodyData, bodyTargetID) = ptyManager.writtenCalls[0]
    #expect(bodyTargetID == dashboard.sessions[0].id)
    #expect(String(decoding: bodyData, as: UTF8.self) == "hello from mobile")
    #expect(messageStore.recorded.count == 1)
    #expect(messageStore.recorded[0].fromSession == nil)
    #expect(messageStore.recorded[0].fromName == nil)
    #expect(messageStore.recorded[0].text == "hello from mobile")
}

/// エージェント間送信(from: セッションID)では従来どおり "[from <表示名>] " プレフィックスを付ける。
@Test @MainActor
func sendMessage_agentSend_deliversPrefixedPayload() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    let fromVM = dashboard.sessions[0]
    let toVM = dashboard.sessions[1]
    fromVM.name = "Sender"
    toVM.name = "Receiver"

    let outcome = await dashboard.sendMessage(
        to: .name("Receiver"),
        text: "agent ping",
        submit: false,
        from: fromVM.id
    )

    #expect(outcome == .sent)
    #expect(ptyManager.writtenCalls.count == 1)
    let (bodyData, bodyTargetID) = ptyManager.writtenCalls[0]
    #expect(bodyTargetID == toVM.id)
    #expect(String(decoding: bodyData, as: UTF8.self) == "[from Sender] agent ping")
}

/// codex TUI はペーストバースト判定後 120ms の Enter 抑制窓を持ち、その間に届く \r は
/// 送信でなく改行扱いになる(codex-rs paste_burst.rs の PASTE_ENTER_SUPPRESS_WINDOW)。
/// submit キー遅延が 120ms を下回ると codex への送信が submit されなくなるため、
/// 既定値の下限をリグレッションガードする。
@Test @MainActor
func sendText_submitKeyDelayDefaultExceedsCodexPasteEnterSuppressWindow() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    let vm = dashboard.sessions[0]

    #expect(vm.submitKeyDelay > .milliseconds(120))
    #expect(vm.submitKeyDelay >= .milliseconds(200))
}

/// 子アプリが bracketed paste mode (CSI ?2004h) を有効化している場合、本文を
/// ESC[200~ … ESC[201~ で包んでから submit キー(\r)を送る。ペーストを明示化することで
/// codex のペーストバースト Enter 抑制窓に \r が巻き込まれず、長文でも確実に submit される
/// (ADR 0002 §8.5)。SwiftTerm が実ペーストで行うラップ手法と同一。
@Test @MainActor
func sendText_whenBracketedPasteEnabled_wrapsBodyAndSubmitsWithSeparateReturn() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    let vm = dashboard.sessions[0]
    vm.submitKeyDelay = .zero
    // 子アプリが bracketed paste mode を有効化したのと同じ CSI ?2004h を流し込む。
    vm.terminalCoordinator.feed(Data([0x1b] + Array("[?2004h".utf8)))

    try await vm.sendText("hello", submit: true)

    let writes = ptyManager.writtenCalls.map { String(decoding: $0.0, as: UTF8.self) }
    #expect(writes == ["\u{1b}[200~", "hello", "\u{1b}[201~", "\r"])
}

/// bracketed paste mode が無効な CLI には従来どおり「本文 → \r」だけを送り、ラップしない
/// (?2004h を有効化しない CLI にマーカーが素通しで表示される退行を防ぐ)。
@Test @MainActor
func sendText_whenBracketedPasteDisabled_sendsBodyThenReturnUnwrapped() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    let vm = dashboard.sessions[0]
    vm.submitKeyDelay = .zero

    try await vm.sendText("hello", submit: true)

    let writes = ptyManager.writtenCalls.map { String(decoding: $0.0, as: UTF8.self) }
    #expect(writes == ["hello", "\r"])
}

/// submit 後に処理開始が観測できなかったとき記録する診断ログ行。1 行・主要項目を含み、
/// visibleText 末尾の改行は 1 行に潰す(grep しやすくするため)。再発時の真因特定用(ADR 0002 §8.5)。
@Test
func submitDiagnostic_logLine_containsKeyFieldsAndFlattensNewlines() {
    let diag = SubmitDiagnostic(
        timestamp: "2026-06-13T12:00:00Z",
        sessionLabel: "#abc123",
        kind: .codex,
        byteCount: 528,
        bracketed: true,
        timeoutSeconds: 3.0,
        visibleTail: "› [from Alice] body\ngpt-5.5 high"
    )

    let line = diag.logLine

    #expect(line.contains("session=#abc123"))
    #expect(line.contains("kind=codex"))
    #expect(line.contains("bytes=528"))
    #expect(line.contains("bracketed=true"))
    #expect(line.contains("2026-06-13T12:00:00Z"))
    // 末尾テキストの改行は潰され、ログ行は 1 行に収まる。
    #expect(line.contains("\n") == false)
    #expect(line.contains("body"))
}

@Test @MainActor
func sendMessage_unknownRecipientName_returnsNotFound() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)

    let outcome = await dashboard.sendMessage(
        to: .name("nobody"),
        text: "hi",
        submit: false,
        from: dashboard.sessions[0].id
    )

    #expect(outcome == .notFound)
    #expect(ptyManager.writtenCalls.isEmpty)
}

@Test @MainActor
func sendMessage_duplicateRecipientName_returnsAmbiguous() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[0].name = "dup"
    dashboard.sessions[1].name = "dup"

    let outcome = await dashboard.sendMessage(
        to: .name("dup"),
        text: "hi",
        submit: false,
        from: SessionID()
    )

    if case .ambiguous(let ids) = outcome {
        #expect(Set(ids) == Set(dashboard.sessions.map(\.id)))
    } else {
        Issue.record("Expected ambiguous but got \(outcome)")
    }
    #expect(ptyManager.writtenCalls.isEmpty)
}

@Test @MainActor
func sendMessage_selfSend_returnsRejected() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[0].name = "solo"

    let outcome = await dashboard.sendMessage(
        to: .name("solo"),
        text: "hi",
        submit: false,
        from: sessionID
    )

    #expect(outcome == .rejected(reason: "self-send"))
    #expect(ptyManager.writtenCalls.isEmpty)
}

@Test @MainActor
func sendMessage_controlCharacters_returnsRejected() async throws {
    let ptyManager = MockPTYManager()
    let messageStore = MockMessageStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream, messages: messageStore)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[1].name = "Bob"

    let newlineOutcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "line\nbreak",
        submit: false,
        from: dashboard.sessions[0].id
    )
    #expect(newlineOutcome == .rejected(reason: "control-characters"))

    let escOutcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "esc\u{1B}",
        submit: false,
        from: dashboard.sessions[0].id
    )
    #expect(escOutcome == .rejected(reason: "control-characters"))
    #expect(messageStore.recorded.isEmpty)
    #expect(ptyManager.writtenCalls.isEmpty)
}

@Test @MainActor
func sendMessage_success_recordsDeliveredMessage() async throws {
    let ptyManager = MockPTYManager()
    let messageStore = MockMessageStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream, messages: messageStore)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let fromID = try await dashboard.spawnNewSession(kind: .claudeCode)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[0].name = "Alice"
    dashboard.sessions[1].name = "Bob"

    let outcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "ping",
        submit: true,
        from: fromID
    )

    #expect(outcome == .sent)
    #expect(messageStore.recorded.count == 1)
    let recorded = messageStore.recorded[0]
    #expect(recorded.fromSession == fromID)
    #expect(recorded.fromName == "Alice")
    #expect(recorded.toSession == dashboard.sessions[1].id)
    #expect(recorded.toName == "Bob")
    #expect(recorded.text == "ping")
    #expect(recorded.submit == true)
    #expect(recorded.delivered == true)
}

@Test @MainActor
func sendMessage_recipientByID_deliversToThatSession() async throws {
    let ptyManager = MockPTYManager()
    let messageStore = MockMessageStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream, messages: messageStore)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let fromID = try await dashboard.spawnNewSession(kind: .claudeCode)
    let toID = try await dashboard.spawnNewSession(kind: .claudeCode)

    let outcome = await dashboard.sendMessage(
        to: .id(toID),
        text: "direct",
        submit: false,
        from: fromID
    )

    #expect(outcome == .sent)
    #expect(ptyManager.writtenCalls.count == 1)
    let (bodyData, bodyTargetID) = ptyManager.writtenCalls[0]
    #expect(bodyTargetID == toID)
    #expect(String(decoding: bodyData, as: UTF8.self).hasSuffix("direct"))
    #expect(messageStore.recorded.count == 1)
    #expect(messageStore.recorded[0].toSession == toID)
    #expect(messageStore.recorded[0].delivered == true)
}

@Test @MainActor
func sendMessage_writeFailsWithSessionNotFound_returnsNotSpawnedAndRecordsUndelivered() async throws {
    let ptyManager = MockPTYManager()
    let messageStore = MockMessageStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream, messages: messageStore)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let fromID = try await dashboard.spawnNewSession(kind: .claudeCode)
    let toID = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[1].name = "Bob"
    ptyManager.setWriteError(.sessionNotFound)

    let outcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "are you alive?",
        submit: true,
        from: fromID
    )

    #expect(outcome == .notSpawned)
    // 配送失敗でもメッセージは delivered=false で記録される。
    #expect(messageStore.recorded.count == 1)
    let recorded = messageStore.recorded[0]
    #expect(recorded.delivered == false)
    #expect(recorded.toSession == toID)
    #expect(recorded.text == "are you alive?")
}

@Test @MainActor
func sendMessage_writeFailsWithOtherError_returnsDeliveryFailedAndRecordsUndelivered() async throws {
    let ptyManager = MockPTYManager()
    let messageStore = MockMessageStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream, messages: messageStore)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let fromID = try await dashboard.spawnNewSession(kind: .claudeCode)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[1].name = "Bob"
    ptyManager.setWriteError(.writeFailed(errno: 5))

    let outcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "important payload",
        submit: false,
        from: fromID
    )

    #expect(outcome == .deliveryFailed)
    #expect(messageStore.recorded.count == 1)
    #expect(messageStore.recorded[0].delivered == false)
}

@Test @MainActor
func sendMessage_21stMessageWithinOneSecond_returnsRateLimited() async throws {
    let ptyManager = MockPTYManager()
    let messageStore = MockMessageStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream, messages: messageStore)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let fromID = try await dashboard.spawnNewSession(kind: .claudeCode)
    _ = try await dashboard.spawnNewSession(kind: .claudeCode)
    dashboard.sessions[1].name = "Bob"

    // 1 秒 20 通の上限まで送信する（submit なし・mock 書込のため 1 秒以内に完了する）。
    for index in 0..<20 {
        let outcome = await dashboard.sendMessage(
            to: .name("Bob"),
            text: "msg-\(index)",
            submit: false,
            from: fromID
        )
        #expect(outcome == .sent)
    }

    let outcome = await dashboard.sendMessage(
        to: .name("Bob"),
        text: "msg-20",
        submit: false,
        from: fromID
    )

    #expect(outcome == .rateLimited)
    // レート制限で弾かれたメッセージは PTY 書込もメッセージ記録もされない。
    #expect(ptyManager.writtenCalls.count == 20)
    #expect(messageStore.recorded.count == 20)
}
