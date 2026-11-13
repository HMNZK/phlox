import Foundation
import StructuredChatKit

/// 計画的なホスト更新（ADR 0233）で新ホストへ渡す、クライアントの状態。
/// 受信済みの行を再生して状態を作り直すのでなく、必要な状態を明示的に運ぶ。
/// 運ばないもの: 途中のファイル変更の差分（partialFileChangesByKey・pendingFileChangesByToolUseId）。
/// 該当するツール実行がちょうど更新をまたぐ場合、その1件の差分表示が欠ける（会話ログの本文は保存済み）。
struct ClaudeHandoverState: Codable {
    var currentSessionId: String?
    var spawnKind: String
    var spawnValue: String?
    var callerResumedSession: Bool
    var observedExistingConversation: Bool
    var currentModel: String?
    var currentPermissionMode: String?
    var currentEffort: String?
    var settingsDirty: Bool
    var currentTurnOpen: Bool
    var currentTurnLine: Data?
    var currentTurnLatestContextTokens: Int?
    var currentTurnHealCount: Int
    var generatedItemCounter: Int
    var toolUseItemIds: [String: String]
    var taskListToolUseIds: [String]
    var taskListTasks: [AgentTaskItem]
    var pendingCreatedTaskTitles: [String: String]
    var subAgentToolUseIds: [String]
    var backgroundSubAgentToolUseIds: [String]
    var emittedSubAgentStarts: [String: Int]
    var subAgentTaskIDs: [String: String]
    var stoppedSubAgentToolUseIds: [String]
    var completedSubAgentToolUseIds: [String]
    var nextStopTaskRequestID: Int
    var partialMessageIdsByParent: [String: String]
    var partialItemIdsByKey: [String: String]
    var partialItemIds: [String]
    var partialContentKeys: [String]
    /// 未回答の承認・質問の原文（request_id → 行）。
    var pendingControlRequests: [String: Data]
}

extension ClaudeChatClient {
    func recordControlRequestLine(_ event: [String: Any], line: Data) {
        guard event["type"] as? String == "control_request",
              let requestId = event["request_id"] as? String,
              (event["request"] as? [String: Any])?["subtype"] as? String == "can_use_tool" else { return }
        controlRequestLines[requestId] = line
        // 回答済みの原文を溜め続けない。
        if controlRequestLines.count > 64 {
            controlRequestLines = controlRequestLines.filter { pendingUserQuestions[$0.key] != nil || $0.key == requestId }
        }
    }

    func makeHandoverState() -> ClaudeHandoverState {
        let kind: String
        let value: String?
        switch activeSpawnArgument {
        case .none: (kind, value) = ("none", nil)
        case .sessionId(let id): (kind, value) = ("sessionId", id)
        case .resume(let id): (kind, value) = ("resume", id)
        case .fork(let id): (kind, value) = ("fork", id)
        }
        return ClaudeHandoverState(
            currentSessionId: currentSessionId, spawnKind: kind, spawnValue: value,
            callerResumedSession: callerResumedSession, observedExistingConversation: observedExistingConversation,
            currentModel: currentModel, currentPermissionMode: currentPermissionMode, currentEffort: currentEffort,
            settingsDirty: settingsDirty, currentTurnOpen: currentTurnOpen, currentTurnLine: currentTurnLine,
            currentTurnLatestContextTokens: currentTurnLatestContextTokens, currentTurnHealCount: currentTurnHealCount,
            generatedItemCounter: generatedItemCounter, toolUseItemIds: toolUseItemIds,
            taskListToolUseIds: Array(taskListToolUseIds), taskListTasks: taskListTasks,
            pendingCreatedTaskTitles: pendingCreatedTaskTitles, subAgentToolUseIds: Array(subAgentToolUseIds),
            backgroundSubAgentToolUseIds: Array(backgroundSubAgentToolUseIds),
            emittedSubAgentStarts: emittedSubAgentStarts.mapValues(\.rawValue), subAgentTaskIDs: subAgentTaskIDs,
            stoppedSubAgentToolUseIds: Array(stoppedSubAgentToolUseIds),
            completedSubAgentToolUseIds: Array(completedSubAgentToolUseIds), nextStopTaskRequestID: nextStopTaskRequestID,
            partialMessageIdsByParent: partialMessageIdsByParent, partialItemIdsByKey: partialItemIdsByKey,
            partialItemIds: Array(partialItemIds), partialContentKeys: Array(partialContentKeys),
            pendingControlRequests: controlRequestLines.filter { pendingUserQuestions[$0.key] != nil })
    }

    func applyHandoverState(_ state: ClaudeHandoverState) {
        currentSessionId = state.currentSessionId
        switch state.spawnKind {
        case "sessionId": activeSpawnArgument = .sessionId(state.spawnValue ?? "")
        case "resume": activeSpawnArgument = .resume(state.spawnValue ?? "")
        case "fork": activeSpawnArgument = .fork(state.spawnValue ?? "")
        default: activeSpawnArgument = .none
        }
        callerResumedSession = state.callerResumedSession
        observedExistingConversation = state.observedExistingConversation
        currentModel = state.currentModel
        currentPermissionMode = state.currentPermissionMode
        currentEffort = state.currentEffort
        settingsDirty = state.settingsDirty
        currentTurnOpen = state.currentTurnOpen
        currentTurnLine = state.currentTurnLine
        currentTurnLatestContextTokens = state.currentTurnLatestContextTokens
        currentTurnHealCount = state.currentTurnHealCount
        generatedItemCounter = state.generatedItemCounter
        toolUseItemIds = state.toolUseItemIds
        taskListToolUseIds = Set(state.taskListToolUseIds)
        taskListTasks = state.taskListTasks
        pendingCreatedTaskTitles = state.pendingCreatedTaskTitles
        subAgentToolUseIds = Set(state.subAgentToolUseIds)
        backgroundSubAgentToolUseIds = Set(state.backgroundSubAgentToolUseIds)
        emittedSubAgentStarts = state.emittedSubAgentStarts.compactMapValues { DescriptionSource(rawValue: $0) }
        subAgentTaskIDs = state.subAgentTaskIDs
        stoppedSubAgentToolUseIds = Set(state.stoppedSubAgentToolUseIds)
        completedSubAgentToolUseIds = Set(state.completedSubAgentToolUseIds)
        nextStopTaskRequestID = state.nextStopTaskRequestID
        partialMessageIdsByParent = state.partialMessageIdsByParent
        partialItemIdsByKey = state.partialItemIdsByKey
        partialItemIds = Set(state.partialItemIds)
        partialContentKeys = Set(state.partialContentKeys)
    }

    /// 引き継ぎ側: 新しい子を作らず、旧ホストの子（holder）へ接続して続きから受け取る準備をする。
    public func prepareAdoption(state: Data, transport: HolderTransport) {
        pendingAdoption = (state, transport)
        spawnForbiddenReason = "引き継ぎが完了していないため、新しい子は起動しません（元の子は終了していません）"
    }
}

extension ClaudeChatClient: HandoverCapableClient {
    public func handoverGateReason() async -> String? {
        guard let holder = transport as? HolderTransport, holder.holderRecord != nil else {
            return "Claudeの子がholder経由ではありません"
        }
        if let reason = holder.endedReason { return "holderとの接続が切れています(\(reason))" }
        if holder.hasUnknownSend { return "結果不明の送信があります" }
        if pendingPermissionRequest != nil || !pendingUsageRequests.isEmpty || !pendingStopTaskRequests.isEmpty {
            return "応答待ちの操作があります"
        }
        if interruptingControlGeneration != nil || interruptExitPendingGeneration != nil || pendingResultError != nil {
            return "中断・終了の処理中です"
        }
        if pendingUserQuestions.values.contains(where: \.isResponding) || !expiringUserQuestionIDs.isEmpty {
            return "承認・質問への回答を処理中です"
        }
        return nil
    }

    /// 中断などでCLIが終わり、`transport`が無い。起動済みで、`spawn`も禁止されていない（採用の途中・手放し後ではない）。
    /// 引き継ぐ実行が無いので対象外にし、新ホストが通常の復元で戻す。
    public func handoverParticipation() async -> HandoverParticipation {
        if transport == nil, spawnGeneration > 0, spawnForbiddenReason == nil { return .childEnded }
        return .participant
    }

    public func prepareHandover(fence: UUID) async throws -> HandoverPreparation {
        guard let holder = transport as? HolderTransport, let record = holder.holderRecord else {
            throw HandoverError.notReady("Claudeの子がholder経由ではありません")
        }
        if let reason = await handoverGateReason() { throw HandoverError.notReady(reason) }
        // 受信側（receiveTask）が最後の行を処理し終えるまで待つ。待つ間にこのactorへ再入するので、完了後に再確認する。
        guard let applied = await holder.quiesce() else { throw HandoverError.timedOut }
        if let reason = await handoverGateReason() {
            holder.resumeAfterQuiesce()
            throw HandoverError.notReady(reason)
        }
        // ここから先は中断なし（状態の採取とフェンスの送出の間に他の処理を挟まない）。
        let state: Data
        do { state = try JSONEncoder().encode(makeHandoverState()) } catch {
            holder.resumeAfterQuiesce()
            throw HandoverError.notReady("状態を保存できません: \(error)")
        }
        eventContinuation.yield(.handoverFence(fence))
        return HandoverPreparation(holder: record, appliedSeq: applied, clientState: state, fence: fence)
    }

    public func cancelHandover() async {
        (transport as? HolderTransport)?.resumeAfterQuiesce()
    }

    public func commitHandover(confirmedThrough: UInt64) async {
        guard let holder = transport as? HolderTransport else { return }
        receiveTask?.cancel()
        receiveTask = nil
        holder.confirm(through: confirmedThrough)
        holder.releaseForHandover()
        // 以後この画面状態から子へは書かない。送信で起動し直さない（子は新ホストが引き継ぐ）。
        transport = nil
        exitReportedGeneration = spawnGeneration
        spawnForbiddenReason = "実行は新しいホストへ引き継ぎ済みのため、新しい子は起動しません"
    }

    public func completeAdoption() async throws {
        // 失敗した採用は、新しい子を起動しない（成功の最後まで`spawn`を禁止したままにする）。
        spawnForbiddenReason = "引き継ぎに失敗したため、新しい子は起動しません（元の子は終了していません）"
        guard let adoption = pendingAdoption else { throw HandoverError.adoptionFailed("引き継ぎの準備がありません") }
        pendingAdoption = nil
        let state: ClaudeHandoverState
        do { state = try JSONDecoder().decode(ClaudeHandoverState.self, from: adoption.state) } catch {
            throw HandoverError.adoptionFailed("クライアント状態を読めません: \(error)")
        }
        // 書込権を取って接続する。失敗しても子には何もしない（終了・再生成しない）。
        do { try adoption.transport.start() } catch {
            throw HandoverError.adoptionFailed("holderへ接続できません: \(error)")
        }
        // 反映済みの番号より後の行が欠けていないか。欠けていれば確認（confirm）を送らず、手放すだけにする。
        if let fault = adoption.transport.adoptionContinuityFault() {
            adoption.transport.releaseForHandover()
            throw HandoverError.adoptionFailed(fault)
        }
        guard adoption.transport.unknownSendIDs.isEmpty else {
            adoption.transport.releaseForHandover()
            throw HandoverError.adoptionFailed("旧ホストの結果不明の送信があります。再送しません")
        }
        applyHandoverState(state)
        transport = adoption.transport
        spawnGeneration += 1
        let generation = spawnGeneration
        interruptedResultSuppression = nil
        adoption.transport.setOwnershipLossHandler { [weak self] reason in
            Task { await self?.handleOwnershipLoss(reason, generation: generation) }
        }
        if state.currentTurnOpen { eventContinuation.yield(.turnStarted) }
        // 未回答の承認・質問は、原文を通常の受信経路へ再投入して作り直す（応答は新ホストが一度だけ返す）。
        for (requestId, line) in state.pendingControlRequests.sorted(by: { $0.key < $1.key }) {
            controlRequestLines[requestId] = line
            await handleLine(line, generation: generation)
        }
        let lines = adoption.transport.receivedLines
        receiveTask = Task { [weak self] in
            for await line in lines {
                await self?.handleLine(line, generation: generation)
            }
            await self?.handleStreamEnded(generation: generation)
        }
        // 採用が成功した。以後の通常の再起動（設定変更の反映など）は、この接続の子に対して従来どおり行う。
        spawnForbiddenReason = nil
    }

    /// 他のホストに書込権を取られた、またはholderとの接続が切れた。子は終了していないので、起動し直さず復旧待ちにする。
    func handleOwnershipLoss(_ reason: HolderTransport.EndReason, generation: Int) {
        guard generation == spawnGeneration else { return }
        exitReportedGeneration = generation
        spawnForbiddenReason = "実行の所有権を失ったため、新しい子は起動しません（元の子は終了していません）"
        eventContinuation.yield(.error(message: "実行の所有権を失いました(\(reason))。子のプロセスは終了していません。復旧を待っています。"))
    }
}

/// 回答の返送が確定したときだけtrueを返す（引き継ぎ準備中の拒否を「回答済み」にしない）。
extension ClaudeChatClient: UserQuestionAnswerAcknowledging {}
