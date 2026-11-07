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
        let starts = items.indices.filter { if case .userMessage = items[$0] { true } else { false } }
        guard let first = starts.first else { return ChatTranscriptGrouping.blocks(from: items) }

        var blocks = ChatTranscriptGrouping.blocks(from: Array(items[..<first]))
        var baseline = items[..<first].last(where: { Snapshot($0) != nil }).flatMap(Snapshot.init)
        for (number, start) in starts.enumerated() {
            let end = number + 1 < starts.count ? starts[number + 1] : items.endIndex
            let segment = Array(items[start..<end])
            blocks += segmentBlocks(
                segment, baseline: baseline,
                isRunning: number == starts.count - 1 && liveState.isProcessing, liveState: liveState
            )
            if let last = segment.last(where: { Snapshot($0) != nil }) { baseline = Snapshot(last) }
        }
        return blocks
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

    private static func segmentBlocks(
        _ segment: [ChatItem], baseline: Snapshot?, isRunning running: Bool, liveState: AgentStatusLiveState
    ) -> [ChatTranscriptBlock] {
        guard case .userMessage(let userID, _, let startedAt, _, let turnEnd) = segment[0] else { return [] }
        // 変更が空の fileChange は作業として数えない（「0 ファイルを編集」にしない）。カードが出ない区間では今のまま出る。
        let body = segment.dropFirst().filter { !isEmptyFileChange($0) }
        let snapshots = body.compactMap(Snapshot.init)

        // 基準（区間に入る直前のスナップショット）と一度でも違ったタスクだけを出す（D8）。
        var baseByID: [String: AgentTaskItem] = [:]
        for task in baseline?.tasks ?? [] where baseByID[task.id] == nil { baseByID[task.id] = task }
        var changed = Set<String>()
        for snapshot in snapshots {
            for task in snapshot.tasks where baseByID[task.id] != task { changed.insert(task.id) }
        }
        let shown = (snapshots.last?.tasks ?? []).filter { changed.contains($0.id) }

        // 作業もタスクも無ければカードを出さない。実行中は、返答が届き始めるまで見出しだけのカードを出す（FR-2）。
        let hasWork = body.contains(where: isWork)
        let hasReply = body.contains { if case .agentMessage = $0 { true } else { false } }
        guard !shown.isEmpty || hasWork || (running && !hasReply) else {
            return ChatTranscriptGrouping.blocks(from: segment)
        }

        // 上: 最初の作業・スナップショットより前の文章と思考。
        let boundary = body.firstIndex { isWork($0) || Snapshot($0) != nil } ?? body.endIndex
        let isAbove: (Int) -> Bool = { index in
            guard index < boundary else { return false }
            switch body[index] {
            case .agentMessage, .reasoning: return true
            default: return false
            }
        }

        // 下: 実行中でないカードの、末尾の使用量と、その直前の最後の返答（FR-18）。終わり方の記録が
        // 無い入力（古い会話・アプリの終了）でも同じ（2026-11-07 ユーザー決定。返答を閉じたカードに隠さない）。
        var belowStart = body.endIndex
        if !running {
            while belowStart > boundary, case .turnCost = body[belowStart - 1] { belowStart -= 1 }
            if belowStart > boundary, case .agentMessage = body[belowStart - 1] { belowStart -= 1 }
        }

        // 中: 位置で振り分ける。直前のスナップショット（区間より前の基準を含む）で進行中がちょうど 1 件、
        // かつそのタスクがカードに出るならそのタスク、それ以外はタスク外（D4。時刻は使わない）。
        let shownIndex = Dictionary(shown.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var effective = baseline
        var seenOwnSnapshot = false
        var taskEntries: [String: [AgentStatusEntry]] = [:]
        var outsideEntries: [Int: [AgentStatusEntry]] = [:]
        var lastWorkID: String?
        for index in body.indices[..<belowStart] where !isAbove(index) {
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
        let above = body.indices.filter(isAbove).map { body[$0] }
        return ChatTranscriptGrouping.blocks(from: [segment[0]] + above)
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

    private static func isWork(_ item: ChatItem) -> Bool {
        switch item {
        case .commandExecution, .fileChange, .subAgentMarker: true
        default: false
        }
    }

    private static func isEmptyFileChange(_ item: ChatItem) -> Bool {
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
                    return total + output.split(whereSeparator: \.isNewline)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                }
                return items.count == 1 ? .search(query: body, hits: hits) : .searches(times: items.count, hits: hits)
            case .edit, nil:
                return tool == "Bash" ? .command(body) : .tool(tool)
            }
        default:
            return .command("")
        }
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
        rows.contains { row in
            row.entries.contains { entry in
                switch entry {
                case .action(let action): action.items.contains { $0.id == itemID }
                case .item(let item): item.id == itemID
                }
            }
        }
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
