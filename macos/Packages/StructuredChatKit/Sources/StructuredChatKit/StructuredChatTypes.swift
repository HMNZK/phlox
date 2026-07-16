import Foundation

public struct FilePatchChange: Codable, Equatable, Sendable {
    public var path: String
    public var diff: String
    public var kind: String?

    public init(path: String, diff: String, kind: String? = nil) {
        self.path = path
        self.diff = diff
        self.kind = kind
    }
}

public enum ChatInput: Equatable, Sendable {
    case text(String)
    /// 添付画像（task-8 契約。受け入れテスト AcceptanceImageContentTests が凍結）。
    /// Claude のみ content block として送信。他クライアントは warning + テキストのみ送信へ degrade。
    case image(data: Data, mediaType: String)
}

public enum SubAgentActivityKind: Equatable, Sendable {
    case prompt
    case message
    case reasoning
    case tool
}

/// 1ターンぶんの API 使用量・コスト（Claude Code の stream-json `result` 由来）。
/// 契約: tasks/task-2.md（受け入れテスト AcceptanceTurnUsageTests が凍結）。
public struct TurnUsage: Codable, Equatable, Sendable {
    public var costUSD: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cacheReadTokens: Int?
    public var cacheCreationTokens: Int?
    public var contextUsedTokens: Int?
    public var contextWindowTokens: Int?

    public init(
        costUSD: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        contextUsedTokens: Int? = nil,
        contextWindowTokens: Int? = nil
    ) {
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.contextUsedTokens = contextUsedTokens
        self.contextWindowTokens = contextWindowTokens
    }
}

public enum NormalizedChatEvent: Equatable, Sendable {
    case agentMessageDelta(itemId: String, String)
    case reasoningDelta(itemId: String, String)
    case commandExecution(itemId: String, command: String?, outputDelta: String)
    case fileChange(itemId: String, [FilePatchChange])
    case turnStarted
    /// ターンの使用量・コスト。`turnCompleted` の直前に yield される（tasks/task-2.md）。
    case turnUsage(TurnUsage)
    case turnCompleted(nativeSessionId: String?)
    case turnInterrupted(nativeSessionId: String?)
    case backgroundTaskStarted(taskId: String, taskType: String, description: String, toolUseId: String?)
    case backgroundTaskCompleted(taskId: String, status: String, summary: String)
    case subAgentStarted(toolUseId: String, subagentType: String, description: String)
    case subAgentActivity(toolUseId: String, kind: SubAgentActivityKind, itemId: String?, text: String)
    case subAgentOutput(toolUseId: String, text: String)
    case subAgentCompleted(toolUseId: String, status: String, summary: String, outputFile: String?)
    case error(message: String)
    case warning(message: String)
}

public protocol StructuredAgentClient: Sendable {
    var events: AsyncStream<NormalizedChatEvent> { get }

    func start() async
    func turnStart(_ input: [ChatInput]) async throws
    func resume(sessionRef: String) async throws
    func interrupt() async throws
    func close() async

    /// 現在の CLI 側会話文脈を破棄し、新規会話に切り替える（巻き戻し=リバートの一部）。
    /// CLI ネイティブの「特定メッセージ時点への巻き戻し」API は存在しないため、ローカル転写の
    /// 巻き戻しと組み合わせて「新規会話 + 文脈リプレイ」を実現する。文脈リプレイのプリアンブル
    /// 合成は呼び出し側（VM）が担い、本メソッドは CLI 側の会話状態リセットのみに責任を持つ。
    /// 会話状態を持たないクライアントは既定の no-op で足りる。
    func resetConversation() async
}

public extension StructuredAgentClient {
    /// 既定は no-op（会話状態を持たないクライアント向け）。
    func resetConversation() async {}
}
