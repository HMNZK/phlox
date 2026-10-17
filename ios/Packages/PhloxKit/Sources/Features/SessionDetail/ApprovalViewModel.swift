import SwiftUI
import PhloxCore

/// 承認/却下（カンプ③⑧ / E4-7）。応答の自動再試行はしない。
@MainActor
@Observable
public final class ApprovalViewModel {
    private let api: PhloxAPI
    public let sessionID: String

    public private(set) var approvals: [Approval] = []
    public private(set) var isVisible = false
    public private(set) var isResponding = false
    public private(set) var resultMessage: String?
    public private(set) var errorMessage: String?

    public init(sessionID: String, api: PhloxAPI) {
        self.sessionID = sessionID
        self.api = api
    }

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

    /// バーの「承認」「却下」から直接応答する。
    public func tapPrimary(approvalID: String, decision: ApprovalDecision) async {
        await respond(decision, approvalID: approvalID)
    }

    public func respond(_ decision: ApprovalDecision, approvalID: String) async {
        guard !isResponding else { return }
        isResponding = true
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
