import SwiftUI
import PhloxCore

/// セッション削除確認（カンプ⑤ / E4-9）。子孫件数を明示し二段確認後に削除する。自動再試行なし。
@MainActor
@Observable
public final class DeleteConfirmationViewModel {
    public enum State: Equatable {
        case idle
        case deleting
        case failed(String)
        case deleted
    }

    private let api: PhloxAPI
    private let onDeleted: () -> Void
    public let sessionID: String
    public let cascadeCount: Int
    public var state: State = .idle

    public init(sessionID: String, cascadeCount: Int, api: PhloxAPI, onDeleted: @escaping () -> Void) {
        self.sessionID = sessionID
        self.cascadeCount = cascadeCount
        self.api = api
        self.onDeleted = onDeleted
    }

    public var message: String {
        cascadeCount > 0
            ? "このセッションと \(cascadeCount) 件の子孫セッションを削除します。"
            : "このセッションを削除します。"
    }

    public var isDeleting: Bool { state == .deleting }

    /// 二段確認後にのみ呼ばれる（View の confirmationDialog から）。
    public func confirmDelete() async {
        state = .deleting
        do {
            try await api.remove(sessionID: sessionID)
            state = .deleted
            onDeleted()
        } catch let error as PhloxError {
            state = .failed(error.presentation.message)
        } catch {
            state = .failed("削除に失敗しました")
        }
    }
}
