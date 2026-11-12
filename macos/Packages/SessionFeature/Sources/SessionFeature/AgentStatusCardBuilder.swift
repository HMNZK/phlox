import Foundation
import AgentDomain
import ChatRenderKit
import DesignSystem
import StructuredChatKit

// エージェント状態カード（agent-status-card-design.md §4、ADR 0226）。

/// 組み立てに使う、実行中の状態。
struct AgentStatusLiveState: Equatable, Sendable {
    /// `showsProcessingIndicator`（バックグラウンドタスク・サブエージェントが動く間も true）。
    var isProcessing: Bool
    var activityState: AgentActivityState
    var hangAssessment: ChatHangAssessment?
    var isAwaitingReply: Bool
}

struct AgentStatusCard: Identifiable, Equatable, Sendable {
    /// `status-card-<起点の userMessage の id>`。
    let id: String
    let header: AgentStatusHeader
    /// タスクの行とタスク外の作業の行。タスクは最新のスナップショットの順、タスク外は時系列の位置。
    let rows: [AgentStatusRow]
    var changeCounts: ChatFileChangePresentation.Counts? = nil
    var totalRowCount: Int? = nil
    var hasTask: Bool? = nil
}

/// 見出し（1 行目）。経過は表示側が `startedAt` と今の時刻から数える（実行中でないカードは時刻で変わらない）。
public struct AgentStatusHeader: Equatable, Codable, Sendable {
    public enum State: Equatable, Codable, Sendable {
        case running
        case stalled
        case awaitingReply
        case completed
        case interrupted
        case error
        case superseded
        /// 終わり方の記録が無い（この機能より前の会話・異常終了・アプリの終了）。印も所要時間も出さない。
        case ended
    }

    let state: State
    /// 実行中の「今の作業」（区間の最後の作業）。作業がまだ無ければ nil。
    let current: AgentStatusAction.Label?
    /// 実行中で作業がまだ無いときの状態語。
    let activityState: AgentActivityState?
    /// 入力を送った時刻。
    let startedAt: Date
    /// 終わった時刻（`turnEnd.at`）。実行中・終了は nil。
    let endedAt: Date?
    /// 無応答の長さ（`.stalled` のときだけ）。
    let silence: TimeInterval?

    /// 実行中の見出し（動く点描・経過を数える）。
    var isLive: Bool { state == .running || state == .stalled || state == .awaitingReply }

    /// 点描の種類。今の作業があればその種類、無ければ状態語の元の活動状態。
    var orbState: AgentActivityState {
        if state == .awaitingReply { return .waiting }
        guard let current else { return activityState ?? .thinking }
        switch current {
        case .read, .search, .searches: return .searching
        case .edit, .editFiles: return .editing
        case .write: return .writing
        case .run, .command, .tool, .subAgent: return .running
        }
    }

    /// 見出しの中央の文言。
    func title(locale: Locale, bundle: Bundle = .main) -> String {
        switch state {
        case .running, .stalled:
            if let current { return current.text(running: true, locale: locale, bundle: bundle) }
            return (activityState ?? .thinking).orbLabel(locale: locale)
        case .awaitingReply:
            return AppLocalizedString.string("待機中…", locale: locale, bundle: bundle)
        case .completed:
            return AppLocalizedString.string("完了", locale: locale, bundle: bundle)
        case .interrupted:
            // 「中断」は既存のキー（ボタンの Interrupt）と英語が違うので、別のキーで引く。
            return AgentStatusText.keyed("statusCard.interrupted", japanese: "中断", locale: locale, bundle: bundle)
        case .error:
            return AppLocalizedString.string("エラー", locale: locale, bundle: bundle)
        case .superseded:
            return AppLocalizedString.string("次の入力へ続く", locale: locale, bundle: bundle)
        case .ended:
            // 「終了」も既存のキー（Quit）と英語が違う。
            return AgentStatusText.keyed("statusCard.ended", japanese: "終了", locale: locale, bundle: bundle)
        }
    }
}

enum AgentStatusRow: Identifiable, Equatable, Sendable {
    case task(AgentStatusTask)
    case outside(AgentStatusOutsideGroup)

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id)"
        case .outside(let group): group.id
        }
    }
}

public struct AgentStatusTask: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Codable, Sendable {
        case pending
        case inProgress
        case completed
        /// 進行中のままカードが終わった（中断・エラー・次の入力へ続く・終了）。
        case interrupted
    }

    public let id: String
    let title: String
    let state: State
    /// この入力の中で最初に進行中として現れたスナップショットの時刻。
    let startedAt: Date?
    /// 完了：最初に完了として現れた時刻。中断：入力の終わった時刻。それ以外は nil。
    let endedAt: Date?
    let entries: [AgentStatusEntry]
    var totalEntryCount: Int? = nil
}

struct AgentStatusOutsideGroup: Identifiable, Equatable, Sendable {
    let id: String
    let entries: [AgentStatusEntry]
    var totalEntryCount: Int? = nil
    var totalActionCount: Int? = nil
    var aggregateState: AgentStatusWorkState? = nil

    var state: AgentStatusWorkState {
        aggregateState ?? AgentStatusWorkState.aggregate(entries.compactMap {
            if case .action(let action) = $0 { action.state } else { nil }
        })
    }
}

public enum AgentStatusWorkState: Hashable, Codable, Sendable {
    case running
    case completed
    case interrupted
    case failed
    case unknown

    static func aggregate(_ states: [Self]) -> Self {
        if states.contains(.running) { return .running }
        if states.contains(.failed) { return .failed }
        if states.contains(.interrupted) { return .interrupted }
        if states.isEmpty || states.contains(.unknown) { return .unknown }
        return .completed
    }
}

/// カードの中の 1 件。作業の行か、そのまま出す item（文章・思考・質問・エラーなど）。
enum AgentStatusEntry: Identifiable, Equatable, Sendable {
    case action(AgentStatusAction)
    case item(ChatItem)

    var id: String {
        switch self {
        case .action(let action): action.id
        case .item(let item): item.id
        }
    }
}

/// 作業の行。同じ種類（読み込み・検索・編集）が続いたら 1 行にまとめる。
public struct AgentStatusAction: Identifiable, Equatable, Sendable {
    public enum Label: Equatable, Codable, Sendable {
        case read(file: String, more: Int)
        case search(query: String, hits: Int)
        case searches(times: Int, hits: Int)
        case edit(file: String)
        case editFiles(count: Int)
        case write(file: String)
        /// エージェントが付けた説明（Claude の Bash の `description`）。
        case run(intent: String)
        case command(String)
        case tool(String)
        case subAgent(description: String, type: String, status: SubAgentStatus)

        static func subAgentStatusText(_ status: SubAgentStatus, locale: Locale, bundle: Bundle = .main) -> String {
            switch status {
            case .running: AppLocalizedString.string("実行中", locale: locale, bundle: bundle)
            case .completed: AppLocalizedString.string("完了", locale: locale, bundle: bundle)
            case .failed: AppLocalizedString.string("失敗", locale: locale, bundle: bundle)
            case .stopped: AgentStatusText.keyed("subagent.status.stopped", japanese: "停止", locale: locale, bundle: bundle)
            }
        }

        private static func endsWithJapanese(_ text: String) -> Bool {
            guard let scalar = text.unicodeScalars.last else { return false }
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xFF66...0xFF9F: return true
            default: return false
            }
        }

        func text(running: Bool, locale: Locale, bundle: Bundle = .main) -> String {
            func format(_ key: String, _ arguments: CVarArg...) -> String {
                String(format: AppLocalizedString.string(key, locale: locale, bundle: bundle), arguments: arguments)
            }
            switch self {
            case .read(let file, 0):
                return format(running ? "%@ を読み込み中" : "%@ を読み込み", file)
            case .read(let file, let more):
                return format(running ? "%1$@ ほか %2$lld ファイルを読み込み中" : "%1$@ ほか %2$lld ファイルを読み込み", file, more)
            case .search(let query, let hits):
                return running ? format("「%@」を検索中", query) : format("「%1$@」を検索 · %2$lld 件", query, hits)
            case .searches(let times, let hits):
                return running ? format("%lld 回検索中", times) : format("%1$lld 回検索 · %2$lld 件", times, hits)
            case .edit(let file):
                return format(running ? "%@ を編集中" : "%@ を編集", file)
            case .editFiles(let count):
                return format(running ? "%lld ファイルを編集中" : "%lld ファイルを編集", count)
            case .write(let file):
                return format(running ? "%@ に書き込み中" : "%@ に書き込み", file)
            case .run(let intent):
                // 「中」は日本語の説明にだけ付ける。英語などの説明には英語の表記と同じ「…」を付ける。
                return running ? (Self.endsWithJapanese(intent) ? format("%@中", intent) : intent + "…") : intent
            case .command(let command):
                let shown = command.isEmpty
                    ? UIWording.text(.missingCommand, languageCode: locale.language.languageCode?.identifier ?? "ja")
                    : command
                return running ? format("%@ を実行中", shown) : shown
            case .tool(let name):
                return format(running ? "%@ を実行中" : "%@ を実行", name)
            case .subAgent(let description, let type, let status):
                let subject = description.isEmpty
                    ? UIWording.text(.missingSubAgentDescription, languageCode: locale.language.languageCode?.identifier ?? "ja")
                    : description
                return [AppLocalizedString.string("サブエージェント", locale: locale, bundle: bundle), subject,
                    type, Self.subAgentStatusText(status, locale: locale, bundle: bundle)]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }
        }
    }

    /// まとめた元の item（開いたときに今のツールカードの中身を出す）。
    let items: [ChatItem]
    let label: Label
    let state: AgentStatusWorkState
    /// 開始から結果が届くまで。結果の時刻が無い（実行中・旧記録・サブエージェント）なら nil。
    let duration: TimeInterval?

    var totalItemCount: Int? = nil
    var remoteID: String? = nil
    var remoteStartedAt: Date? = nil

    public var id: String { remoteID ?? items[0].id }
    var isRunning: Bool { state == .running }
    var startedAt: Date? { remoteStartedAt ?? items.first.flatMap { $0.timestamp == .distantPast ? nil : $0.timestamp } }

    func elapsed(at now: Date) -> TimeInterval? {
        if isRunning { return startedAt.map { max(0, now.timeIntervalSince($0)) } }
        return state == .completed ? duration : nil
    }

    func text(locale: Locale, bundle: Bundle = .main) -> String {
        label.text(running: isRunning, locale: locale, bundle: bundle)
    }
}

/// 時間の書き方（要件 FR-4、見本 10-Anatomy）。
typealias AgentStatusDurationFormat = ChatDurationFormat

extension AgentStatusDurationFormat {
    /// VoiceOver 用。13 秒、1 分 20 秒、1 時間 2 分。
    /// `fractional`: 10 秒未満を 0.6 秒のように小数で読む（作業の行）。
    static func spoken(_ seconds: TimeInterval, locale: Locale, bundle: Bundle = .main, fractional: Bool = false) -> String {
        func format(_ key: String, _ arguments: CVarArg...) -> String {
            String(format: AppLocalizedString.string(key, locale: locale, bundle: bundle), arguments: arguments)
        }
        if fractional, seconds < 0.1 { return format("0.1 秒未満") }
        if fractional, seconds < 10 { return format("%.1f 秒", max(0, seconds)) }
        let total = Int(max(0, seconds))
        if total >= 3600 { return format("%1$lld 時間 %2$lld 分", total / 3600, total % 3600 / 60) }
        if total >= 60 { return format("%1$lld 分 %2$lld 秒", total / 60, total % 60) }
        return format("%lld 秒", total)
    }
}

enum AgentStatusText {
    /// 既存の日本語キーと英語が衝突する文言は、識別子のキーで引き、訳が無ければ日本語を返す。
    static func keyed(_ key: String, japanese: String, locale: Locale, bundle: Bundle) -> String {
        let text = AppLocalizedString.string(key, locale: locale, bundle: bundle)
        return text == key ? japanese : text
    }
}

/// 確定した項目ごとの寄与。再受信・差分置換で同じ作業を重複加算しない。
struct AgentStatusChangeCounts {
    private var contributions: [String: ChatFileChangePresentation.Counts] = [:]
    private var additions = 0
    private var deletions = 0

    init<Items: Sequence>(items: Items) where Items.Element == ChatItem {
        for item in items { update(item) }
    }

    var counts: ChatFileChangePresentation.Counts? {
        contributions.isEmpty ? nil : .init(additions: additions, deletions: deletions)
    }

    mutating func update(_ item: ChatItem) {
        if let previous = contributions.removeValue(forKey: item.id) {
            additions -= previous.additions
            deletions -= previous.deletions
        }
        guard case .fileChange(_, let changes, _, .some) = item,
              !changes.isEmpty, changes.allSatisfy({ !$0.diff.isEmpty }) else { return }
        let counts = changes.reduce(ChatFileChangePresentation.Counts(additions: 0, deletions: 0)) { total, change in
            let next = ChatMessageRenderCache.diffCounts(change.diff)
            return .init(additions: total.additions + next.additions, deletions: total.deletions + next.deletions)
        }
        contributions[item.id] = counts
        additions += counts.additions
        deletions += counts.deletions
    }
}

enum AgentStatusCardBuilder {
    /// この機能より前の版が上書きしていた、固定 id の 1 枚（FR-22）。
    static let legacyTaskListID = "task-list"

    /// 会話ログを `userMessage` で区切り、作業やタスクのある区間をカードにする。
    /// 作業の無い区間と、最初の入力より前の item は今の `ChatTranscriptGrouping.blocks` のまま。
    static func build(items: [ChatItem], liveState: AgentStatusLiveState) -> [ChatTranscriptBlock] {
        let (prefixEnd, segments) = segments(items, liveState: liveState)
        return ChatTranscriptGrouping.blocks(from: Array(items[..<prefixEnd]))
            + segments.flatMap { segmentBlocks(SegmentPlan($0, in: items), liveState: liveState) }
    }

    static func buildInputInterval(items: [ChatItem], baseline: ChatItem?, liveState: AgentStatusLiveState) -> [ChatTranscriptBlock] {
        guard !items.isEmpty else { return [] }
        return segmentBlocks(SegmentPlan(Segment(range: items.indices, baseline: baseline.flatMap(Snapshot.init),
            running: liveState.isProcessing), in: items), liveState: liveState)
    }

    /// 末尾 `blockLimit` ブロックだけを組み立てる（`build` してから窓で切った結果と同じ）。
    /// 窓の外の区間はブロック数だけを配列を作らずに数え（隠れ件数のため）、作業の行・文言・所要時間を
    /// 作るのは窓に入る区間だけ。本体の再描画のたびに呼ばれる（NFR-1、B3 指摘 2）。
    static func visibleSlice(items: [ChatItem], liveState: AgentStatusLiveState, blockLimit: Int) -> ChatTranscriptSlice {
        let limit = max(0, blockLimit)
        let (prefixEnd, segments) = segments(items, liveState: liveState)
        let prefix = items[..<prefixEnd]
        let total = segments.reduce(groupedBlockCount(prefix)) { $0 + blockCount($1, in: items) }

        var built: [[ChatTranscriptBlock]] = []
        var builtCount = 0
        for segment in segments.reversed() where builtCount < limit {
            let blocks = segmentBlocks(SegmentPlan(segment, in: items), liveState: liveState)
            built.append(blocks)
            builtCount += blocks.count
        }
        if builtCount < limit { built.append(ChatTranscriptGrouping.blocks(from: Array(prefix))) }

        let visible = built.reversed().joined().suffix(limit)
        return ChatTranscriptSlice(
            blocks: visible.map { ChatTranscriptVisibleBlock(id: $0.id, content: $0) },
            hiddenBlockCount: total - visible.count
        )
    }

    /// 入力 1 回の区間（起点の userMessage から次の入力の直前まで）と、その基準・実行中かどうか。
    private struct Segment {
        let range: Range<Int>
        let baseline: Snapshot?
        let running: Bool
    }

    /// 会話ログを入力の区間に分け、それぞれの基準（区間の直前の最後のスナップショット）を決める。
    /// 返す `prefixEnd` は最初の入力の位置（それより前は今のブロックのまま）。
    private static func segments(_ items: [ChatItem], liveState: AgentStatusLiveState) -> (prefixEnd: Int, segments: [Segment]) {
        var starts: [Int] = []
        var lastSnapshotBefore: [Int?] = []
        var lastSnapshot: Int?
        for index in items.indices {
            switch items[index] {
            case .userMessage:
                starts.append(index)
                lastSnapshotBefore.append(lastSnapshot)
            case .taskList:
                lastSnapshot = index
            default:
                break
            }
        }
        guard let first = starts.first else { return (items.endIndex, []) }
        let segments = starts.indices.map { number in
            Segment(
                range: starts[number]..<(number + 1 < starts.count ? starts[number + 1] : items.endIndex),
                baseline: lastSnapshotBefore[number].flatMap { Snapshot(items[$0]) },
                running: number == starts.count - 1 && liveState.isProcessing
            )
        }
        return (first, segments)
    }

    /// `segmentBlocks(SegmentPlan(segment))` のブロック数を、配列を作らずに数える（窓の外の区間に使う）。
    /// 決まりは `SegmentPlan` と同じ（変更が空の fileChange を除いて、カードの有無・上・下を決める）。
    private static func blockCount(_ segment: Segment, in items: [ChatItem]) -> Int {
        let body = items[(segment.range.lowerBound + 1)..<segment.range.upperBound]
        var boundary = body.endIndex
        var firstReply = body.endIndex
        var hasActivity = false
        var hasSnapshot = false
        for index in body.indices {
            switch body[index] {
            case .fileChange(_, let changes, _, _) where changes.isEmpty:
                continue
            case .commandExecution, .fileChange, .subAgentMarker:
                hasActivity = true
                boundary = min(boundary, index)
            case .reasoning where isNonEmptyReasoning(body[index]):
                hasActivity = true
                boundary = min(boundary, index)
            case .taskList:
                hasSnapshot = true
                boundary = min(boundary, index)
            case .agentMessage:
                firstReply = min(firstReply, index)
            default:
                break
            }
        }
        let hasCard = hasActivity || (segment.running && firstReply == body.endIndex)
            || (hasSnapshot && !shownTasks(body.compactMap(Snapshot.init), baseline: segment.baseline).isEmpty)
        guard hasCard else { return groupedBlockCount(items[segment.range]) }

        var above = 0
        for index in body.indices[..<boundary] {
            switch body[index] {
            case .agentMessage: above += 1
            case .turnCost where index < firstReply: above += 1
            default: break
            }
        }
        var below = 0
        var index = body.endIndex
        scan: while index > boundary {
            index -= 1
            switch body[index] {
            case .fileChange(_, let changes, _, _) where changes.isEmpty:
                continue
            case .turnCost:
                below += 1
            case .agentMessage:
                below += 1
                break scan
            default:
                break scan
            }
        }
        // 起点の入力・上の文章・カード・下の返答と使用量（どれもコマンドではないので 1 件 1 ブロック）。
        return 1 + above + 1 + below
    }

    /// 基準と一度でも違ったタスクのうち、区間の最後のスナップショットにあるもの（D8）。
    private static func shownTasks(_ snapshots: [Snapshot], baseline: Snapshot?) -> [AgentTaskItem] {
        var baseByID: [String: AgentTaskItem] = [:]
        for task in baseline?.tasks ?? [] where baseByID[task.id] == nil { baseByID[task.id] = task }
        var changed = Set<String>()
        for snapshot in snapshots {
            for task in snapshot.tasks where baseByID[task.id] != task { changed.insert(task.id) }
        }
        return (snapshots.last?.tasks ?? []).filter { changed.contains($0.id) }
    }

    /// `ChatTranscriptGrouping.blocks(from:).count` と同じ数（連続するコマンドは 1 ブロック）を、配列を作らずに数える。
    private static func groupedBlockCount<Items: Sequence>(_ items: Items) -> Int where Items.Element == ChatItem {
        var count = 0
        var inCommandRun = false
        for item in items {
            if case .commandExecution = item {
                if !inCommandRun { count += 1 }
                inCommandRun = true
            } else {
                count += 1
                inCommandRun = false
            }
        }
        return count
    }

    /// 最新のカードの見出し（グリッドの小さいタイルが使う）。最後の入力の区間と、その直前のタスクの
    /// スナップショット（基準）だけで組み立てるので、長い会話でも全件を走査しない。
    static func latestHeader(items: [ChatItem], liveState: AgentStatusLiveState) -> AgentStatusHeader? {
        guard let start = items.lastIndex(where: { if case .userMessage = $0 { true } else { false } }) else { return nil }
        let baseline = items[..<start].last(where: { Snapshot($0) != nil })
        let tail = (baseline.map { [$0] } ?? []) + items[start...]
        for case .statusCard(let card) in build(items: tail, liveState: liveState) { return card.header }
        return nil
    }

    // MARK: - 区間

    struct Snapshot {
        let tasks: [AgentTaskItem]
        let at: Date
        let isLegacy: Bool

        init?(_ item: ChatItem) {
            guard case .taskList(let id, let tasks, let at) = item else { return nil }
            self.tasks = tasks
            self.at = at
            isLegacy = id == AgentStatusCardBuilder.legacyTaskListID
        }

        /// この時点で作業を属させるタスク。進行中がちょうど 1 件のときだけ。固定 id の 1 枚は最後の状態しか
        /// 持たないので、経過の根拠にしない（FR-22。作業はタスク外にまとめる）。
        var owner: String? {
            guard !isLegacy else { return nil }
            let inProgress = tasks.filter { $0.status == .inProgress }
            return inProgress.count == 1 ? inProgress[0].id : nil
        }
    }

    /// 1 つの入力の区間について、作業の行を作る前に決まること（カードの有無・上・下・ブロック数）。
    /// 窓の外の区間はここまでで止め、隠れ件数だけに使う。
    private struct SegmentPlan {
        /// 起点の userMessage から次の入力の直前まで（元のまま）。
        let segment: ArraySlice<ChatItem>
        /// 起点を除いた中身（変更が空の fileChange を除く）。
        let body: [ChatItem]
        let baseline: Snapshot?
        let snapshots: [Snapshot]
        let shown: [AgentTaskItem]
        let running: Bool
        let hasCard: Bool
        /// カードの上に出す body の位置（昇順）。
        let above: [Int]
        let belowStart: Int

        init(_ range: Segment, in items: [ChatItem]) {
            let segment = items[range.range]
            let baseline = range.baseline
            let running = range.running
            self.segment = segment
            self.baseline = baseline
            self.running = running
            // 変更が空の fileChange は作業として数えない（「0 ファイルを編集」にしない）。カードが出ない区間では今のまま出る。
            let body = segment.dropFirst().filter { !AgentStatusCardBuilder.isEmptyFileChange($0) }
            self.body = body
            let snapshots = body.compactMap(Snapshot.init)
            self.snapshots = snapshots

            // 基準（区間に入る直前のスナップショット）と一度でも違ったタスクだけを出す（D8）。
            let shown = AgentStatusCardBuilder.shownTasks(snapshots, baseline: baseline)
            self.shown = shown

            // 思考・作業・タスクがあれば完了後もカードに残す。実行中は返答前なら見出しだけ出す。
            let firstReply = body.firstIndex { if case .agentMessage = $0 { true } else { false } }
            hasCard = !shown.isEmpty || body.contains {
                AgentStatusCardBuilder.isWork($0) || AgentStatusCardBuilder.isNonEmptyReasoning($0)
            } || (running && firstReply == nil)

            // 上: 最初の思考・作業・スナップショットより前の文章。前の入力の使用量（superseded の後に
            // 追記された turnCost）も、最初の返答より前ならカードの中に入れず上に出す（B3 指摘 8）。
            let boundary = body.firstIndex {
                AgentStatusCardBuilder.isWork($0) || AgentStatusCardBuilder.isNonEmptyReasoning($0) || Snapshot($0) != nil
            } ?? body.endIndex
            above = body.indices[..<boundary].filter { index in
                switch body[index] {
                case .agentMessage: true
                case .turnCost: index < (firstReply ?? body.endIndex)
                default: false
                }
            }

            // 下: 末尾の返答候補と使用量は生成中からカード外へ出す。後続作業が来れば途中本文として戻る。
            var belowStart = body.endIndex
            while belowStart > boundary, case .turnCost = body[belowStart - 1] { belowStart -= 1 }
            if belowStart > boundary, case .agentMessage = body[belowStart - 1] { belowStart -= 1 }
            self.belowStart = belowStart
        }

    }

    private static func segmentBlocks(_ plan: SegmentPlan, liveState: AgentStatusLiveState) -> [ChatTranscriptBlock] {
        let segment = plan.segment
        guard case .userMessage(let userID, _, let startedAt, _, let turnEnd) = segment[segment.startIndex] else { return [] }
        guard plan.hasCard else { return ChatTranscriptGrouping.blocks(from: Array(segment)) }
        let (body, baseline, snapshots, shown, running, belowStart) =
            (plan.body, plan.baseline, plan.snapshots, plan.shown, plan.running, plan.belowStart)
        let aboveSet = Set(plan.above)

        // 中: 位置で振り分ける。直前のスナップショット（区間より前の基準を含む）で進行中がちょうど 1 件、
        // かつそのタスクがカードに出るならそのタスク、それ以外はタスク外（D4。時刻は使わない）。
        let shownIndex = Dictionary(shown.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var effective = baseline
        var effectiveOwner = baseline?.owner
        var seenOwnSnapshot = false
        var anchor = outsideAnchor(effective, false, shownIndex)
        var taskEntries: [String: EntryAccumulator] = [:]
        var outsideEntries: [Int: EntryAccumulator] = [:]
        var lastWorkID: String?
        for index in body.indices[..<belowStart] where !aboveSet.contains(index) {
            let item = body[index]
            if let snapshot = Snapshot(item) {
                effective = snapshot
                seenOwnSnapshot = true
                effectiveOwner = snapshot.owner
                anchor = outsideAnchor(effective, seenOwnSnapshot, shownIndex)
                continue
            }
            if isWork(item) { lastWorkID = item.id }
            if let owner = effectiveOwner, shownIndex[owner] != nil {
                let accumulator = taskEntries[owner] ?? EntryAccumulator()
                taskEntries[owner] = accumulator
                accumulator.append(item)
            } else {
                let accumulator = outsideEntries[anchor] ?? EntryAccumulator()
                outsideEntries[anchor] = accumulator
                accumulator.append(item)
            }
        }

        var times: [String: TaskTimes] = [:]
        for snapshot in snapshots where !snapshot.isLegacy {
            for task in snapshot.tasks {
                if times[task.id]?.startedAt == nil, task.status == .inProgress {
                    times[task.id, default: TaskTimes()].startedAt = snapshot.at
                }
                if times[task.id]?.startedAt != nil, times[task.id]?.completedAt == nil, task.status == .completed {
                    times[task.id, default: TaskTimes()].completedAt = snapshot.at
                }
            }
        }
        var rows: [AgentStatusRow] = []
        for position in 0...shown.count {
            if let accumulator = outsideEntries[position] {
                let entries = accumulator.materialize(running: running, turnEnd: turnEnd)
                rows.append(.outside(AgentStatusOutsideGroup(id: "outside-\(entries[0].id)", entries: entries)))
            }
            if position < shown.count {
                let task = shown[position]
                rows.append(.task(makeTask(
                    task, times: times[task.id] ?? TaskTimes(), entries: taskEntries[task.id]?.materialize(running: running, turnEnd: turnEnd) ?? [], running: running, turnEnd: turnEnd
                )))
            }
        }

        let card = AgentStatusCard(
            id: "status-card-\(userID)",
            header: makeHeader(
                // 今の作業は、実行中の作業があるときだけ。終わった作業を「〜中」で出し続けない（見本 10-Anatomy）。
                current: lastWorkID.flatMap { lastAction(containing: $0, in: rows) }.flatMap { $0.isRunning ? $0.label : nil },
                startedAt: startedAt, turnEnd: turnEnd, running: running, liveState: liveState
            ),
            rows: rows,
            changeCounts: AgentStatusChangeCounts(items: segment.dropFirst()).counts
        )
        return ChatTranscriptGrouping.blocks(from: [segment[segment.startIndex]] + plan.above.map { body[$0] })
            + [.statusCard(card)]
            + ChatTranscriptGrouping.blocks(from: Array(body[belowStart...]))
    }

    /// タスク外の作業を出す位置（タスクの行の何番目の前か）。この区間のスナップショットがまだ無い
    /// （タスク登録前）ならタスクの上、それ以外は、その時点で完了しているタスクのうち最後のものの下。
    static func outsideAnchor(_ effective: Snapshot?, _ seenOwnSnapshot: Bool, _ shownIndex: [String: Int]) -> Int {
        guard seenOwnSnapshot, let effective else { return 0 }
        let completed = effective.tasks.filter { $0.status == .completed }.compactMap { shownIndex[$0.id] }
        return completed.max().map { $0 + 1 } ?? 0
    }

    private struct TaskTimes {
        var startedAt: Date?
        var completedAt: Date?
    }

    private static func makeTask(
        _ task: AgentTaskItem, times: TaskTimes, entries: [AgentStatusEntry], running: Bool, turnEnd: ChatTurnEnd?
    ) -> AgentStatusTask {
        let startedAt = times.startedAt
        let completedAt = times.completedAt
        let state: AgentStatusTask.State = switch task.status {
        case .pending: .pending
        case .completed: .completed
        case .inProgress: running ? .inProgress : .interrupted
        }
        let endedAt: Date? = switch state {
        case .completed: completedAt
        case .interrupted: startedAt == nil ? nil : turnEnd?.at
        case .pending, .inProgress: nil
        }
        return AgentStatusTask(
            id: task.id, title: task.title, state: state, startedAt: startedAt, endedAt: endedAt, entries: entries
        )
    }

    static func makeHeader(
        current: AgentStatusAction.Label?, startedAt: Date, turnEnd: ChatTurnEnd?, running: Bool,
        liveState: AgentStatusLiveState
    ) -> AgentStatusHeader {
        // 最新のカードでは、終わり方の記録より実行中を優先する（ADR 0064・FR-5）。
        guard !running else {
            let stalled = liveState.hangAssessment?.isStalled == true
            let state: AgentStatusHeader.State = liveState.isAwaitingReply ? .awaitingReply : stalled ? .stalled : .running
            return AgentStatusHeader(
                state: state, current: current, activityState: current == nil ? liveState.activityState : nil,
                startedAt: startedAt, endedAt: nil, silence: state == .stalled ? liveState.hangAssessment?.silence : nil
            )
        }
        let state: AgentStatusHeader.State = switch turnEnd?.outcome {
        case .completed: .completed
        case .interrupted: .interrupted
        case .error: .error
        case .superseded: .superseded
        case nil: .ended
        }
        return AgentStatusHeader(
            state: state, current: nil, activityState: nil, startedAt: startedAt, endedAt: turnEnd?.at, silence: nil
        )
    }

    private static func lastAction(containing itemID: String, in rows: [AgentStatusRow]) -> AgentStatusAction? {
        for row in rows {
            let entries = switch row {
            case .task(let task): task.entries
            case .outside(let group): group.entries
            }
            for case .action(let action) in entries where action.items.contains(where: { $0.id == itemID }) {
                return action
            }
        }
        return nil
    }

    // MARK: - 作業の行

    static func isWork(_ item: ChatItem) -> Bool {
        switch item {
        case .commandExecution, .fileChange, .subAgentMarker: true
        default: false
        }
    }

    static func isNonEmptyReasoning(_ item: ChatItem) -> Bool {
        if case .reasoning(_, let text, _) = item {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    static func isEmptyFileChange(_ item: ChatItem) -> Bool {
        if case .fileChange(_, let changes, _, _) = item { changes.isEmpty } else { false }
    }

    /// まとめてよい種類（読み込み・検索・編集）。それ以外は nil（実行・書き込み・その他はまとめない）。
    enum MergeKind { case read, search, edit }

    static func mergeKind(_ item: ChatItem) -> MergeKind? {
        switch item {
        case .commandExecution(_, let command, _, _, _, let intent) where intent == nil:
            switch ChatCommandToolLabel.derive(command: command).label {
            case "Read", "LS": return .read
            case "Grep", "Glob", "WebSearch", "WebFetch": return .search
            default: return nil
            }
        case .fileChange(_, let changes, _, _):
            return isWrite(changes) ? nil : .edit
        default:
            return nil
        }
    }

    private static func isWrite(_ changes: [FilePatchChange]) -> Bool {
        !changes.isEmpty && changes.allSatisfy { $0.kind == "write" }
    }

    private final class EntryAccumulator {
        enum Entry {
            case item(ChatItem)
            case action(ActionAccumulator)
        }
        var entries: [Entry] = []

        func append(_ item: ChatItem) {
            guard isWork(item) else { entries.append(.item(item)); return }
            if let kind = mergeKind(item), case .action(let last)? = entries.last,
               mergeKind(last.items[0]) == kind {
                last.append(item)
            } else {
                let action = ActionAccumulator()
                action.append(item)
                entries.append(.action(action))
            }
        }

        func materialize(running: Bool, turnEnd: ChatTurnEnd?) -> [AgentStatusEntry] {
            entries.map {
                switch $0 {
                case .item(let item): .item(item)
                case .action(let action): .action(action.materialize(running: running, turnEnd: turnEnd))
                }
            }
        }
    }

    final class ActionAccumulator: @unchecked Sendable {
        private(set) var items: [ChatItem] = []
        private var positions: [String: Int] = [:]
        private var files: [String: Int] = [:]
        private var hits = 0
        private(set) var nonBlankOutputCount = 0
        private var states: [AgentStatusWorkState: Int] = [:]
        private var completions: [String: Date] = [:]
        private var latestCompletion: Date?

        init(items: [ChatItem] = []) {
            for item in items { append(item) }
        }

        func append(_ item: ChatItem) {
            if positions[item.id] != nil { replace(item); return }
            positions[item.id] = items.count
            items.append(item)
            contribute(item, sign: 1)
        }

        func index(ofItemID id: String) -> Int? { positions[id] }

        func replace(_ item: ChatItem) {
            guard let index = positions[item.id] else { return }
            let completionChanged = completionDate(items[index]) != completionDate(item)
            contribute(items[index], sign: -1, updateCompletion: completionChanged)
            items[index] = item
            contribute(item, sign: 1, updateCompletion: completionChanged)
        }

        private func completionDate(_ item: ChatItem) -> Date? {
            switch item {
            case .commandExecution(_, _, _, _, let at, _), .fileChange(_, _, _, let at): at
            default: nil
            }
        }

        private func contribute(_ item: ChatItem, sign: Int, updateCompletion: Bool = true) {
            let paths: [String]
            let state: AgentStatusWorkState
            var completion: Date?
            switch item {
            case .commandExecution(_, let command, let output, _, let at, _):
                let derived = ChatCommandToolLabel.derive(command: command)
                paths = mergeKind(item) == .read ? [fileName(derived.body)] : []
                if mergeKind(item) == .search { hits += sign * hitCount(output) }
                if output.contains(where: { !$0.isWhitespace }) { nonBlankOutputCount += sign }
                completion = at
                state = at == nil ? .running : .completed
            case .fileChange(_, let changes, _, let at):
                paths = changes.map(\.path)
                completion = at
                state = at == nil ? .running : .completed
            case .subAgentMarker(_, _, _, let status):
                paths = []
                state = switch status {
                case .running: .running
                case .completed: .completed
                case .failed: .failed
                case .stopped: .interrupted
                }
            default: return
            }
            for path in paths {
                files[path, default: 0] += sign
                if files[path] == 0 { files.removeValue(forKey: path) }
            }
            states[state, default: 0] += sign
            guard updateCompletion else { return }
            if sign > 0, let completion {
                completions[item.id] = completion
                latestCompletion = max(latestCompletion ?? completion, completion)
            } else if sign < 0, let removed = completions.removeValue(forKey: item.id), removed == latestCompletion {
                latestCompletion = completions.values.max()
            }
        }

        func materialize(running: Bool, turnEnd: ChatTurnEnd?) -> AgentStatusAction {
            AgentStatusAction(items: items, label: resolvedLabel(running: running, turnEnd: turnEnd),
                state: state(running: running, turnEnd: turnEnd), duration: duration)
        }

        func resolvedLabel(running: Bool, turnEnd: ChatTurnEnd?) -> AgentStatusAction.Label {
            if case .subAgent(let description, let type, .running) = label,
               state(running: running, turnEnd: turnEnd) == .interrupted {
                return .subAgent(description: description, type: type, status: .stopped)
            }
            return label
        }

        var duration: TimeInterval? {
            guard completions.count == items.count, let first = items.first,
                  first.timestamp != .distantPast, let latestCompletion else { return nil }
            return latestCompletion.timeIntervalSince(first.timestamp)
        }

        func state(running: Bool, turnEnd: ChatTurnEnd?) -> AgentStatusWorkState {
            let unfinished: AgentStatusWorkState
            if running { unfinished = .running }
            else {
                unfinished = switch turnEnd?.outcome {
                case .interrupted, .error, .superseded: .interrupted
                case .completed, nil: .unknown
                }
            }
            return .aggregate(states.compactMap { state, count in
                count > 0 ? (state == .running ? unfinished : state) : nil
            })
        }

        var label: AgentStatusAction.Label {
            guard let first = items.first else { return .command("") }
            switch first {
            case .subAgentMarker(_, let type, let description, let status):
                return .subAgent(description: description, type: type, status: status)
            case .fileChange(_, let changes, _, _) where isWrite(changes):
                return .write(file: fileName(changes[0].path))
            case .fileChange:
                // 実行中の対象名は、完了済み編集との集約で失わない。
                var activeFiles: [String] = []
                for case .fileChange(_, let changes, _, nil) in items {
                    for change in changes where !activeFiles.contains(change.path) { activeFiles.append(change.path) }
                }
                if !activeFiles.isEmpty { return .edit(file: activeFiles.map(fileName).joined(separator: ", ")) }
                return files.count == 1 ? .edit(file: fileName(files.keys.first!)) : .editFiles(count: files.count)
            case .commandExecution(_, let command, _, _, _, let intent):
                if let intent { return .run(intent: intent) }
                let (tool, body) = ChatCommandToolLabel.derive(command: command)
                switch mergeKind(first) {
                case .read: return .read(file: fileName(body), more: max(0, files.count - 1))
                case .search: return items.count == 1 ? .search(query: body, hits: hits) : .searches(times: items.count, hits: hits)
                case .edit, nil: return tool == "Bash" ? .command(unwrappingShell(body)) : .tool(tool)
                }
            default: return .command("")
            }
        }
    }

    /// 検索の結果の件数。Claude の Grep・Glob は見出し（「Found 3 files」「Found 40 files limit: 40」
    /// 「No files found」「No matches found」）や末尾の注記（ページ送り・打ち切り）を付けるので、それは数えない。
    /// 見出しに件数があればそれを使い、無ければ空でない行を数える（B3 指摘 4。実際の結果の形は
    /// ~/.claude/projects の会話記録で確かめた）。
    private static func hitCount(_ output: String) -> Int {
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return 0 }
        if first.hasPrefix("No "), first.hasSuffix(" found") { return 0 }
        if first.hasPrefix("Found "), let count = Int(first.dropFirst("Found ".count).prefix(while: \.isNumber)) {
            return count
        }
        let notes = ["[Showing results with pagination", "(Results are truncated", "[result-id:"]
        return lines.filter { line in !notes.contains { line.hasPrefix($0) } }.count
    }

    /// Codex のコマンドは `/bin/zsh -lc '…'` の包みごと届く。包みを外して、中身を元のコマンドとして読める形で出す。
    /// 中身は 1 つのシェルの語（引用の連結を含む。`"…"'…'"…"`）なので、引用を解く。
    /// 1 語として読めない（引用が閉じない・引用の外に空白がある）ときは、元のまま出す。
    private static func unwrappingShell(_ command: String) -> String {
        let parts = command.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard parts.count == 3,
              ["zsh", "bash", "sh"].contains((String(parts[0]) as NSString).lastPathComponent),
              ["-c", "-lc"].contains(String(parts[1])),
              let word = unquotedShellWord(parts[2].trimmingCharacters(in: .whitespacesAndNewlines))
        else { return command }
        return word
    }

    /// POSIX シェルの 1 語の引用を解く。単引用符は中身そのまま、二重引用符の中の `\` は `$` `` ` `` `"` `\` の前だけ外す。
    /// ponytail: 展開（`$`・`` ` ``）は評価しない。
    private static func unquotedShellWord(_ text: String) -> String? {
        let chars = Array(text)
        var result = ""
        var index = 0
        while index < chars.count {
            let char = chars[index]
            index += 1
            switch char {
            case "'":
                guard let close = chars[index...].firstIndex(of: "'") else { return nil }
                result.append(contentsOf: chars[index..<close])
                index = close + 1
            case "\"":
                var closed = false
                while index < chars.count {
                    let inner = chars[index]
                    index += 1
                    if inner == "\"" { closed = true; break }
                    if inner == "\\", index < chars.count, "$`\"\\".contains(chars[index]) {
                        result.append(chars[index])
                        index += 1
                    } else {
                        result.append(inner)
                    }
                }
                if !closed { return nil }
            case "\\":
                guard index < chars.count else { return nil }
                result.append(chars[index])
                index += 1
            case _ where char.isWhitespace:
                return nil
            default:
                result.append(char)
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func fileName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}

/// どの会話でカードを使うか、使う会話のブロック列をどう作るか（設計 §4.1「適用範囲」）。
/// Claude と Codex だけがカードの組み立てを使い、Cursor は今の `ChatTranscriptGrouping.blocks` のまま（AC-14）。
enum AgentStatusCardRouting {
    static func usesStatusCard(_ agent: AgentKind) -> Bool {
        switch agent {
        case .claudeCode, .codex: true
        case .cursor: false
        }
    }

    static func blocks(items: [ChatItem], agent: AgentKind, liveState: AgentStatusLiveState) -> [ChatTranscriptBlock] {
        usesStatusCard(agent)
            ? AgentStatusCardBuilder.build(items: items, liveState: liveState)
            : ChatTranscriptGrouping.blocks(from: items)
    }
}

extension AgentStatusCard {
    /// カードの中にこの id の item があるか（ジャンプ先をカードの id へ解決するため）。
    func contains(itemID: String) -> Bool {
        entryID(containing: itemID) != nil
    }

    /// この item を含む作業の行（または item）の id。開いた行の中のその位置へ移動するために使う。
    func entryID(containing itemID: String) -> String? {
        for row in rows {
            if let entry = row.entries.first(where: { $0.contains(itemID: itemID) }) { return entry.id }
        }
        return nil
    }
}

extension ChatSessionViewModel {
    /// 組み立てへ渡す実行中の状態。承認・質問待ちも、今の処理中表示と同じく実行中に数える。
    /// 無応答の判定は時刻で変わるので渡さない（見出しが表示の時計から決める）。
    var statusCardLiveState: AgentStatusLiveState {
        let activity = activityState
        return AgentStatusLiveState(
            isProcessing: showsProcessingIndicator || activity == .waiting,
            activityState: activity ?? .thinking,
            hangAssessment: nil,
            isAwaitingReply: activity == .waiting
        )
    }
}
