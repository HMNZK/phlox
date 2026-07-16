import Foundation

/// 新規セッション起動リクエスト（カンプ④ / POST /sessions）。
public struct SpawnRequest: Sendable, Equatable {
    public let agent: AgentKind
    public let workspace: String
    public let prompt: String?
    public let model: String?

    public init(agent: AgentKind, workspace: String, prompt: String? = nil, model: String? = nil) {
        self.agent = agent
        self.workspace = workspace
        self.prompt = prompt
        self.model = model
    }
}

/// セッションへの送信リクエスト（カンプ⑦ / POST /send（to,text,images）。
/// images は API 拡張契約 v1（docs/specs/mobile-api-extensions-contract.md §5）。既定 [] で後方互換。
public struct SendRequest: Sendable, Equatable {
    public let sessionID: String
    public let text: String
    public let images: [SendAttachment]

    public init(sessionID: String, text: String, images: [SendAttachment] = []) {
        self.sessionID = sessionID
        self.text = text
        self.images = images
    }
}

/// 送信に添付する画像（契約 §5: mediaType は image/png / image/jpeg を必須サポート）。
public struct SendAttachment: Sendable, Equatable {
    public let mediaType: String
    public let data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }
}

/// 送信結果。
public struct SendResult: Sendable, Equatable {
    public let accepted: Bool
    public let message: String?

    public init(accepted: Bool, message: String? = nil) {
        self.accepted = accepted
        self.message = message
    }
}
