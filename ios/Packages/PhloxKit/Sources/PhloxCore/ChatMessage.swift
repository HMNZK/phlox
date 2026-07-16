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
        }
    }
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
