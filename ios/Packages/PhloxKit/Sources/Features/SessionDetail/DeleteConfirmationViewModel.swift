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
    public let sessionName: String
    public let cascadeCount: Int
    public var state: State = .idle
    public private(set) var failurePresentation: ErrorPresentation?

    public init(
        sessionID: String,
        sessionName: String = "セッション",
        cascadeCount: Int,
        api: PhloxAPI,
        onDeleted: @escaping () -> Void
    ) {
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.cascadeCount = cascadeCount
        self.api = api
        self.onDeleted = onDeleted
    }

    public var title: String { "“\(sessionName)” を削除しますか？" }

    public var message: String {
        if cascadeCount > 0 {
            return "子孫のセッション \(cascadeCount) 件も一緒に削除されます。合わせて \(cascadeCount + 1) 件です。元に戻せません。"
        }
        return "Mac 側のセッションと会話の記録が削除されます。元に戻せません。"
    }

    public var deleteButtonLabel: String { "\(cascadeCount + 1) 件を削除" }

    public var isDeleting: Bool { state == .deleting }

    /// 一覧の親 ID から子・孫を数える。親 ID の無い旧サーバーでは 0 件になる。
    public static func descendantCount(sessionID: String, sessions: [Session]) -> Int {
        var counted = Set<String>()
        var parents = [sessionID]
        while !parents.isEmpty {
            let parent = parents.removeFirst()
            for child in sessions where child.parentSessionId == parent {
                guard child.id != sessionID, counted.insert(child.id).inserted else { continue }
                parents.append(child.id)
            }
        }
        return counted.count
    }

    /// 二段確認後にのみ呼ばれる（View の confirmationDialog から）。
    public func confirmDelete() async {
        state = .deleting
        failurePresentation = nil
        do {
            try await api.remove(sessionID: sessionID)
            state = .deleted
            onDeleted()
        } catch let error as PhloxError {
            let technicalDetail = error.presentation.technicalDetail ?? "削除に失敗しました"
            let presentation = Self.failurePresentation(cascadeCount: cascadeCount, technicalDetail: technicalDetail)
            failurePresentation = presentation
            state = .failed(Self.failureMessage(presentation))
        } catch {
            let presentation = Self.failurePresentation(cascadeCount: cascadeCount, technicalDetail: nil)
            failurePresentation = presentation
            state = .failed(Self.failureMessage(presentation))
        }
    }

    private static func failurePresentation(cascadeCount: Int, technicalDetail: String?) -> ErrorPresentation {
        let retainedSessions = cascadeCount == 0
            ? "セッションは消えずに残っています。"
            : "セッションと子孫 \(cascadeCount) 件は、どれも消えずに残っています。"
        return ErrorPresentation(
            title: "削除できませんでした",
            message: retainedSessions,
            recoveryAction: "もう一度削除",
            nextStep: "閉じるか、もう一度削除します。",
            technicalDetail: technicalDetail
        )
    }

    private static func failureMessage(_ presentation: ErrorPresentation) -> String {
        [presentation.cause, presentation.nextStep, presentation.technicalDetail]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}
