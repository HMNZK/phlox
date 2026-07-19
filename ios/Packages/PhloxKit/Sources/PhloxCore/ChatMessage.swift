import Foundation

/// 構造化チャットの 1 メッセージ（Mac の `ChatItem` に対応する Domain モデル）。
/// `GET /sessions/{id}/messages` の wire DTO から `toDomain()` で変換し、wire format を Domain に漏らさない。
/// 種別は user/agent/reasoning/command/fileChange/error/subAgent の 7 種で、Mac GUI の描画区分と一致する。
public enum ChatMessage: Sendable, Equatable, Identifiable {
    case user(id: String, text: String)
    case agent(id: String, text: String)
    case reasoning(id: String, text: String)
    case command(id: String, command: String?, output: String)
    case fileChange(id: String, changes: [ChatFileChange])
    case error(id: String, message: String)
    case subAgent(id: String, text: String)
    /// AskUserQuestion の質問カード（task-0 契約。Mac の `ChatItem.userQuestion` に対応）。
    /// answers は「質問文 → 選択 label 配列」。
    case userQuestion(
        id: String,
        requestId: String,
        questions: [UserQuestionItem],
        answers: [String: [String]]?,
        state: UserQuestionState
    )

    public var id: String {
        switch self {
        case let .user(id, _),
             let .agent(id, _),
             let .reasoning(id, _),
             let .command(id, _, _),
             let .fileChange(id, _),
             let .error(id, _),
             let .subAgent(id, _):
            id
        case let .userQuestion(id, _, _, _, _):
            id
        }
    }
}

/// AskUserQuestion の選択肢 1 件（Mac の `ChatUserQuestionOption` に対応）。
public struct UserQuestionOption: Sendable, Equatable {
    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

/// AskUserQuestion の質問 1 件（Mac の `ChatUserQuestion` に対応）。
public struct UserQuestionItem: Sendable, Equatable {
    public let question: String
    public let header: String
    public let options: [UserQuestionOption]
    public let multiSelect: Bool

    public init(question: String, header: String, options: [UserQuestionOption], multiSelect: Bool) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// 質問カードの表示状態（Mac の `ChatUserQuestionState` に対応）。
public enum UserQuestionState: String, Sendable, Equatable {
    case pending
    case answered
    case expired
}

/// fileChange メッセージ 1 ファイル分の差分（Mac の `FilePatchChange` に対応）。
public struct ChatFileChange: Sendable, Equatable {
    public let path: String
    public let diff: String
    public let kind: String?

    public init(path: String, diff: String, kind: String? = nil) {
        self.path = path
        self.diff = diff
        self.kind = kind
    }
}
