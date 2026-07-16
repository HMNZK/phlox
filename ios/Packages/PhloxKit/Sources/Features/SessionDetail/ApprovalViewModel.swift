import SwiftUI
import PhloxCore

/// 承認/却下（カンプ③⑧ / E4-7）。Codex は 4 択シート、それ以外は二段確認。自動再試行なし。
@MainActor
@Observable
public final class ApprovalViewModel {
    private let api: PhloxAPI
    public let sessionID: String
    public let agentKind: AgentKind

    public private(set) var approvals: [Approval] = []
    public private(set) var isVisible = false
    public private(set) var isResponding = false
    public var showCodexSheet = false
    public private(set) var resultMessage: String?
    public private(set) var errorMessage: String?

    public init(sessionID: String, agentKind: AgentKind, api: PhloxAPI) {
        self.sessionID = sessionID
        self.agentKind = agentKind
        self.api = api
    }

    /// Codex は 4 択シートで応答する。
    public var usesCodexSheet: Bool { agentKind == .codex }

    public func load() async {
        do {
            let all = try await api.approvals()
            approvals = all.filter { $0.sessionID == sessionID }
            isVisible = !approvals.isEmpty
        } catch let error as PhloxError {
            errorMessage = error.presentation.message
        } catch {
            errorMessage = "承認情報の取得に失敗しました"
        }
    }

    /// バーのボタンタップ。Codex なら 4 択シートを開き、それ以外は直接応答（View 側で二段確認）。
    public func tapPrimary(approvalID: String, decision: ApprovalDecision) async {
        if usesCodexSheet {
            showCodexSheet = true
        } else {
            await respond(decision, approvalID: approvalID)
        }
    }

    public func respond(_ decision: ApprovalDecision, approvalID: String) async {
        guard !isResponding else { return }
        isResponding = true
        showCodexSheet = false
        do {
            try await api.respond(approvalID: approvalID, decision: decision)
            isVisible = false
            resultMessage = "応答を送信しました（\(decision.rawValue)）"
        } catch let error as PhloxError {
            errorMessage = error.presentation.message
        } catch {
            errorMessage = "応答の送信に失敗しました"
        }
        isResponding = false
    }
}
