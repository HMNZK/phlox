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
    /// ツール呼び出し（子の `tool_use`）。`itemId` は子の tool_use.id。
    case tool
    /// ツール結果（子の `tool_result`）。`itemId` は同じ tool_use_id で、`.tool` と1セルにマージされる。
    case toolResult
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

/// AskUserQuestion の選択肢 1 件（task-0 契約。受け入れテスト AcceptanceUserQuestionChatItemCodableTests が凍結）。
public struct ChatUserQuestionOption: Codable, Equatable, Sendable {
    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

/// AskUserQuestion の質問 1 件。CLI の can_use_tool 入力 `questions[]` と 1:1 対応（task-0 契約）。
public struct ChatUserQuestion: Codable, Equatable, Sendable {
    public let question: String
    public let header: String
    public let options: [ChatUserQuestionOption]
    public let multiSelect: Bool

    public init(question: String, header: String, options: [ChatUserQuestionOption], multiSelect: Bool) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// 保留中の質問がどう決着したか。answered は VM 起点の回答、expired は turn 中断・
/// プロセス終了・respawn による失効（クライアントが権威として yield する）。
public enum ChatUserQuestionOutcome: Equatable, Sendable {
    case answered(answers: [String: [String]])
    case expired
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
    /// 会話履歴の圧縮（compaction）境界。Claude Code stream-json の
    /// `system/compact_boundary` に対応する（phlox-ux-5fixes task-2 契約。
    /// 受け入れテスト AcceptanceCompactBoundaryTests / AcceptanceCompactingIndicatorTests が凍結）。
    /// trigger は "auto" | "manual"（未知値はそのまま透過）、preTokens は圧縮前トークン数。
    case compactionBoundary(trigger: String?, preTokens: Int?)
    /// AskUserQuestion（control_request can_use_tool）が届いた。UI は質問カードを表示し、
    /// `respondToUserQuestion` で回答を返送する（task-0 契約）。
    case userQuestionRequested(requestId: String, questions: [ChatUserQuestion])
    /// 保留中の質問の決着（回答送信完了 or 失効）。requestId は Requested と対応する。
    case userQuestionResolved(requestId: String, outcome: ChatUserQuestionOutcome)
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

    /// AskUserQuestion への回答を CLI へ返送する（task-0 契約）。
    /// `answers` は「質問文 → 選択した label 配列」（single-select は 1 要素。自由入力はその文字列）。
    /// AskUserQuestion に対応しないクライアントは既定の no-op で足りる。
    func respondToUserQuestion(requestId: String, answers: [String: [String]]) async
}

public extension StructuredAgentClient {
    /// 既定は no-op（会話状態を持たないクライアント向け）。
    func resetConversation() async {}

    /// 既定は no-op（AskUserQuestion 非対応クライアント向け）。
    func respondToUserQuestion(requestId: String, answers: [String: [String]]) async {}
}
