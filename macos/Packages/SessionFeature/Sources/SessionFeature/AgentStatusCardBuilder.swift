import Foundation
import AgentDomain
import ChatRenderKit
import DesignSystem
import StructuredChatKit

// エージェント状態カード（agent-status-card-design.md §4、ADR 0226）。
// 会話ログから入力 1 回ごとのカードを、表示のたびに組み立てる。カードは保存しない。

/// 組み立てに使う、実行中の状態。
struct AgentStatusLiveState: Equatable {
    /// `showsProcessingIndicator`（バックグラウンドタスク・サブエージェントが動く間も true）。
    var isProcessing: Bool
    var activityState: AgentActivityState
    var hangAssessment: ChatHangAssessment?
    var isAwaitingReply: Bool
}

struct AgentStatusCard: Identifiable, Equatable {
    /// `status-card-<起点の userMessage の id>`。
    let id: String
    let header: AgentStatusHeader
    /// タスクの行とタスク外の作業の行。タスクは最新のスナップショットの順、タスク外は時系列の位置。
    let rows: [AgentStatusRow]
}

/// 見出し（1 行目）。経過は表示側が `startedAt` と今の時刻から数える（実行中でないカードは時刻で変わらない）。
struct AgentStatusHeader: Equatable {
    enum State: Equatable {
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

enum AgentStatusRow: Identifiable, Equatable {
    case task(AgentStatusTask)
    case outside(AgentStatusOutsideGroup)

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id)"
        case .outside(let group): group.id
        }
    }
}

struct AgentStatusTask: Identifiable, Equatable {
    enum State: Equatable {
        case pending
        case inProgress
        case completed
        /// 進行中のままカードが終わった（中断・エラー・次の入力へ続く・終了）。
        case interrupted
    }

    let id: String
    let title: String
    let state: State
    /// この入力の中で最初に進行中として現れたスナップショットの時刻。
    let startedAt: Date?
    /// 完了：最初に完了として現れた時刻。中断：入力の終わった時刻。それ以外は nil。
    let endedAt: Date?
    let entries: [AgentStatusEntry]
}

struct AgentStatusOutsideGroup: Identifiable, Equatable {
    let id: String
    let entries: [AgentStatusEntry]
}

/// カードの中の 1 件。作業の行か、そのまま出す item（文章・思考・質問・エラーなど）。
enum AgentStatusEntry: Identifiable, Equatable {
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
struct AgentStatusAction: Identifiable, Equatable {
    enum Label: Equatable {
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
                return running ? format("%@中", intent) : intent
            case .command(let command):
                let shown = command.isEmpty
                    ? UIWording.text(.missingCommand, languageCode: locale.language.languageCode?.identifier ?? "ja")
                    : command
                return running ? format("%@ を実行中", shown) : shown
            case .tool(let name):
                return format(running ? "%@ を実行中" : "%@ を実行", name)
            case .subAgent(let description, _, _):
                return description.isEmpty
                    ? UIWording.text(.missingSubAgentDescription, languageCode: locale.language.languageCode?.identifier ?? "ja")
                    : description
            }
        }
    }

    /// まとめた元の item（開いたときに今のツールカードの中身を出す）。
    let items: [ChatItem]
    let label: Label
    let isRunning: Bool
    /// 開始から結果が届くまで。結果の時刻が無い（実行中・旧記録・サブエージェント）なら nil。
    let duration: TimeInterval?

    var id: String { items[0].id }

    func text(locale: Locale, bundle: Bundle = .main) -> String {
        label.text(running: isRunning, locale: locale, bundle: bundle)
    }
}

/// 時間の書き方（要件 FR-4、見本 10-Anatomy）。
enum AgentStatusDurationFormat {
    /// 見出しとタスク: m:ss、1 時間以上は h:mm:ss。60 秒未満も 0:09。
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// 作業の行: 10 秒未満は 1.9s、60 秒未満は 14s、それ以上は m:ss。
    static func action(_ seconds: TimeInterval) -> String {
        if seconds < 10 { return String(format: "%.1fs", max(0, seconds)) }
        if seconds < 60 { return "\(Int(seconds))s" }
        return clock(seconds)
    }
}

extension AgentStatusDurationFormat {
    /// VoiceOver 用。13 秒、1 分 20 秒、1 時間 2 分。
    /// `fractional`: 10 秒未満を 0.6 秒のように小数で読む（作業の行）。
    static func spoken(_ seconds: TimeInterval, locale: Locale, bundle: Bundle = .main, fractional: Bool = false) -> String {
        func format(_ key: String, _ arguments: CVarArg...) -> String {
            String(format: AppLocalizedString.string(key, locale: locale, bundle: bundle), arguments: arguments)
        }
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
        var hasWork = false
        var hasSnapshot = false
        for index in body.indices {
            switch body[index] {
            case .fileChange(_, let changes, _, _) where changes.isEmpty:
                continue
            case .commandExecution, .fileChange, .subAgentMarker:
                hasWork = true
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
        let hasCard = hasWork || (segment.running && firstReply == body.endIndex)
            || (hasSnapshot && !shownTasks(body.compactMap(Snapshot.init), baseline: segment.baseline).isEmpty)
        guard hasCard else { return groupedBlockCount(items[segment.range]) }

        var above = 0
        for index in body.indices[..<boundary] {
            switch body[index] {
            case .agentMessage, .reasoning: above += 1
            case .turnCost where index < firstReply: above += 1
            default: break
            }
        }
        var below = 0
        if !segment.running {
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

    private struct Snapshot {
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

            // 作業もタスクも無ければカードを出さない。実行中は、返答が届き始めるまで見出しだけのカードを出す（FR-2）。
            let firstReply = body.firstIndex { if case .agentMessage = $0 { true } else { false } }
            hasCard = !shown.isEmpty || body.contains(where: AgentStatusCardBuilder.isWork) || (running && firstReply == nil)

            // 上: 最初の作業・スナップショットより前の文章と思考。前の入力の使用量（superseded の後に
            // 追記された turnCost）も、最初の返答より前ならカードの中に入れず上に出す（B3 指摘 8）。
            let boundary = body.firstIndex { AgentStatusCardBuilder.isWork($0) || Snapshot($0) != nil } ?? body.endIndex
            above = body.indices[..<boundary].filter { index in
                switch body[index] {
                case .agentMessage, .reasoning: true
                case .turnCost: index < (firstReply ?? body.endIndex)
                default: false
                }
            }

            // 下: 実行中でないカードの、末尾の使用量と、その直前の最後の返答（FR-18）。終わり方の記録が
            // 無い入力（古い会話・アプリの終了）でも同じ（2026-11-07 ユーザー決定。返答を閉じたカードに隠さない）。
            var belowStart = body.endIndex
            if !running {
                while belowStart > boundary, case .turnCost = body[belowStart - 1] { belowStart -= 1 }
                if belowStart > boundary, case .agentMessage = body[belowStart - 1] { belowStart -= 1 }
            }
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
        var seenOwnSnapshot = false
        var taskEntries: [String: [AgentStatusEntry]] = [:]
        var outsideEntries: [Int: [AgentStatusEntry]] = [:]
        var lastWorkID: String?
        for index in body.indices[..<belowStart] where !aboveSet.contains(index) {
            let item = body[index]
            if let snapshot = Snapshot(item) {
                effective = snapshot
                seenOwnSnapshot = true
                continue
            }
            if isWork(item) { lastWorkID = item.id }
            if let owner = effective?.owner, shownIndex[owner] != nil {
                append(item, to: &taskEntries[owner, default: []], running: running)
            } else {
                append(item, to: &outsideEntries[outsideAnchor(effective, seenOwnSnapshot, shownIndex), default: []], running: running)
            }
        }

        var rows: [AgentStatusRow] = []
        for position in 0...shown.count {
            if let entries = outsideEntries[position] {
                rows.append(.outside(AgentStatusOutsideGroup(id: "outside-\(entries[0].id)", entries: entries)))
            }
            if position < shown.count {
                let task = shown[position]
                rows.append(.task(makeTask(
                    task, snapshots: snapshots, entries: taskEntries[task.id] ?? [], running: running, turnEnd: turnEnd
                )))
            }
        }

        let card = AgentStatusCard(
            id: "status-card-\(userID)",
            header: makeHeader(
                current: lastWorkID.flatMap { lastAction(containing: $0, in: rows) }?.label,
                startedAt: startedAt, turnEnd: turnEnd, running: running, liveState: liveState
            ),
            rows: rows
        )
        return ChatTranscriptGrouping.blocks(from: [segment[segment.startIndex]] + plan.above.map { body[$0] })
            + [.statusCard(card)]
            + ChatTranscriptGrouping.blocks(from: Array(body[belowStart...]))
    }

    /// タスク外の作業を出す位置（タスクの行の何番目の前か）。この区間のスナップショットがまだ無い
    /// （タスク登録前）ならタスクの上、それ以外は、その時点で完了しているタスクのうち最後のものの下。
    private static func outsideAnchor(_ effective: Snapshot?, _ seenOwnSnapshot: Bool, _ shownIndex: [String: Int]) -> Int {
        guard seenOwnSnapshot, let effective else { return 0 }
        let completed = effective.tasks.filter { $0.status == .completed }.compactMap { shownIndex[$0.id] }
        return completed.max().map { $0 + 1 } ?? 0
    }

    private static func makeTask(
        _ task: AgentTaskItem, snapshots: [Snapshot], entries: [AgentStatusEntry], running: Bool, turnEnd: ChatTurnEnd?
    ) -> AgentStatusTask {
        var startedAt: Date?
        var completedAt: Date?
        for snapshot in snapshots where !snapshot.isLegacy {
            guard let status = snapshot.tasks.first(where: { $0.id == task.id })?.status else { continue }
            if startedAt == nil, status == .inProgress { startedAt = snapshot.at }
            if startedAt != nil, completedAt == nil, status == .completed { completedAt = snapshot.at }
        }
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

    private static func makeHeader(
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

    fileprivate static func isWork(_ item: ChatItem) -> Bool {
        switch item {
        case .commandExecution, .fileChange, .subAgentMarker: true
        default: false
        }
    }

    fileprivate static func isEmptyFileChange(_ item: ChatItem) -> Bool {
        if case .fileChange(_, let changes, _, _) = item { changes.isEmpty } else { false }
    }

    /// まとめてよい種類（読み込み・検索・編集）。それ以外は nil（実行・書き込み・その他はまとめない）。
    private enum MergeKind { case read, search, edit }

    private static func mergeKind(_ item: ChatItem) -> MergeKind? {
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

    /// 文章などは item のまま足す。作業は、直前の行が同じまとめられる種類なら 1 行にまとめる。
    private static func append(_ item: ChatItem, to entries: inout [AgentStatusEntry], running: Bool) {
        guard isWork(item) else {
            entries.append(.item(item))
            return
        }
        if let kind = mergeKind(item), case .action(let last)? = entries.last, mergeKind(last.items[0]) == kind {
            entries[entries.count - 1] = .action(makeAction(last.items + [item], running: running))
        } else {
            entries.append(.action(makeAction([item], running: running)))
        }
    }

    private static func makeAction(_ items: [ChatItem], running: Bool) -> AgentStatusAction {
        var completions: [Date] = []
        var unfinished = false
        for item in items {
            switch item {
            case .commandExecution(_, _, _, _, let completedAt, _), .fileChange(_, _, _, let completedAt):
                if let completedAt { completions.append(completedAt) } else { unfinished = true }
            case .subAgentMarker(_, _, _, let status):
                unfinished = unfinished || status == .running
            default:
                break
            }
        }
        // 時刻を持たないサブエージェント（.distantPast）と、結果の時刻が無い作業は所要時間を出さない。
        let duration: TimeInterval? = !unfinished && completions.count == items.count
            ? completions.max().map { $0.timeIntervalSince(items[0].timestamp) }
            : nil
        return AgentStatusAction(
            items: items, label: label(for: items),
            // 終わったカードでは、結果の時刻が無くても「〜中」にしない（旧会話・中断した作業）。
            isRunning: running && unfinished, duration: duration
        )
    }

    private static func label(for items: [ChatItem]) -> AgentStatusAction.Label {
        switch items[0] {
        case .subAgentMarker(_, let type, let description, let status):
            return .subAgent(description: description, type: type, status: status)
        case .fileChange(_, let changes, _, _) where isWrite(changes):
            return .write(file: fileName(changes[0].path))
        case .fileChange:
            var paths: [String] = []
            for case .fileChange(_, let changes, _, _) in items {
                for change in changes where !paths.contains(change.path) { paths.append(change.path) }
            }
            return paths.count == 1 ? .edit(file: fileName(paths[0])) : .editFiles(count: paths.count)
        case .commandExecution(_, let command, _, _, _, let intent):
            if let intent { return .run(intent: intent) }
            let (tool, body) = ChatCommandToolLabel.derive(command: command)
            switch mergeKind(items[0]) {
            case .read:
                var files: [String] = []
                for case .commandExecution(_, let command, _, _, _, _) in items {
                    let file = fileName(ChatCommandToolLabel.derive(command: command).body)
                    if !files.contains(file) { files.append(file) }
                }
                return .read(file: files[0], more: files.count - 1)
            case .search:
                let hits = items.reduce(0) { total, item in
                    guard case .commandExecution(_, _, let output, _, _, _) = item else { return total }
                    return total + hitCount(output)
                }
                return items.count == 1 ? .search(query: body, hits: hits) : .searches(times: items.count, hits: hits)
            case .edit, nil:
                return tool == "Bash" ? .command(body) : .tool(tool)
            }
        default:
            return .command("")
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
