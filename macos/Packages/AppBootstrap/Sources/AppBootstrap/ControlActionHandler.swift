import Foundation
import OSLog
import AgentDomain
import ControlServer
import DashboardFeature
import SessionFeature
import StructuredChatKit

/// Control API のセッション一覧で返す 1 セッション分の概要。
public struct ControlSessionSummary: Sendable {
    public let id: SessionID
    public let name: String
    public let agentID: String
    public let status: SessionStatus
    public let workspaceName: String
    public let projectID: String?
    public let projectName: String?

    public init(
        id: SessionID,
        name: String,
        agentID: String,
        status: SessionStatus,
        workspaceName: String,
        projectID: String? = nil,
        projectName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.agentID = agentID
        self.status = status
        self.workspaceName = workspaceName
        self.projectID = projectID
        self.projectName = projectName
    }
}

/// ControlActionHandler が必要とするダッシュボード操作の最小インターフェース。
/// 本体は DashboardViewModel が適合する（適合は App 側）。テストではモックを注入する。
@MainActor
public protocol ControlActionDashboard: AnyObject {
    var controlSessionSummaries: [ControlSessionSummary] { get }
    func sendMessage(
        to recipient: Recipient,
        text: String,
        submit: Bool,
        from: SessionID?,
        inReplyTo: UUID?,
        images: [ControlImageAttachment]
    ) async -> DashboardViewModel.SendOutcome
    func spawnSession(
        ref: AgentRef,
        from: SessionID?,
        backend: SessionBackend,
        workingDirectory: String?
    ) async throws -> SessionID
    func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool
    func removeSession(_ id: SessionID) async -> Bool
    func renameSession(_ id: SessionID, to name: String)
    func persistSessionRole(id: SessionID, role: String)
    /// spawn の着地通知。アゴラ討論が進行中で、role 付き spawn または討論参加者
    /// （ファシリテーター等）からの spawn なら討論参加者として登録する
    /// （witness は DashboardViewModel。討論外の spawn では何もしない）。
    func agoraParticipantLanded(id: SessionID, role: String?, requester: SessionID?)
    func sessionOutput(for id: SessionID) -> String?
    /// 構造化（appServer）セッションの差分/全量 transcript を返す（契約6）。非構造化/不在は nil（→404）。
    /// `since == nil` は全量（isSnapshot=false）＋cursor。`since` 有効かつ append のみは差分、
    /// 編集/置換・不正/期限切れ cursor は全量（isSnapshot=true）。long-poll の待機はハンドラ層が行う
    /// （このメソッド自体は現時点のスナップショットを即時に返す純参照）。
    func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta?
    func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult
    func waitUntilDone(
        for id: SessionID,
        timeout: Duration,
        sentinel: String?
    ) async -> DashboardViewModel.DoneResult

    // MARK: - 承認 witness（MC-3b が App 層で実体を注入する）
    /// 現在保留中の承認一覧を返す。witness 未注入時は空配列を返す既定で十分。
    func listApprovals() async -> [ApprovalDTO]
    /// id の承認に decision を応答する。成功（id が存在）なら true、未知 id なら false を返す。
    func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool

    func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome
    func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]?
    func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]?
    func sessionUsage(for id: SessionID) -> ControlSessionUsage?
    func sessionModelSettings(for id: SessionID) -> ControlSessionModelSettings?
    func setSessionModel(_ model: String, for id: SessionID) async -> Bool
    var controlCLIUsages: [AgentKind: CLIUsage] { get }
}

extension ControlActionDashboard {
    public func persistSessionRole(id: SessionID, role: String) {}
    public func agoraParticipantLanded(id: SessionID, role: String?, requester: SessionID?) {}
    public func sessionModelSettings(for id: SessionID) -> ControlSessionModelSettings? { nil }
    public func setSessionModel(_ model: String, for id: SessionID) async -> Bool { false }
    public var controlCLIUsages: [AgentKind: CLIUsage] { [:] }
}

@MainActor
public final class ControlActionHandler {
    private static let logger = Logger(subsystem: "com.phlox.Phlox", category: "ControlActionHandler")
    public weak var dashboard: (any ControlActionDashboard)?

    private let deviceTokenStore: (any DeviceTokenStore)?

    public init(deviceTokenStore: (any DeviceTokenStore)? = nil) {
        self.deviceTokenStore = deviceTokenStore
    }

    public func handle(_ request: ControlRequest) async -> ControlResponse {
        switch request.action {
        case let .registerDeviceToken(registration):
            return handleRegisterDeviceToken(registration)
        default:
            break
        }

        guard let dashboard else { return .status(503) }
        switch request.action {
        case .listSessions:
            return handleListSessions(dashboard)
        case let .sendText(to, text, submit, inReplyTo, images):
            return await handleSendText(
                dashboard,
                to: to,
                text: text,
                submit: submit,
                requester: request.requester,
                inReplyTo: inReplyTo,
                images: images
            )
        case let .spawn(ref, backend, workingDirectory):
            return await handleSpawn(
                dashboard,
                ref: ref,
                requester: request.requester,
                backend: backend,
                workingDirectory: workingDirectory,
                model: ControlSpawnContext.model
            )
        case let .remove(id):
            return await handleRemove(dashboard, id: id, requester: request.requester)
        case let .rename(id, name):
            return handleRename(dashboard, id: id, name: name, requester: request.requester)
        case let .output(id, mode):
            return handleOutput(dashboard, id: id, mode: mode)
        case let .messages(id, since, wait):
            return await handleMessagesDelta(dashboard, id: id, since: since, wait: wait)
        case let .waitReady(id, timeoutSeconds):
            return await handleWaitReady(dashboard, id: id, timeoutSeconds: timeoutSeconds)
        case let .wait(id, timeoutSeconds, sentinel):
            return await handleWait(
                dashboard,
                id: id,
                timeoutSeconds: timeoutSeconds,
                sentinel: sentinel
            )
        case .listApprovals:
            return await handleListApprovals(dashboard)
        case let .respondApproval(id, decision):
            return await handleRespondApproval(dashboard, id: id, decision: decision)
        case let .interrupt(id):
            return await handleInterrupt(dashboard, id: id)
        case let .subAgents(id):
            return handleSubAgents(dashboard, id: id)
        case let .subAgentMessages(id, subAgentID):
            return handleSubAgentMessages(dashboard, id: id, subAgentID: subAgentID)
        case let .usage(id):
            return handleUsage(dashboard, id: id)
        case let .sessionSettings(id):
            return handleSessionSettings(dashboard, id: id)
        case let .setModel(id, model):
            return await handleSetModel(dashboard, id: id, model: model)
        case let .agentModels(kind):
            return handleAgentModels(kind: kind)
        case .cliUsage:
            return handleCLIUsage(dashboard)
        case .registerDeviceToken:
            fatalError("registerDeviceToken is handled before dashboard guard")
        }
    }

    // MARK: - Action handlers (Extract Method)

    private func handleRegisterDeviceToken(_ registration: DeviceTokenRegistration) -> ControlResponse {
        guard let deviceTokenStore else {
            return .status(503)
        }
        do {
            try deviceTokenStore.upsert(registration)
            return .json(200, OkDTO(ok: true))
        } catch {
            return .status(500)
        }
    }

    private func handleListSessions(_ dashboard: any ControlActionDashboard) -> ControlResponse {
        let items = dashboard.controlSessionSummaries.map { s in
            ControlSessionListItem(
                id: s.id.rawValue.uuidString,
                name: s.name,
                kind: s.agentID,
                status: Self.statusString(s.status),
                workspace: s.workspaceName,
                projectId: s.projectID,
                projectName: s.projectName
            )
        }
        return .json(200, ControlSessionListResponse(sessions: items))
    }

    private func handleSessionSettings(
        _ dashboard: any ControlActionDashboard,
        id: SessionID
    ) -> ControlResponse {
        if let settings = dashboard.sessionModelSettings(for: id) {
            return .json(200, settings)
        }
        guard dashboard.controlSessionSummaries.contains(where: { $0.id == id }) else {
            return .status(404)
        }
        return .json(
            200,
            ControlSessionModelSettings(selectedModel: nil, availableModels: [])
        )
    }

    private func handleSetModel(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        model: String
    ) async -> ControlResponse {
        await dashboard.setSessionModel(model, for: id) ? .status(200) : .status(404)
    }

    private func handleAgentModels(kind: AgentKind) -> ControlResponse {
        .json(200, ControlAgentModelsResponse(
            models: AgentModelCatalog.models(for: kind),
            defaultModel: AgentModelCatalog.defaultModel(for: kind)
        ))
    }

    private func handleCLIUsage(_ dashboard: any ControlActionDashboard) -> ControlResponse {
        let formatter = ISO8601DateFormatter()
        let agents = dashboard.controlCLIUsages.values
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
            .map { usage -> ControlCLIUsageAgent in
                switch usage.state {
                case let .ok(buckets):
                    return ControlCLIUsageAgent(
                        kind: usage.kind.rawValue,
                        state: "ok",
                        updatedAt: formatter.string(from: usage.updatedAt),
                        dataAsOf: usage.dataAsOf.map(formatter.string(from:)),
                        buckets: buckets.map { bucket in
                            ControlCLIUsageBucket(
                                id: bucket.id,
                                label: bucket.label,
                                usedPercent: bucket.usedPercent,
                                resetsAt: bucket.resetsAt.map(formatter.string(from:))
                            )
                        }
                    )
                case .unavailable:
                    return ControlCLIUsageAgent(
                        kind: usage.kind.rawValue,
                        state: "unavailable",
                        updatedAt: nil,
                        dataAsOf: nil,
                        buckets: []
                    )
                }
            }
        return .json(200, ControlCLIUsageResponse(agents: agents))
    }

    private func handleSendText(
        _ dashboard: any ControlActionDashboard,
        to: Recipient,
        text: String,
        submit: Bool,
        requester: SessionID?,
        inReplyTo: UUID?,
        images: [ControlImageAttachment]
    ) async -> ControlResponse {
        let outcome = await dashboard.sendMessage(
            to: to,
            text: text,
            submit: submit,
            from: requester,
            inReplyTo: inReplyTo,
            images: images
        )
        return mapSendOutcome(outcome)
    }

    private func handleSpawn(
        _ dashboard: any ControlActionDashboard,
        ref: AgentRef,
        requester: SessionID?,
        backend: SessionBackend,
        workingDirectory: String?,
        model: String?
    ) async -> ControlResponse {
        guard Self.isValidWorkingDirectory(workingDirectory) else {
            return .json(400, ErrorDTO(error: "invalid workingDirectory"))
        }

        do {
            let id = try await dashboard.spawnSession(
                ref: ref,
                from: requester,
                backend: backend,
                workingDirectory: workingDirectory
            )
            let modelApplied = await ControlSpawnModelApplier.apply(model, to: id) { model, sessionID in
                await dashboard.setSessionModel(model, for: sessionID)
            }
            if modelApplied == false {
                Self.logger.warning(
                    "Spawned session \(id.rawValue.uuidString, privacy: .private) but model application failed"
                )
            }
            if let role = ControlSpawnContext.role {
                dashboard.persistSessionRole(id: id, role: role)
            }
            dashboard.agoraParticipantLanded(id: id, role: ControlSpawnContext.role, requester: requester)
            return .json(201, IDDTO(id: id.rawValue.uuidString))
        } catch {
            return mapSpawnError(error)
        }
    }

    private static func isValidWorkingDirectory(_ path: String?) -> Bool {
        guard let path else { return true }
        guard !path.isEmpty, (path as NSString).isAbsolutePath else {
            return false
        }

        var isDirectory: ObjCBool = false
        // FileManager follows symlinks here, so symlink-to-directory is accepted.
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func handleRemove(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        requester: SessionID?
    ) async -> ControlResponse {
        guard dashboard.isAuthorizedToRemove(id, requester: requester) else {
            return .json(403, ErrorDTO(error: "forbidden"))
        }
        let existed = await dashboard.removeSession(id)
        return existed ? .json(200, OkDTO(ok: true)) : .status(404)
    }

    private func handleRename(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        name: String,
        requester: SessionID?
    ) -> ControlResponse {
        // 変更系（rename）は remove と同じ自己/祖先認可を要求し、任意 SessionID の
        // rename（IDOR/CWE-639）を塞ぐ。isAuthorizedToRemove は requester=nil（モバイル/
        // ローカル）・privileged（モバイルトークン）・自己・祖先で true を返す共通の
        // セッション所有権判定であり、rename にも適用する。
        guard dashboard.isAuthorizedToRemove(id, requester: requester) else {
            return .json(403, ErrorDTO(error: "forbidden"))
        }
        dashboard.renameSession(id, to: name)
        return .json(200, OkDTO(ok: true))
    }

    // read 系（output/messages/waitReady/wait/listSessions）は operator モデルとして
    // 有効 token を持つ任意セッションからの読み取りを許可する（要求元が対象の祖先でなくても可）。
    // これは PM→worker の read や CLI operator セッションによる横断参照という orchestration の
    // 基盤機能であり、E2E（operator が他セッションを read）が正常系として固定している。
    // 認可を課すのは所有権を変更しうる操作（remove/rename）に限る。

    private func handleOutput(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        mode: OutputMode
    ) -> ControlResponse {
        // mode は現状 screen のみ実装。scrollback も viewport テキストを返す
        // （scrollback 抽出は後続フェーズ。visibleText は viewport 限定のため）。
        guard let text = dashboard.sessionOutput(for: id) else {
            return .json(404, ErrorDTO(error: "session not found"))
        }
        return .json(200, OutputDTO(text: text))
    }

    /// GET /sessions/{id}/messages（契約6）。cursor を常に付与し、since/wait による差分・long-poll に対応。
    /// 非構造化/不在は 404 → モバイルは従来のターミナル output にフォールバックする。
    private func handleMessagesDelta(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        since: String?,
        wait: Int?
    ) async -> ControlResponse {
        guard var delta = dashboard.sessionChatMessagesDelta(for: id, since: since) else {
            return .json(404, ErrorDTO(error: "session not found"))
        }

        // long-poll: since 指定かつ wait 指定時のみ。差分が空で snapshot でもない間だけ待つ。
        // since 省略時は差分の基準が無いので wait を無視して即応答（＝従来挙動＋cursor）。
        // snapshot（編集/置換の検出）が出たら待たずに即返す（変化を握りつぶさない）。
        if let wait, let since, !since.isEmpty {
            let clamped = min(max(wait, 1), 25)
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(clamped))
            while delta.items.isEmpty, !delta.isSnapshot {
                // 残り時間を超えて待たない（次の sleep を deadline で打ち切る）。
                let remaining = deadline - clock.now
                guard remaining > .zero else { break }
                let nap = min(Self.messagesPollInterval, remaining)
                do {
                    // Task.sleep で MainActor を解放しながら待つ（他リクエスト・UI を巻き添えにしない）。
                    try await Task.sleep(for: nap)
                } catch {
                    break
                }
                guard let next = dashboard.sessionChatMessagesDelta(for: id, since: since) else {
                    // 待機中にセッションが消えた。
                    return .json(404, ErrorDTO(error: "session not found"))
                }
                delta = next
            }
        }

        return .json(200, MessagesDeltaDTO(
            sessionId: id.rawValue.uuidString,
            messages: delta.items.map(ChatMessageDTO.from),
            cursor: delta.cursor,
            snapshot: delta.isSnapshot ? true : nil
        ))
    }

    /// long-poll のポーリング間隔。短すぎると CPU を無駄に使い、長すぎると応答遅延が増える。
    private static let messagesPollInterval: Duration = .milliseconds(300)

    private func handleWaitReady(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        timeoutSeconds: Int
    ) async -> ControlResponse {
        // 過大な待機で接続を占有しないよう 1〜60 秒に丸める。
        let capped = min(max(timeoutSeconds, 1), 60)
        let result = await dashboard.waitUntilReady(for: id, timeout: .seconds(capped))
        return mapReadinessResult(result)
    }

    private func handleWait(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        timeoutSeconds: Int,
        sentinel: String?
    ) async -> ControlResponse {
        // 無限待ちを防ぐため 1〜600 秒に丸める。
        let capped = min(max(timeoutSeconds, 1), 600)
        let result = await dashboard.waitUntilDone(
            for: id,
            timeout: .seconds(capped),
            sentinel: sentinel
        )
        return mapDoneResult(result)
    }

    private func handleListApprovals(_ dashboard: any ControlActionDashboard) async -> ControlResponse {
        let items = await dashboard.listApprovals()
        return .json(200, ApprovalListDTO(approvals: items))
    }

    private func handleRespondApproval(
        _ dashboard: any ControlActionDashboard,
        id: String,
        decision: ApprovalDecision
    ) async -> ControlResponse {
        let found = await dashboard.respondToApproval(id: id, decision: decision)
        return found ? .status(200) : .status(404)
    }

    private func handleInterrupt(
        _ dashboard: any ControlActionDashboard,
        id: SessionID
    ) async -> ControlResponse {
        switch await dashboard.interruptSession(id) {
        case .accepted:
            return .status(204)
        case .notFound:
            return .json(404, ErrorDTO(error: "session not found"))
        case .unsupported:
            return .json(409, ErrorDTO(error: "interrupt unsupported"))
        }
    }

    private func handleSubAgents(
        _ dashboard: any ControlActionDashboard,
        id: SessionID
    ) -> ControlResponse {
        guard let summaries = dashboard.sessionSubAgents(for: id) else {
            return .json(404, ErrorDTO(error: "session not found"))
        }
        return .json(200, SubAgentsDTO(
            sessionId: id.rawValue.uuidString,
            subAgents: summaries.map(SubAgentDTO.from)
        ))
    }

    private func handleSubAgentMessages(
        _ dashboard: any ControlActionDashboard,
        id: SessionID,
        subAgentID: String
    ) -> ControlResponse {
        guard let items = dashboard.sessionSubAgentMessages(for: id, subAgentID: subAgentID) else {
            return .json(404, ErrorDTO(error: "session not found"))
        }
        return .json(200, SubAgentMessagesDTO(
            sessionId: id.rawValue.uuidString,
            subAgentId: subAgentID,
            messages: items.map(ChatMessageDTO.from)
        ))
    }

    private func handleUsage(
        _ dashboard: any ControlActionDashboard,
        id: SessionID
    ) -> ControlResponse {
        guard let usage = dashboard.sessionUsage(for: id) else {
            return .json(404, ErrorDTO(error: "session not found"))
        }
        return .json(200, SessionUsageDTO(
            sessionId: id.rawValue.uuidString,
            turn: usage.turn.map(TurnUsageWireDTO.from)
        ))
    }

    // MARK: - Outcome mapping helpers

    private func mapSendOutcome(_ outcome: DashboardViewModel.SendOutcome) -> ControlResponse {
        switch outcome {
        case .sent:
            return .json(200, OkDTO(ok: true))
        case .notFound:
            return .json(404, ErrorDTO(error: "recipient not found"))
        case let .ambiguous(ids):
            return .json(
                409,
                AmbiguousDTO(
                    error: "ambiguous recipient",
                    candidates: ids.map { $0.rawValue.uuidString }
                )
            )
        case let .rejected(reason):
            return .json(400, ErrorDTO(error: reason))
        case .notSpawned:
            return .json(425, ErrorDTO(error: "recipient not spawned yet"))
        case .deliveryFailed:
            return .json(500, ErrorDTO(error: "delivery failed"))
        case .rateLimited:
            return .json(429, ErrorDTO(error: "rate limited"))
        case .imagesUnsupported:
            return .json(409, ErrorDTO(error: "images unsupported"))
        }
    }

    private func mapSpawnError(_ error: Error) -> ControlResponse {
        switch error {
        case AgentSpawnError.spawnRateLimited:
            return .json(429, ErrorDTO(error: "spawn rate limited"))
        case AgentSpawnError.depthLimitExceeded:
            return .json(403, ErrorDTO(error: "spawn depth limit exceeded"))
        default:
            return .json(400, ErrorDTO(error: "spawn failed"))
        }
    }

    private func mapReadinessResult(_ result: DashboardViewModel.ReadinessResult) -> ControlResponse {
        switch result {
        case .ready:
            return .json(200, ReadyDTO(ready: true))
        case .timedOut:
            return .json(200, ReadyDTO(ready: false))
        case .notFound:
            return .json(404, ErrorDTO(error: "session not found"))
        }
    }

    private func mapDoneResult(_ result: DashboardViewModel.DoneResult) -> ControlResponse {
        switch result {
        case let .done(output):
            return .json(200, DoneDTO(done: true, output: output))
        case let .timedOut(output):
            return .json(408, DoneDTO(done: false, output: output))
        case .notFound:
            return .json(404, ErrorDTO(error: "session not found"))
        }
    }

    static func statusString(_ s: SessionStatus) -> String {
        switch s {
        case .starting: "starting"
        case .idle: "idle"
        case .running: "running"
        case .awaitingApproval: "awaitingApproval"
        case .completed: "completed"
        case .error: "error"
        }
    }
}

private struct ApprovalListDTO: Codable {
    let approvals: [ApprovalDTO]
}

private struct OkDTO: Codable {
    let ok: Bool
}

private struct ErrorDTO: Codable {
    let error: String
}

private struct AmbiguousDTO: Codable {
    let error: String
    let candidates: [String]
}

private struct IDDTO: Codable {
    let id: String
}

private struct OutputDTO: Codable {
    let text: String
}

private struct ReadyDTO: Codable {
    let ready: Bool
}

private struct DoneDTO: Codable {
    let done: Bool
    let output: String
}

// MARK: - Chat messages DTO（GET /sessions/{id}/messages）

/// セッション単位の差分/全量チャットレスポンス（契約6）。モバイル側 DTO と完全一致させる。
/// `cursor` は常に付与。`snapshot` は全量フォールバック時（true）のみキーを出す（後方互換のため
/// 差分・全量初回では省略）。
private struct MessagesDeltaDTO: Encodable {
    let sessionId: String
    let messages: [ChatMessageDTO]
    let cursor: String
    let snapshot: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId, messages, cursor, snapshot
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(messages, forKey: .messages)
        try container.encode(cursor, forKey: .cursor)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
    }
}

/// 1 メッセージ分の DTO。`type` で種別を判別し、種別に使うフィールドのみ非 nil（不要キーは省略される）。
/// type: user | agent | reasoning | command | fileChange | error
private struct ChatMessageDTO: Codable {
    let id: String
    let type: String
    let text: String?
    let command: String?
    let output: String?
    let changes: [FileChangeDTO]?
    let message: String?

    init(
        id: String,
        type: String,
        text: String? = nil,
        command: String? = nil,
        output: String? = nil,
        changes: [FileChangeDTO]? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.command = command
        self.output = output
        self.changes = changes
        self.message = message
    }

    /// DashboardFeature の表示モデル `ChatItem` を wire DTO へ写像する。
    static func from(_ item: ChatItem) -> ChatMessageDTO {
        switch item {
        case let .userMessage(id, text, _, _):
            ChatMessageDTO(id: id, type: "user", text: text)
        case let .agentMessage(id, text, _):
            ChatMessageDTO(id: id, type: "agent", text: text)
        case let .reasoning(id, text, _):
            ChatMessageDTO(id: id, type: "reasoning", text: text)
        case let .commandExecution(id, command, output, _):
            ChatMessageDTO(id: id, type: "command", command: command, output: output)
        case let .fileChange(id, changes, _):
            ChatMessageDTO(
                id: id,
                type: "fileChange",
                changes: changes.map { FileChangeDTO(path: $0.path, diff: $0.diff, kind: $0.kind) }
            )
        case let .error(id, message, _):
            ChatMessageDTO(id: id, type: "error", message: message)
        case let .subAgentMarker(id, subagentType, description, status):
            ChatMessageDTO(
                id: id,
                type: "subAgent",
                text: "Sub-agent \(subagentType) \(status.rawValue): \(description)"
            )
        case let .turnCost(id, costUSD, _):
            ChatMessageDTO(id: id, type: "turnCost", text: "$\(costUSD)")
        }
    }
}

/// fileChange の 1 ファイル分。`StructuredChatKit.FilePatchChange` を wire 形へ写像。
private struct FileChangeDTO: Codable {
    let path: String
    let diff: String
    let kind: String?
}

private struct SubAgentsDTO: Encodable {
    let sessionId: String
    let subAgents: [SubAgentDTO]
}

private struct SubAgentDTO: Encodable {
    let id: String
    let name: String
    let status: String
    let messageCount: Int
    let markerMessageId: String?

    static func from(_ summary: SubAgentControlSummary) -> SubAgentDTO {
        SubAgentDTO(
            id: summary.id,
            name: summary.name,
            status: wireStatus(summary.status),
            messageCount: summary.messageCount,
            markerMessageId: summary.markerMessageId
        )
    }

    private static func wireStatus(_ status: SubAgentStatus) -> String {
        switch status {
        case .running: "running"
        case .completed: "completed"
        case .failed: "unknown"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, messageCount, markerMessageId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(markerMessageId, forKey: .markerMessageId)
    }
}

private struct SubAgentMessagesDTO: Codable {
    let sessionId: String
    let subAgentId: String
    let messages: [ChatMessageDTO]
}

private struct SessionUsageDTO: Encodable {
    let sessionId: String
    let turn: TurnUsageWireDTO?

    enum CodingKeys: String, CodingKey {
        case sessionId, turn
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        if let turn {
            try container.encode(turn, forKey: .turn)
        } else {
            try container.encodeNil(forKey: .turn)
        }
    }
}

private struct TurnUsageWireDTO: Encodable {
    let costUSD: Double?
    let contextUsedTokens: Int?
    let contextWindowTokens: Int?

    static func from(_ usage: TurnUsage) -> TurnUsageWireDTO {
        TurnUsageWireDTO(
            costUSD: usage.costUSD,
            contextUsedTokens: usage.contextUsedTokens,
            contextWindowTokens: usage.contextWindowTokens
        )
    }

    enum CodingKeys: String, CodingKey {
        case costUSD, contextUsedTokens, contextWindowTokens
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(costUSD, forKey: .costUSD)
        try container.encodeIfPresent(contextUsedTokens, forKey: .contextUsedTokens)
        try container.encodeIfPresent(contextWindowTokens, forKey: .contextWindowTokens)
    }
}
