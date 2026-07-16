import SwiftUI
import PhloxCore

/// 質問待ちセッションへの回答（カンプ⑦ / DP-4-7）。
/// エージェント質問を表示し、ユーザー回答を楽観的バブル追加 → `POST /send` で送信する。
@MainActor
@Observable
public final class ChatAnswerViewModel {
    public enum SendState: Equatable {
        case idle
        case sending
        case failed(String)
    }

    public struct UserMessage: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let text: String
        public let isPending: Bool

        public init(id: UUID = UUID(), text: String, isPending: Bool) {
            self.id = id
            self.text = text
            self.isPending = isPending
        }
    }

    private let api: PhloxAPI
    public let session: Session
    public var inputText: String = ""
    public private(set) var userMessages: [UserMessage] = []
    public private(set) var sendState: SendState = .idle

    public init(session: Session, api: PhloxAPI) {
        self.session = session
        self.api = api
        if ProcessInfo.processInfo.arguments.contains("-UIScreen=chatAnswer") {
            let draft = "v2 契約で。prompt は必須にして。"
            inputText = draft
            userMessages = [UserMessage(text: draft, isPending: false)]
        }
    }

    public var agentQuestion: String {
        Self.agentQuestionText(for: session)
    }

    public var isSending: Bool { sendState == .sending }

    /// エージェント質問文をセッションから導出する（テスト可能な決定点）。
    static func agentQuestionText(for session: Session) -> String {
        if case .awaitingApproval(let prompt) = session.status, !prompt.isEmpty {
            return prompt
        }
        let subtitle = session.subtitle
        let prefix = "回答待ち: 「"
        if subtitle.hasPrefix(prefix), let closing = subtitle.lastIndex(of: "」") {
            let start = subtitle.index(subtitle.startIndex, offsetBy: prefix.count)
            guard start < closing else { return subtitle }
            return String(subtitle[start..<closing])
        }
        if !subtitle.isEmpty {
            return subtitle
        }
        return "質問があります"
    }

    /// 回答を送信。楽観的にユーザーバブルを追加 → 失敗時はロールバック。
    public func sendAnswer() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendState != .sending else { return }

        let backup = inputText
        let messageID = UUID()
        inputText = ""
        userMessages.append(UserMessage(id: messageID, text: text, isPending: true))
        sendState = .sending

        do {
            let result = try await api.send(SendRequest(sessionID: session.id, text: text))
            confirmMessage(id: messageID)
            if result.accepted {
                sendState = .idle
            } else {
                sendState = .failed(result.message ?? "送信が拒否されました")
            }
        } catch let error as PhloxError {
            rollbackMessage(id: messageID, restoredInput: backup)
            sendState = .failed(error.presentation.message)
        } catch {
            rollbackMessage(id: messageID, restoredInput: backup)
            sendState = .failed("送信に失敗しました")
        }
    }

    private func confirmMessage(id: UUID) {
        guard let index = userMessages.firstIndex(where: { $0.id == id }) else { return }
        let message = userMessages[index]
        userMessages[index] = UserMessage(id: message.id, text: message.text, isPending: false)
    }

    private func rollbackMessage(id: UUID, restoredInput: String) {
        userMessages.removeAll { $0.id == id }
        inputText = restoredInput
    }
}
