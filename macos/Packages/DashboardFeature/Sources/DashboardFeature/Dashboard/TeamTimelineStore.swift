import Foundation
import Observation
import AgentDomain

/// チームタイムラインの再構築を「入力が実際に変わったときだけ」に限定するストア。
///
/// `TeamTimelineView.body` が transcript / lastOutputAt 等の高頻度 observable を直接読むと、
/// ストリーミングのデルタごとに body 無効化→全再計算が走る（task-1 診断 P2）。
/// 本ストアは caller（表示中のみ動く周期 tick）から `refreshIfNeeded` で駆動され、
/// signature が前回適用値と等しい間は再構築を行わない。
/// 契約の正本: TeamTimelineStoreAcceptanceTests（凍結）。
@MainActor
@Observable
public final class TeamTimelineStore {
    public private(set) var sources: [TeamTimelineSource] = []
    public private(set) var items: [TeamTimelineItem] = []
    public private(set) var agentEntries: [AgentTimelineEntry] = []
    public private(set) var isComposerReadyForInput = false

    private var lastSignature: TeamTimelineSignature?

    public init() {}

    /// signature が前回適用値と異なるときだけ `makeSources` を実行し、
    /// `sources` と `items`（= `TeamTimelineModel.merge(sources)`）を再構築して true を返す。
    /// 等しければ makeSources を呼ばず false を返す。
    @discardableResult
    public func refreshIfNeeded(
        signature: TeamTimelineSignature,
        makeSources: () -> [TeamTimelineSource]
    ) -> Bool {
        guard signature != lastSignature else { return false }
        lastSignature = signature
        sources = makeSources()
        items = TeamTimelineModel.merge(sources)
        agentEntries = []
        refreshComposerReadiness(false)
        return true
    }

    /// エージェントビュー用。signature が変わった場合だけ source と timeline tree を再構築する。
    @discardableResult
    public func refreshAgentTimelineIfNeeded(
        signature: TeamTimelineSignature,
        rootID: SessionID?,
        messageLimitPerSession: Int,
        makeSources: () -> [AgentTimelineSource]
    ) -> Bool {
        guard signature != lastSignature else { return false }
        lastSignature = signature

        let agentSources = makeSources()
        sources = agentSources.map {
            TeamTimelineSource(
                id: $0.id,
                displayName: $0.displayName,
                agentDescriptor: $0.agentDescriptor,
                messages: $0.messages
            )
        }
        items = TeamTimelineModel.merge(sources)
        if let rootID {
            agentEntries = AgentChatTimelineBuilder.build(
                sources: agentSources,
                rootID: rootID,
                messageLimitPerSession: messageLimitPerSession
            )
        } else {
            agentEntries = []
        }
        return true
    }

    /// アゴラ用。signature が変わった場合だけ source を作り、ルート＋直接の子だけを
    /// フラットなグループチャットへマージする。
    @discardableResult
    public func refreshAgoraTimelineIfNeeded(
        signature: TeamTimelineSignature,
        messageLimitPerSession: Int,
        discussionParticipants: Set<SessionID>? = nil,
        makeSources: () -> [AgentTimelineSource]
    ) -> Bool {
        guard signature != lastSignature else { return false }
        lastSignature = signature

        let agentSources = makeSources().map { source in
            AgentTimelineSource(
                id: source.id,
                parentSessionID: source.parentSessionID,
                displayName: source.displayName,
                agentDescriptor: source.agentDescriptor,
                messages: Self.limitedMessages(
                    source.messages,
                    messageLimitPerSession: messageLimitPerSession
                )
            )
        }
        let parentByID = Dictionary(
            uniqueKeysWithValues: agentSources.compactMap { source in
                source.parentSessionID.map { (source.id, $0) }
            }
        )
        // 討論中は makeSources（段1）が既に参加者集合で絞り込んでいるが、
        // 二次フィルタでも discussionParticipants を渡して階層ベースの非討論ロジックに
        // 孫参加者が落ちないよう貫通する（root 不変条件への暗黙依存を避ける）。
        let participantIDs = AgoraParticipantsPolicy.participants(
            orderedIDs: agentSources.map(\.id),
            parentByID: parentByID,
            discussionParticipants: discussionParticipants
        )
        let participantSources = TeamTimelineNodeOrdering.ordered(
            ids: participantIDs,
            items: agentSources,
            id: \.id
        )

        sources = participantSources.map {
            TeamTimelineSource(
                id: $0.id,
                displayName: $0.displayName,
                agentDescriptor: $0.agentDescriptor,
                messages: $0.messages
            )
        }
        items = AgoraTimelineBuilder.build(
            sources: participantSources,
            participants: participantIDs
        )
        agentEntries = []
        return true
    }

    /// Composer readiness は時刻経過だけで変わる PTY 経路があるため、timeline signature と独立に更新する。
    @discardableResult
    public func refreshComposerReadiness(_ isReadyForInput: Bool) -> Bool {
        guard isComposerReadyForInput != isReadyForInput else { return false }
        isComposerReadyForInput = isReadyForInput
        return true
    }

    private static func limitedMessages(
        _ messages: [TeamTimelineSourceMessage],
        messageLimitPerSession: Int
    ) -> [TeamTimelineSourceMessage] {
        guard messageLimitPerSession > 0, messages.count > messageLimitPerSession else {
            return messages
        }
        return Array(messages.suffix(messageLimitPerSession))
    }
}

/// タイムライン入力の版数署名。成分ごとの値等値（順序込み）で比較する。
public struct TeamTimelineSignature: Hashable, Sendable {
    private let components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    static func make(
        selectedSessionID: SessionID?,
        selectedProjectID: ProjectID? = nil,
        sessions: [TeamTimelineSignatureSession],
        discussionParticipantIDs: Set<SessionID>? = nil
    ) -> TeamTimelineSignature {
        var components = [
            "selected:\(selectedSessionID?.rawValue.uuidString ?? "nil")",
            "selectedProject:\(selectedProjectID?.rawValue.uuidString ?? "nil")",
        ]
        components.reserveCapacity(2 + sessions.count * 12 + 1)

        for session in sessions {
            components.append("session:\(session.id.rawValue.uuidString)")
            components.append("parent:\(session.parentSessionID?.rawValue.uuidString ?? "nil")")
            components.append("project:\(session.projectID?.rawValue.uuidString ?? "nil")")
            components.append("launch:\(String(describing: session.launchContext))")
            components.append("status:\(String(describing: session.status))")
            components.append("name:\(session.name)")
            components.append("display:\(session.displayName)")
            components.append("agentRef:\(session.agentDescriptor.ref.id)")
            components.append("agentDisplay:\(session.agentDescriptor.displayName)")
            components.append("agentColor:\(session.agentDescriptor.colorRGB.hex)")
            components.append(session.content.component)
        }

        if let discussionParticipantIDs {
            let sorted = discussionParticipantIDs.map(\.rawValue.uuidString).sorted()
            components.append("agoraDiscussionParticipants:\(sorted.joined(separator: ","))")
        }

        return TeamTimelineSignature(components)
    }
}

struct TeamTimelineSignatureSession: Sendable {
    let id: SessionID
    let parentSessionID: SessionID?
    let projectID: ProjectID?
    let launchContext: SessionLaunchContext
    let status: SessionStatus
    let name: String
    let displayName: String
    let agentDescriptor: AgentDescriptor
    let content: TeamTimelineSignatureContent
}

enum TeamTimelineSignatureContent: Sendable {
    case appServer(transcriptRevision: Int)
    case pty(lastOutputAt: Date?)

    var component: String {
        switch self {
        case .appServer(let transcriptRevision):
            "appTranscriptRevision:\(transcriptRevision)"
        case .pty(let lastOutputAt):
            "ptyLastOutputAt:\(lastOutputAt?.timeIntervalSinceReferenceDate.description ?? "nil")"
        }
    }
}

private extension AgentRGB {
    var hex: String {
        String(format: "%02X%02X%02X", r, g, b)
    }
}

/// PM3 task-7 契約（PM 設置）: makeSources の「ID 列→ノード列」解決の純関数。
/// セマンティクス（受け入れテストで凍結）: ids の順序を保存する／items に無い id は落とす／
/// items 側の重複 id は最初の一致を採る／ids 側の重複はその回数だけ出力する。
/// 実装タスク（task-7）でこの内部を O(n) に置き換える（セマンティクス不変）。
enum TeamTimelineNodeOrdering {
    static func ordered<T>(ids: [SessionID], items: [T], id: (T) -> SessionID) -> [T] {
        // items 側で id が重複する場合は最初の一致を採る（`Dictionary(grouping:)` は
        // 全一致を集めてしまうため使わず、`init(_:uniquingKeysWith:)` で「先勝ち」に固定する）。
        let byID = Dictionary(items.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
}
