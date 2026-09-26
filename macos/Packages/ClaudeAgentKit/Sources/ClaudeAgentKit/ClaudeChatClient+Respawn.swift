import Foundation
import StructuredChatKit

// 隠している秘密: モデル/権限変更や resume 失敗をいつ・どの引数（`--session-id`/`--resume`）で respawn するか、および ping-pong を1回に抑える上限ロジック
extension ClaudeChatClient {
    func spawn(sessionArgument: SpawnSessionArgument) async throws {
        currentTurnLatestContextTokens = nil
        if case .fork = sessionArgument {
            // fork は CLI が init で新しい ID を発行する。fork 元 ID を respawn 用状態へ残さない。
            currentSessionId = nil
            observedExistingConversation = false
        }
        partialMessageIdsByParent.removeAll()
        partialItemIdsByKey.removeAll()
        partialItemIds.removeAll()
        partialContentKeys.removeAll()
        completedSubAgentToolUseIds.removeAll()
        await expirePendingUserQuestions()
        if let transport {
            failAllPendingUsageRequests(ClaudeChatClientError.transportClosed)
            // 閉じる前に古い受信を止める（close() と同じ順）。close() は古いプロセスの終了を待つ間
            // 戻らないので、その間に古いプロセスが SIGTERM で終わると、起動し直しのための終了（143）が
            // セッションの終了として知らされてしまう。
            receiveTask?.cancel()
            receiveTask = nil
            await transport.close()
            self.transport = nil
            // reentrant actor: 上の await close() の suspension 窓で fetchRateLimits が
            // 旧 transport・旧世代のまま pending を新規登録できる。transport を nil に
            // した後にもう一度 fail して取りこぼしを防ぐ（stage2 レビュー MUST）。
            failAllPendingUsageRequests(ClaudeChatClientError.transportClosed)
            await expirePendingUserQuestions()
        }

        let arguments = buildArguments(sessionArgument: sessionArgument)
        let nextTransport = transportFactory(command, arguments, environment, workingDirectory)
        try nextTransport.start()
        transport = nextTransport
        activeSpawnArgument = sessionArgument
        spawnGeneration += 1
        interruptedResultSuppression = nil
        let generation = spawnGeneration
        switch sessionArgument {
        case .none:
            break
        case .sessionId(let sessionId), .resume(let sessionId):
            currentSessionId = sessionId
        case .fork:
            break
        }

        let lines = nextTransport.receivedLines
        receiveTask = Task { [weak self] in
            for await line in lines {
                await self?.handleLine(line, generation: generation)
            }
            await self?.handleStreamEnded(generation: generation)
        }
    }

    func handleStreamEnded(generation: Int) async {
        // A respawn (settings apply / resume) closes the previous transport,
        // whose receive loop then ends. Ignore that stale signal so it cannot
        // clobber the freshly spawned transport.
        // 起動し直しや close() が受信を止めたとき（タスクがキャンセル済み）も、終了として扱わない。
        guard !Task.isCancelled, generation == spawnGeneration else { return }
        // CLI プロセス終了後は stdin へ deny を送っても届かず、死因エラーにノイズを足すだけなので送信しない。
        await expirePendingUserQuestions(generation: generation, sendDeny: false)
        failAllPendingUsageRequests(ClaudeChatClientError.transportClosed)
        let endedTransport = transport

        if let pendingResultError {
            let stderrTail = await endedTransport?.stderrTail()
            guard generation == spawnGeneration else { return }
            if let healArgument = selfHealArgument(
                pendingResultError: pendingResultError,
                stderrTail: stderrTail
            ), canSelfHealCurrentTurn() {
                let replayLine = currentTurnLine
                let shouldReplayTurn = replayLine != nil
                self.pendingResultError = nil
                transport = nil
                receiveTask = nil
                recordSelfHealAttemptIfTurnBound()
                do {
                    try await spawn(sessionArgument: healArgument)
                    if let replayLine {
                        try await transport?.send(replayLine)
                    } else {
                        currentTurnOpen = false
                        currentTurnLine = nil
                    }
                } catch {
                    currentTurnOpen = false
                    currentTurnLine = nil
                    eventContinuation.yield(.error(message: "Failed to self-heal Claude session: \(error)"))
                    // 修復用のプロセスも起動できなかったときだけ、元のプロセスの終了として知らせる
                    // （起動できて再送だけ失敗したなら、新しいプロセスが動いている）。
                    if transport == nil {
                        await yieldProcessExited(endedTransport, generation: generation)
                    }
                }
                if !shouldReplayTurn {
                    currentTurnOpen = false
                    currentTurnLine = nil
                }
                return
            }

            self.pendingResultError = nil
            transport = nil
            receiveTask = nil
            currentTurnOpen = false
            currentTurnLine = nil
            eventContinuation.yield(.error(message: pendingResultError.message))
            await yieldProcessExited(endedTransport, generation: generation)
            return
        }

        if currentTurnOpen {
            let stderrTail = await endedTransport?.stderrTail()
            guard generation == spawnGeneration else { return }
            if let healArgument = selfHealArgumentForResultlessDeath(stderrTail: stderrTail),
               canSelfHealCurrentTurn() {
                let replayLine = currentTurnLine
                transport = nil
                receiveTask = nil
                recordSelfHealAttemptIfTurnBound()
                do {
                    try await spawn(sessionArgument: healArgument)
                    if let replayLine {
                        try await transport?.send(replayLine)
                    }
                } catch {
                    currentTurnOpen = false
                    currentTurnLine = nil
                    eventContinuation.yield(.error(message: "Failed to self-heal Claude session: \(error)"))
                    // 修復用のプロセスも起動できなかったときだけ、元のプロセスの終了として知らせる
                    // （起動できて再送だけ失敗したなら、新しいプロセスが動いている）。
                    if transport == nil {
                        await yieldProcessExited(endedTransport, generation: generation)
                    }
                }
                return
            }
            transport = nil
            receiveTask = nil
            currentTurnOpen = false
            currentTurnLine = nil
            eventContinuation.yield(.error(message: processEndedMessage(stderrTail: stderrTail)))
            await yieldProcessExited(endedTransport, generation: generation)
            return
        }

        transport = nil
        receiveTask = nil
        await yieldProcessExited(endedTransport, generation: generation)
    }

    /// プロセスが自分で終わったことを終了コードつきで知らせる（04 B3）。
    /// close() が受信を打ち切った（タスクがキャンセル済み）ときと、中断で止めたときは知らせない。
    /// 終了コードを待つ間に次の送信が新しいプロセスを起動していたら、古いプロセスの終了は知らせない。
    private func yieldProcessExited(_ endedTransport: (any LineDelimitedTransport)?, generation: Int) async {
        guard !Task.isCancelled, interruptEndedGeneration != generation else { return }
        let exitCode = await endedTransport?.terminationStatus()
        guard !Task.isCancelled, interruptEndedGeneration != generation, spawnGeneration == generation else { return }
        eventContinuation.yield(.processExited(exitCode: exitCode))
    }

    func buildArguments(sessionArgument: SpawnSessionArgument) -> [String] {
        var arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-prompt-tool", "stdio",
            "--forward-subagent-text",
        ]
        if includePartialMessages {
            arguments.append("--include-partial-messages")
        }
        if let currentModel {
            arguments.append(contentsOf: ["--model", currentModel])
        }
        if let currentPermissionMode {
            arguments.append(contentsOf: ["--permission-mode", currentPermissionMode])
        }
        if let currentEffort {
            arguments.append(contentsOf: ["--effort", currentEffort])
        }
        if !allowedTools.isEmpty {
            arguments.append(contentsOf: ["--allowedTools", allowedTools.joined(separator: ",")])
        }
        if let settingSources {
            arguments.append(contentsOf: ["--setting-sources", settingSources])
        }
        if let agents {
            arguments.append(contentsOf: ["--agents", agents])
        }
        switch sessionArgument {
        case .none:
            break
        case .sessionId(let sessionId):
            arguments.append(contentsOf: ["--session-id", sessionId])
        case .resume(let resumeSessionId):
            arguments.append(contentsOf: ["--resume", resumeSessionId])
        case .fork(let resumeSessionId):
            arguments.append(contentsOf: ["--resume", resumeSessionId, "--fork-session"])
        }
        return arguments
    }

    func initialSessionArgument() -> SpawnSessionArgument {
        if let phloxSessionID {
            return .sessionId(phloxSessionID)
        }
        return .none
    }

    func settingsRespawnSessionArgument() -> SpawnSessionArgument {
        if case .fork = activeSpawnArgument, currentSessionId == nil {
            // system.init 前は fork 元も新しい session ID も使わず、新規 spawn にする。
            return .none
        }
        if observedExistingConversation || callerResumedSession, let currentSessionId {
            return .resume(currentSessionId)
        }
        return initialSessionArgument()
    }

    func shouldDeferResultError(_ event: [String: Any]) -> Bool {
        guard event["subtype"] as? String == "error_during_execution" else { return false }
        guard activeResumeSessionId() != nil else { return false }
        return true
    }

    func activeResumeSessionId() -> String? {
        if case .resume(let sessionId) = activeSpawnArgument {
            return sessionId
        }
        return nil
    }

    func selfHealArgument(
        pendingResultError: PendingResultError,
        stderrTail: String?
    ) -> SpawnSessionArgument? {
        guard let resumeSessionId = pendingResultError.resumeSessionId else { return nil }
        guard let stderrTail, stderrTail.contains("No conversation found with session ID") else {
            return nil
        }
        return .sessionId(resumeSessionId)
    }

    func selfHealArgumentForResultlessDeath(stderrTail: String?) -> SpawnSessionArgument? {
        guard case .sessionId(let sessionId) = activeSpawnArgument else { return nil }
        guard let stderrTail, stderrTail.contains("is already in use") else { return nil }
        return .resume(sessionId)
    }

    func canSelfHealCurrentTurn() -> Bool {
        guard currentTurnLine != nil else { return true }
        return currentTurnHealCount == 0
    }

    func recordSelfHealAttemptIfTurnBound() {
        if currentTurnLine != nil {
            currentTurnHealCount += 1
        }
    }

    func recordConversationEvidenceFromResult(_ event: [String: Any]) {
        if case .sessionId = activeSpawnArgument {
            observedExistingConversation = true
            return
        }
        if event["subtype"] as? String == "success" {
            observedExistingConversation = true
        }
    }

    func shouldAbsorbInterruptedResultError(_ event: [String: Any], generation: Int) -> Bool {
        guard event["subtype"] as? String == "error_during_execution" else { return false }
        guard let interruptedResultSuppression else { return false }
        return interruptedResultSuppression.generation == generation
    }

    func yieldPendingResultErrorIfNeeded() {
        guard let pendingResultError else { return }
        self.pendingResultError = nil
        eventContinuation.yield(.error(message: pendingResultError.message))
    }
}
