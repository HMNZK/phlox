import SwiftUI
import DesignSystemIOS
import PhloxCore
import PhloxNetworking
import ImageAttachmentKit
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// セッション詳細（カンプ③ / E4-6）+ 送信（カンプ⑦ / E4-8）。
/// 入力は送信受付後にだけクリアし、送信中の編集を保持する。
@MainActor
@Observable
public final class SessionDetailViewModel {
    public enum SendState: Equatable {
        case idle
        case sending
        case failed(String)
    }

    /// 添付上限（契約 §5 / ComposerAttachments と同一）。
    static let maxAttachmentCount = ImageAttachmentLimits.maxCount
    static let maxAttachmentBytesPerImage = ImageAttachmentLimits.maxInputBytes
    static let maxAttachmentTotalBytes = ImageAttachmentLimits.maxTotalInputBytes

    private let api: PhloxAPI
    public private(set) var session: Session
    public private(set) var currentStatus: SessionStatus {
        didSet { syncThinkingStartedAt(from: oldValue) }
    }
    /// task-4: `currentStatus` が `.running` になった時刻。running を外れたら nil。
    public private(set) var thinkingStartedAt: Date?
    /// 入力欄の本文。**本文編集を添付へ同期するのは View 側の `.onChange` から
    /// `syncAttachmentsWithTextEdit(oldText:newText:)` を呼ぶ**（macOS と同じ形）。
    /// `didSet` の中から自分自身へ書き戻すと、SwiftUI の `TextField` がその更新を
    /// 取り込まず、モデルと画面の本文がずれる（実機・シミュレータで確認）。
    public var inputText: String = "" {
        didSet { if inputText != oldValue { inputRevision &+= 1 } }
    }
    @ObservationIgnored private var inputRevision: UInt64 = 0

    /// task-3 契約の PM スタブ。入力欄のカーソル位置（UTF-16 オフセット）。
    /// View が書き込み、添付時のプレースホルダ挿入位置として使う。
    public var inputCursorUTF16: Int = 0
    /// 初回の messages 解決まで true。ポーリング更新では再点灯しない。
    public private(set) var isInitialLoading: Bool = true
    public private(set) var chatMessages: [ChatMessage] = [] {
        didSet { reconcileAttachments() }
    }
    public private(set) var attachmentCountsByMessageID: [String: Int] = [:]
    private var pendingAttachmentSends: [SessionAttachmentReconciler.Pending] = []
    /// reasoning / command / fileChange 行の展開状態（message.id キー。ポーリング差し替え後も保持）。
    public private(set) var expandedMessageIDs: Set<String> = []
    public private(set) var sendState: SendState = .idle
    public private(set) var loadError: String?
    /// task-9: 実行中ターンの停止が可能か（interrupt 非対応=409 を観測したら false にして停止 UI を隠す）。
    public private(set) var canInterrupt: Bool = true
    /// task-9: 直近ターンのコスト・コンテキスト使用量（ターン完了時に取得。未取得は nil）。
    public private(set) var turnUsage: TurnUsage?

    /// messagesDelta の since 引き渡し用 cursor（差分ポーリング）。
    private var messagesCursor: String?
    /// markerMessageID → subAgentID（行タップ可否の判定用。取得失敗時は空のまま）。
    private var subAgentMarkerIndex: [String: String] = [:]

    /// task-10: 送信に添付する画像（最大4枚・1枚4MiB・計8MiB）とストリップ用プレビュー。
    public private(set) var attachmentItems: [SessionAttachmentItem] = []
    /// 受け入れテスト互換の送信ペイロード参照面。
    public var attachments: [SendAttachment] { attachmentItems.map(\.send) }
    /// task-10: 添付の上限超過などの弾いた理由（表示用。無ければ nil）。
    public private(set) var attachmentError: String?
    /// task-6: モデル選択チップ用の設定。取得失敗・空一覧は nil（チップ非表示）。
    public private(set) var modelSettings: SessionModelSettings?
    private enum MenuPresentation {
        case modelPicker
        case rename
    }

    /// メニュー由来の提示を排他的に管理する単一の状態。
    private var menuPresentation: MenuPresentation?
    /// task-6: モデル選択シートの表示状態。
    public var isModelSheetPresented: Bool {
        get { menuPresentation == .modelPicker }
        set {
            if newValue {
                menuPresentation = .modelPicker
            } else if menuPresentation == .modelPicker {
                menuPresentation = nil
            }
        }
    }
    /// task-4: ピッカーの1行。kind を行IDに含め、同一 model ID の衝突を曖昧にしない。
    public struct ModelPickerEntry: Identifiable, Equatable, Sendable {
        public let kind: AgentKind
        public let modelID: String?
        public let displayName: String

        public var id: String { "\(kind.rawValue)::\(modelID ?? "__agent_default__")" }
    }
    public private(set) var modelPickerEntries: [ModelPickerEntry] = []
    public private(set) var selectedModelPickerEntryID: String?
    /// ドラフトでユーザーが選んだエージェント種別とモデル。表示用 ID と切り離して保持し、
    /// カタログの一時的な欠落で別 kind へ選択が移ることを防ぐ。
    private struct DraftModelSelection: Equatable {
        let kind: AgentKind
        let modelID: String?
    }
    private var draftModelSelection: DraftModelSelection?
    private var draftProject: String?
    private var draftProjectID: String?
    /// branch 情報は Session に無いため、取得済みのプロジェクト名だけを代替表示する。
    public var inputContextDisplayName: String? { session.projectName ?? draftProject }
    private var draftNeedsReady = false
    public private(set) var hasSpawnedDraft = false
    public var isAwaitingInitialSpawn: Bool { draftProject != nil && !hasSpawnedDraft }
    /// 入力バーが停止ボタンを出すべきか。下書き未 spawn（isAwaitingInitialSpawn）中は
    /// placeholder が .running でも送信ボタンを出す（最初の1通を送れるようにする）。
    public var showsStopButton: Bool {
        !isAwaitingInitialSpawn && currentStatus == .running && canInterrupt
    }
    public var showsInitialLoadingIndicator: Bool {
        isInitialLoading && !isAwaitingInitialSpawn && chatMessages.isEmpty
    }
    /// 表示名の単一の源（初期値は session.name）。
    public private(set) var displayName: String
    public var renameDraft: String = ""
    public var isRenamePresented: Bool {
        get { menuPresentation == .rename }
        set {
            if newValue {
                menuPresentation = .rename
            } else if menuPresentation == .rename {
                menuPresentation = nil
            }
        }
    }
    public private(set) var isRenaming = false

    /// 入力バー添付ストリップ用（確定時に生成した小さいプレビューのみ。フル解像度は `send` に保持）。
    public struct SessionAttachmentItem: Equatable, Identifiable, Sendable {
        public let id: UUID
        /// 本文の `[Image #N]` と対応する表示番号（1始まり・欠番は詰めない）。task-3 契約。
        public let number: Int
        public let send: SendAttachment
        public let previewData: Data

        public init(id: UUID = UUID(), number: Int = 1, send: SendAttachment, previewData: Data) {
            self.id = id
            self.number = number
            self.send = send
            self.previewData = previewData
        }
    }

    public init(session: Session, api: PhloxAPI) {
        self.session = session
        self.api = api
        self.currentStatus = session.status
        self.displayName = session.name
        // didSet は init では発火しないため、初期 running をここで記録する。
        if session.status == .running {
            thinkingStartedAt = Date()
        }
    }

    /// モデル選択シートを開く。別のメニュー presentation があれば置き換える。
    public func beginModelSelection() {
        menuPresentation = .modelPicker
    }

    /// セッション名変更シートを開く。`renameDraft` を現在の `displayName` で初期化する。
    public func beginRename() {
        renameDraft = displayName
        menuPresentation = .rename
    }

    /// trim 後の `renameDraft` でセッション名を確定する。空・同名は no-op。
    public func commitRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else {
            isRenamePresented = false
            return
        }
        isRenaming = true
        defer { isRenaming = false }
        do {
            try await api.rename(sessionID: session.id, name: trimmed)
            displayName = trimmed
            isRenamePresented = false
        } catch {
            // 失敗時は displayName を変えない。
        }
    }

    /// 実行中ターンの停止。`currentStatus == .running` のときだけ `interrupt` を呼ぶ。
    /// 409（非対応）は `canInterrupt = false` にし、エラーバナーは出さない。
    public func stop() async {
        guard currentStatus == .running else { return }
        do {
            try await api.interrupt(sessionID: session.id)
        } catch let error as PhloxError {
            if case .server(status: 409, _) = error {
                canInterrupt = false
            }
        } catch {}
    }

    /// 画像添付を追加する。上限違反のバッチは全体を弾き `attachmentError` を設定（部分採用しない）。
    /// 元画像と小さいプレビューを保持し、形式変換は送信前に行う。
    public func addAttachments(_ candidates: [SendAttachment]) {
        appendAttachments(candidates, previews: nil)
    }

    /// Pickerからの画像はプレビューもメインスレッド外で作る。
    public func addAttachmentsFromPicker(_ candidates: [SendAttachment]) async {
        guard candidates.count <= Self.maxAttachmentCount,
              candidates.allSatisfy({ $0.data.count <= Self.maxAttachmentBytesPerImage }) else {
            addAttachments(candidates)
            return
        }
        let previews = await Task.detached(priority: .userInitiated) {
            candidates.map { Self.makeAttachmentPreview(from: $0.data) }
        }.value
        appendAttachments(candidates, previews: previews)
    }

    private func appendAttachments(_ candidates: [SendAttachment], previews: [Data]?) {
        guard !candidates.isEmpty else { return }
        attachmentError = nil
        guard attachmentItems.count + candidates.count <= Self.maxAttachmentCount else {
            attachmentError = ImageAttachmentLimits.countMessage
            return
        }
        guard candidates.allSatisfy({ $0.data.count <= Self.maxAttachmentBytesPerImage }) else {
            attachmentError = ImageAttachmentLimits.inputSizeMessage
            return
        }

        var normalizedItems: [SessionAttachmentItem] = []
        normalizedItems.reserveCapacity(candidates.count)
        for (index, candidate) in candidates.enumerated() {
            guard let send = Self.normalizeAttachment(candidate) else {
                attachmentError = "画像を読み込めませんでした"
                return
            }
            let preview = previews?[index] ?? Self.makeAttachmentPreview(from: send.data)
            normalizedItems.append(SessionAttachmentItem(send: send, previewData: preview))
        }

        let combined = attachmentItems.map(\.send) + normalizedItems.map(\.send)
        let totalBytes = combined.reduce(0) { $0 + $1.data.count }
        if totalBytes > Self.maxAttachmentTotalBytes {
            attachmentError = ImageAttachmentLimits.inputTotalMessage
            return
        }

        var numberedItems: [SessionAttachmentItem] = []
        numberedItems.reserveCapacity(normalizedItems.count)
        var existingNumbers = attachmentItems.map(\.number)
        var currentText = inputText
        var currentCursor = inputCursorUTF16

        for item in normalizedItems {
            let number = ComposerImagePlaceholder.nextNumber(after: existingNumbers)
            existingNumbers.append(number)
            numberedItems.append(SessionAttachmentItem(
                id: item.id,
                number: number,
                send: item.send,
                previewData: item.previewData
            ))
            let inserted = ComposerImagePlaceholder.inserting(
                number: number,
                into: currentText,
                cursorUTF16: currentCursor
            )
            currentText = inserted.text
            currentCursor = inserted.cursorUTF16
        }

        attachmentItems.append(contentsOf: numberedItems)
        inputText = currentText
        inputCursorUTF16 = currentCursor
    }

    /// 本文の編集を添付へ同期する（本文から `[Image #N]` が消えたら添付も外す）。
    /// トークンの一部だけが消えた編集では、残骸ごと取り除いて「まとめて消えた」ように見せる。
    /// View の `.onChange(of: inputText)` から呼ぶこと。
    public func syncAttachmentsWithTextEdit(oldText: String, newText: String) {
        guard oldText != newText, !attachmentItems.isEmpty else { return }
        let removedNumbers = ComposerImagePlaceholder.numbersRemoved(
            from: oldText,
            to: newText,
            among: attachmentItems.map(\.number)
        )
        guard !removedNumbers.isEmpty else { return }

        // task-5: iOS の入力欄（SwiftUI の TextField）は打鍵を横取りできないため、
        // 1文字消えた直後に残ったトークンの断片をまとめて取り除いて「まとめて消えた」ように見せる。
        let survivingNumbers = attachmentItems.map(\.number).filter { !removedNumbers.contains($0) }
        var repairedText = newText
        var repairedCursor: Int?
        for number in removedNumbers {
            guard let repaired = ComposerImagePlaceholder.repairingBrokenPlaceholder(
                number: number,
                oldText: oldText,
                newText: repairedText,
                preserving: survivingNumbers
            ) else { continue }
            repairedText = repaired.text
            repairedCursor = repaired.cursorUTF16
        }

        // 修復が本文をさらに変えるので、外す添付は「修復後の本文」を基準に決め直す。
        // newText だけで決めると、修復が巻き込んだプレースホルダの添付が孤児として残る。
        let toRemove = Set(ComposerImagePlaceholder.numbersRemoved(
            from: oldText,
            to: repairedText,
            among: attachmentItems.map(\.number)
        ))
        attachmentItems.removeAll { toRemove.contains($0.number) }

        if repairedText != newText {
            inputText = repairedText
            inputCursorUTF16 = min(repairedCursor ?? inputCursorUTF16, repairedText.utf16.count)
        }
    }

    /// 添付を1件削除する（ストリップの × ボタン用）。
    public func removeAttachment(at index: Int) {
        guard attachmentItems.indices.contains(index) else { return }
        let removedNumber = attachmentItems[index].number
        attachmentItems.remove(at: index)
        attachmentError = nil
        inputText = ComposerImagePlaceholder.removing(number: removedNumber, from: inputText)
        inputCursorUTF16 = min(inputCursorUTF16, inputText.utf16.count)
    }

    /// api.subAgents の markerMessageID で行→サブエージェントを解決する。
    /// 解決不能（不一致・旧サーバー 404/501）は nil を返す（クラッシュしない）。
    public func resolveSubAgentID(forMessageID messageID: String) async -> String? {
        guard let summaries = try? await api.subAgents(sessionID: session.id) else { return nil }
        updateSubAgentMarkerIndex(from: summaries)
        return summaries.first(where: { $0.markerMessageID == messageID })?.id
    }

    /// キャッシュ済み index から同期的に subAgentID を引く（行のタップ可否表示用）。
    public func subAgentID(forMessageID messageID: String) -> String? {
        subAgentMarkerIndex[messageID]
    }

    /// AskUserQuestion の回答送信（task-0 契約。実装は task-4）。
    /// 戻り値: API が回答を受理し、ローカルの質問カードを answered へ更新したら true。
    public func answerQuestion(requestId: String, answers: [String: [String]]) async -> Bool {
        let hasPendingVisible = visibleMessages.contains { message in
            if case let .userQuestion(_, rid, _, _, state) = message {
                return rid == requestId && state == .pending
            }
            return false
        }
        guard hasPendingVisible else { return false }
        guard let index = chatMessages.firstIndex(where: { message in
            if case let .userQuestion(_, rid, _, _, state) = message {
                return rid == requestId && state == .pending
            }
            return false
        }) else { return false }
        guard case let .userQuestion(id, rid, questions, _, _) = chatMessages[index] else {
            return false
        }

        do {
            try await api.respondToQuestion(
                sessionID: session.id,
                requestId: requestId,
                answers: answers
            )
        } catch {
            return false
        }

        chatMessages[index] = .userQuestion(
            id: id,
            requestId: rid,
            questions: questions,
            answers: answers,
            state: .answered
        )
        return true
    }

    public func attachmentImageCount(forMessageID id: String) -> Int? {
        attachmentCountsByMessageID[id]
    }

    /// サブエージェント詳細画面用 ViewModel を生成する（api を View に漏らさない）。
    public func makeSubAgentDetailViewModel(subAgentID: String) -> SubAgentDetailViewModel {
        SubAgentDetailViewModel(session: session, subAgentID: subAgentID, api: api)
    }

    /// 生成中インジケータの表示条件: チャット表示中 かつ currentStatus == .running。
    public var isAgentWorking: Bool { showsChat && currentStatus == .running }

    /// Thinking インジケータに出す活動状態。表示しないときは nil。
    /// 承認・回答待ちは実行中でなくても待機として出す（orb の 6 状態のうち waiting）。
    public var activityState: AgentActivityState? {
        guard showsChat else { return nil }
        if let waiting = AgentActivityClassifier.waitingState(for: currentStatus) { return waiting }
        guard isAgentWorking else { return nil }
        return ChatRecapIOS.deriveActivityState(messages: chatMessages, status: currentStatus)
    }

    /// 描画対象メッセージ（空メッセージを除外した chatMessages）。
    public var visibleMessages: [ChatMessage] {
        chatMessages.filter(Self.isVisible)
    }

    /// reasoning / command / fileChange のみ折りたたみトグル対象。
    public static func supportsMessageExpansionToggle(_ message: ChatMessage) -> Bool {
        switch message {
        case .reasoning, .command, .fileChange:
            return true
        case .user, .agent, .error, .subAgent, .userQuestion:
            return false
        }
    }

    public func isMessageExpanded(_ messageID: String) -> Bool {
        expandedMessageIDs.contains(messageID)
    }

    public func toggleMessageExpansion(_ messageID: String) {
        if expandedMessageIDs.contains(messageID) {
            expandedMessageIDs.remove(messageID)
        } else {
            expandedMessageIDs.insert(messageID)
        }
    }

    /// 折りたたみヘッダ用の先頭プレビュー（種別ラベル横の要約）。
    public static func collapsedMessagePreview(for message: ChatMessage) -> String {
        switch message {
        case let .reasoning(_, text):
            return collapsedPreview(text)
        case let .command(_, command, output):
            if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return collapsedPreview(command)
            }
            return collapsedPreview(output)
        case let .fileChange(_, changes):
            return collapsedPreview(changes.map(\.path).joined(separator: ", "))
        default:
            return ""
        }
    }

    static func collapsedPreview(_ text: String, maxLength: Int = 48) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    /// visibleMessages の末尾が .reasoning ならその text（生成中インジケータのプレビュー用）。それ以外は nil。
    /// task-4: View は `recap(now:)` を使う。削除せず回帰保全（未使用化のみ可）。
    public var thinkingPreview: String? {
        guard case let .reasoning(_, text)? = visibleMessages.last else { return nil }
        return text
    }

    /// 実行中ターンの recap 要約（task-4）。呼び出しは読み取り専用。
    /// `elapsed = now - (thinkingStartedAt ?? now)` を `ChatRecapIOS.derive` に渡す。
    public func recap(now: Date) -> String? {
        let elapsed = now.timeIntervalSince(thinkingStartedAt ?? now)
        return ChatRecapIOS.derive(
            messages: chatMessages,
            status: currentStatus,
            elapsed: elapsed
        )
    }

    /// 入力バー有効: starting 以外。初回 spawn 待ち中は既存どおり有効にする。
    public var inputEnabled: Bool {
        if isAwaitingInitialSpawn { return true }
        switch currentStatus {
        case .awaitingApproval, .awaitingUserQuestion, .idle, .running, .completed, .error:
            return true
        case .starting:
            return false
        }
    }

    public var isSending: Bool { sendState == .sending }
    public var isInputBarEnabled: Bool { inputEnabled && !isSending }

    /// task-6: 選択可能モデルが1件以上あるときだけチップを出す。
    public var showsModelSelectorChip: Bool {
        if isAwaitingInitialSpawn { return !modelPickerEntries.isEmpty }
        guard let modelSettings else { return false }
        return !modelSettings.availableModels.isEmpty
    }

    /// task-6: チップに表示する現在モデルの表示名。
    public var selectedModelDisplayName: String? {
        if let selectedModelPickerEntryID,
           let entry = modelPickerEntries.first(where: { $0.id == selectedModelPickerEntryID }) {
            return entry.displayName
        }
        guard let modelSettings, !modelSettings.availableModels.isEmpty else { return nil }
        if let selected = modelSettings.selectedModel,
           let match = modelSettings.availableModels.first(where: { $0.id == selected }) {
            return match.displayName
        }
        return modelSettings.availableModels.first?.displayName
    }

    /// 構造化チャットを表示するか（メッセージが1件以上ある場合）。
    public var showsChat: Bool { !chatMessages.isEmpty }

    /// 詳細表示時のロード入口。構造化チャットを取得する。
    public func load() async {
        defer { isInitialLoading = false }
        await refreshSubAgentIndex()
        await loadModelSettings()
        if await adoptNonEmptyMessages(updateOnlyIfChanged: false) { return }
        chatMessages = []
    }

    /// ポーリング間隔（リアルタイム更新の代替。P3 のストリーミングまでの暫定）。
    public static let pollInterval: Duration = .seconds(3)

    /// 詳細表示中のポーリング入口。初回 `load()` でモードを決め、画面離脱（`.task` キャンセル）まで
    /// 一定間隔で非破壊 `refresh()` を回す。これでエージェントの遅延応答が自動で反映される。
    public func startPolling(interval: Duration = pollInterval) async {
        await load()
        while !Task.isCancelled {
            do { try await Task.sleep(for: interval) } catch { break }
            await refresh()
        }
    }

    /// ドラフトではカタログだけを準備して終了し、存在しない placeholder を poll しない。
    /// spawn 後は `session.id` の変化で View の task が再起動し、実セッションを poll する。
    public func startPolling(
        composeDraft: SessionComposeDraft?,
        interval: Duration = pollInterval
    ) async {
        if let composeDraft, !hasSpawnedDraft {
            await prepareDraft(composeDraft)
            return
        }
        await startPolling(interval: interval)
    }

    /// ポーリング更新。データは更新するが、**一時的な失敗・空では表示を消さない**（復帰時フリッカー防止）。
    /// - 構造化メッセージが取れれば（非空）チャットを更新。
    /// - チャット表示中の失敗/空は現状維持。
    public func refresh() async {
        await refreshCurrentStatus()
        await refreshSubAgentIndex()
        await loadModelSettings()
        if await adoptMessagesFromDelta(updateOnlyIfChanged: true) { return }
        if showsChat { return }
    }

    /// task-6: モデル一覧を取得する。404/オフライン等はチップ非表示に留め画面は壊さない。
    public func loadModelSettings() async {
        guard let modelAPI = api as? any SessionModelSelecting else {
            modelSettings = nil
            return
        }
        do {
            let settings = try await modelAPI.sessionSettings(sessionID: session.id)
            modelSettings = settings.availableModels.isEmpty ? nil : settings
            modelPickerEntries = settings.availableModels.map {
                ModelPickerEntry(kind: session.agent, modelID: $0.id, displayName: $0.displayName)
            }
            if let selected = settings.selectedModel,
               let entry = modelPickerEntries.first(where: { $0.modelID == selected }) {
                selectedModelPickerEntryID = entry.id
            } else {
                selectedModelPickerEntryID = modelPickerEntries.first?.id
            }
        } catch {
            modelSettings = nil
            modelPickerEntries = []
            selectedModelPickerEntryID = nil
        }
    }

    /// task-6: モデルを切り替え、成功時にチップ表示を更新する。
    public func selectModel(_ modelID: String) async {
        guard let modelAPI = api as? any SessionModelSelecting else { return }
        let availableModels = modelSettings?.availableModels ?? []
        guard availableModels.contains(where: { $0.id == modelID }) else { return }
        do {
            try await modelAPI.setModel(sessionID: session.id, model: modelID)
            modelSettings = SessionModelSettings(
                selectedModel: modelID,
                availableModels: availableModels
            )
            selectedModelPickerEntryID = modelPickerEntries.first(where: { $0.modelID == modelID })?.id
        } catch {
            // 失敗時は現状維持（エラーバナーは出さない）。
        }
    }

    /// 未 spawn compose の3エージェント分カタログを読み込む。
    /// Codex は既存契約どおり、空カタログでも agent-only 行を必ず持つ。
    public func prepareDraft(_ draft: SessionComposeDraft) async {
        draftProject = draft.project
        draftProjectID = draft.projectID
        guard !hasSpawnedDraft else { return }

        var catalogs: [AgentKind: AgentModels] = [:]
        for kind in [AgentKind.claudeCode, .cursor, .codex] {
            if let catalog = try? await api.agentModels(kind: kind) {
                catalogs[kind] = catalog
            }
        }

        var entries: [ModelPickerEntry] = []
        for kind in [AgentKind.claudeCode, .cursor, .codex] {
            for model in catalogs[kind]?.models ?? [] {
                entries.append(ModelPickerEntry(
                    kind: kind,
                    modelID: model.id,
                    displayName: model.displayName
                ))
            }
        }
        if catalogs[.codex]?.models.isEmpty ?? true {
            entries.append(ModelPickerEntry(kind: .codex, modelID: nil, displayName: AgentKind.codex.displayName))
        }
        modelPickerEntries = entries

        guard let previousSelection = draftModelSelection else {
            selectedModelPickerEntryID = Self.defaultDraftEntryID(entries: entries, catalogs: catalogs)
            return
        }

        if let exactEntry = entries.first(where: {
            $0.kind == previousSelection.kind && $0.modelID == previousSelection.modelID
        }) {
            selectedModelPickerEntryID = exactEntry.id
            return
        }
        if let defaultModel = catalogs[previousSelection.kind]?.defaultModel,
           let defaultEntry = entries.first(where: {
               $0.kind == previousSelection.kind && $0.modelID == defaultModel
           }) {
            draftModelSelection = DraftModelSelection(kind: previousSelection.kind, modelID: defaultModel)
            selectedModelPickerEntryID = defaultEntry.id
            return
        }
        if let sameKindEntry = entries.first(where: { $0.kind == previousSelection.kind }) {
            draftModelSelection = DraftModelSelection(
                kind: previousSelection.kind,
                modelID: sameKindEntry.modelID
            )
            selectedModelPickerEntryID = sameKindEntry.id
            return
        }

        // 行が一時的に存在しなくても、spawn の kind は保持する。ピッカーでは未選択に見せる。
        draftModelSelection = DraftModelSelection(kind: previousSelection.kind, modelID: nil)
        selectedModelPickerEntryID = nil
    }

    public func selectDraftModel(entryID: String) {
        guard isAwaitingInitialSpawn,
              let entry = modelPickerEntries.first(where: { $0.id == entryID }) else { return }
        draftModelSelection = DraftModelSelection(kind: entry.kind, modelID: entry.modelID)
        selectedModelPickerEntryID = entryID
    }

    public func selectModelPickerEntry(entryID: String) async {
        if isAwaitingInitialSpawn {
            selectDraftModel(entryID: entryID)
            return
        }
        guard let modelID = modelPickerEntries.first(where: { $0.id == entryID })?.modelID else { return }
        await selectModel(modelID)
    }

    private static func defaultDraftEntryID(
        entries: [ModelPickerEntry],
        catalogs: [AgentKind: AgentModels]
    ) -> String? {
        for kind in [AgentKind.claudeCode, .cursor] {
            guard let defaultModel = catalogs[kind]?.defaultModel else { continue }
            if let entry = entries.first(where: { $0.kind == kind && $0.modelID == defaultModel }) {
                return entry.id
            }
        }
        return entries.first?.id
    }

    /// task-6 白箱テスト用: availableModels の有無だけでチップ表示を判定する。
    static func shouldShowModelSelectorChip(for settings: SessionModelSettings?) -> Bool {
        guard let settings else { return false }
        return !settings.availableModels.isEmpty
    }

    /// E4-8 送信。受付後に同じ入力だけクリアする。失敗時は入力を書き換えない。
    public func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendState != .sending else { return }

        let backupText = inputText
        let backupRevision = inputRevision
        let backupItems = attachmentItems
        let backupModel = selectedModelPickerEntryID
        let backupSessionID = session.id
        sendState = .sending
        let prepared: [PreparedImageAttachment]
        do {
            prepared = try await ImageAttachmentPreparer.prepare(backupItems.map { $0.send.data })
            guard inputRevision == backupRevision, inputText == backupText, attachmentItems == backupItems,
                  selectedModelPickerEntryID == backupModel, session.id == backupSessionID else {
                sendState = .failed("本文・添付・モデルが変更されたため、送信を中止しました")
                return
            }
        } catch {
            attachmentError = error.localizedDescription
            sendState = .failed(error.localizedDescription)
            return
        }
        do {
            if let draftProject, !hasSpawnedDraft {
                let selection = draftModelSelection
                    ?? modelPickerEntries.first(where: { $0.id == selectedModelPickerEntryID }).map {
                        DraftModelSelection(kind: $0.kind, modelID: $0.modelID)
                    }
                    ?? DraftModelSelection(kind: .codex, modelID: nil)
                let spawned = try await api.spawn(SpawnRequest(
                    agent: selection.kind,
                    workspace: draftProject,
                    projectID: draftProjectID,
                    model: selection.modelID
                ))
                // listSessions の反映を待たず、spawn 応答の実体をそのまま採用する。
                session = spawned
                currentStatus = spawned.status
                displayName = spawned.name
                hasSpawnedDraft = true
                draftNeedsReady = true
            }
            if draftNeedsReady {
                guard try await api.waitUntilReady(sessionID: session.id) else {
                    throw DraftComposeError.notReady
                }
                draftNeedsReady = false
                currentStatus = .running
            }
            _ = try await api.send(SendRequest(
                sessionID: session.id,
                text: text,
                images: prepared.map { SendAttachment(mediaType: $0.mediaType, data: $0.data) }
            ))
            if inputRevision == backupRevision, inputText == backupText, attachmentItems == backupItems {
                inputText = ""
                attachmentItems = []
            }
            if !backupItems.isEmpty {
                pendingAttachmentSends.append(.init(text: text, count: backupItems.count))
            }
            sendState = .idle
            attachmentError = nil
            await refresh() // 送信後に即時更新（以降はポーリングが追従）
        } catch let error as PhloxError {
            sendState = .failed(error.presentation.message)
        } catch {
            sendState = .failed("送信に失敗しました")
        }
    }

    /// View の environment を送信経路にも渡し、`.task` より先に操作されても placeholder へ送らない。
    public func sendMessage(composeDraft: SessionComposeDraft?) async {
        if let composeDraft, !hasSpawnedDraft {
            await prepareDraft(composeDraft)
        }
        await sendMessage()
    }

    private enum DraftComposeError: Error {
        case notReady
    }

    /// messages 全量取得→非空なら採用。`load()` と delta フォールバック用。
    private func adoptNonEmptyMessages(updateOnlyIfChanged: Bool) async -> Bool {
        let messages: [ChatMessage]
        do {
            messages = try await api.messages(sessionID: session.id)
            loadError = nil
        } catch let error as PhloxError {
            if case .notFound = error {
                loadError = nil
            } else if !showsChat {
                loadError = error.presentation.message
            }
            return false
        } catch {
            if !showsChat { loadError = "会話の取得に失敗しました" }
            return false
        }
        guard !messages.isEmpty else { return false }
        if updateOnlyIfChanged {
            if chatMessages != messages { chatMessages = messages }
        } else {
            chatMessages = messages
        }
        return true
    }

    /// messagesDelta 取得→snapshot 置換 / 差分 append。404・501 は `messages()` へフォールバック。
    private func adoptMessagesFromDelta(updateOnlyIfChanged: Bool) async -> Bool {
        do {
            let delta = try await api.messagesDelta(sessionID: session.id, since: messagesCursor, wait: nil)
            applyMessagesDelta(delta, updateOnlyIfChanged: updateOnlyIfChanged)
            if let cursor = delta.cursor {
                messagesCursor = cursor
            }
            loadError = nil
            if !chatMessages.isEmpty {
                return true
            }
            return false
        } catch let error as PhloxError where shouldFallbackToFullMessages(error) {
            return await adoptNonEmptyMessages(updateOnlyIfChanged: updateOnlyIfChanged)
        } catch let error as PhloxError {
            if !showsChat { loadError = error.presentation.message }
            return false
        } catch {
            if !showsChat { loadError = "会話の取得に失敗しました" }
            return false
        }
    }

    private func shouldFallbackToFullMessages(_ error: PhloxError) -> Bool {
        switch error {
        case .notFound:
            return true
        case let .server(status, _) where status == 404 || status == 501:
            return true
        default:
            return false
        }
    }

    private func applyMessagesDelta(_ delta: MessagesDelta, updateOnlyIfChanged: Bool) {
        if delta.isSnapshot {
            applySnapshotMessages(delta.messages, updateOnlyIfChanged: updateOnlyIfChanged)
            return
        }
        guard !delta.messages.isEmpty else { return }
        if let firstID = delta.messages.first?.id,
           chatMessages.contains(where: { $0.id == firstID }) {
            applySnapshotMessages(delta.messages, updateOnlyIfChanged: updateOnlyIfChanged)
            return
        }
        var updated = chatMessages
        let existingIDs = Set(updated.map(\.id))
        for message in delta.messages where !existingIDs.contains(message.id) {
            updated.append(message)
        }
        if updateOnlyIfChanged {
            if updated != chatMessages { chatMessages = updated }
        } else {
            chatMessages = updated
        }
    }

    private func applySnapshotMessages(_ messages: [ChatMessage], updateOnlyIfChanged: Bool) {
        if updateOnlyIfChanged {
            guard !messages.isEmpty, chatMessages != messages else { return }
            chatMessages = messages
        } else {
            chatMessages = messages
        }
    }

    private func refreshCurrentStatus() async {
        let previousStatus = currentStatus
        guard let sessions = try? await api.listSessions(),
              let live = sessions.first(where: { $0.id == session.id }) else { return }
        currentStatus = live.status
        if previousStatus == .running, currentStatus != .running {
            await fetchTurnUsageIfAvailable()
        }
    }

    /// running へ入った時刻だけ記録し、同一 running の再代入では動かさない（ポーリング暴れ防止）。
    private func syncThinkingStartedAt(from oldValue: SessionStatus) {
        if currentStatus == .running {
            if oldValue != .running {
                thinkingStartedAt = Date()
            }
        } else {
            thinkingStartedAt = nil
        }
    }

    private func fetchTurnUsageIfAvailable() async {
        guard let usage = try? await api.usage(sessionID: session.id) else { return }
        turnUsage = usage
    }

    /// 旧サーバー（404/501）でも黙って劣化。エラーバナーは出さない。
    private func refreshSubAgentIndex() async {
        guard let summaries = try? await api.subAgents(sessionID: session.id) else { return }
        updateSubAgentMarkerIndex(from: summaries)
    }

    private func updateSubAgentMarkerIndex(from summaries: [SubAgentSummary]) {
        subAgentMarkerIndex = Dictionary(
            uniqueKeysWithValues: summaries.compactMap { summary in
                guard let marker = summary.markerMessageID else { return nil }
                return (marker, summary.id)
            }
        )
    }

    private func reconcileAttachments() {
        let result = SessionAttachmentReconciler.reconcile(
            messages: chatMessages,
            pending: pendingAttachmentSends,
            assigned: attachmentCountsByMessageID
        )
        attachmentCountsByMessageID = result.assigned
        pendingAttachmentSends = result.remaining
    }

    static func isVisible(_ message: ChatMessage) -> Bool {
        switch message {
        case let .user(_, text), let .agent(_, text), let .reasoning(_, text), let .subAgent(_, text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .error(_, message):
            return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .command(_, command, output):
            let commandEmpty = command?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            let outputEmpty = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return !(commandEmpty && outputEmpty)
        case let .fileChange(_, changes):
            return !changes.isEmpty
        case let .userQuestion(_, _, questions, _, _):
            return !questions.isEmpty
        }
    }

    // MARK: - task-10 画像正規化（契約 §5: mediaType と実バイトを一致させる）

    enum ImageWireFormat: Equatable {
        case png
        case jpeg
        case other
    }

    static let attachmentPreviewMaxPixelSize: CGFloat = 112

    /// 先頭マジックバイトで PNG / JPEG を判定する（HEIC 等は `.other`）。
    static func detectImageWireFormat(_ data: Data) -> ImageWireFormat {
        guard data.count >= 4 else { return .other }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if data.starts(with: [0xFF, 0xD8]) { return .jpeg }
        return .other
    }

    /// 元画像は保持し、送信時に共通処理で必要な形式へ変換する。
    static func normalizeAttachment(_ candidate: SendAttachment) -> SendAttachment? {
        switch detectImageWireFormat(candidate.data) {
        case .png:
            return SendAttachment(mediaType: "image/png", data: candidate.data)
        case .jpeg:
            return SendAttachment(mediaType: "image/jpeg", data: candidate.data)
        case .other:
            if let source = CGImageSourceCreateWithData(candidate.data as CFData, nil),
               let type = CGImageSourceGetType(source) as String?,
               let mediaType = UTType(type)?.preferredMIMEType {
                return SendAttachment(mediaType: mediaType, data: candidate.data)
            }
            // PNG/JPEGの実体検査は送信前の共通処理で行う。
            if candidate.mediaType == "image/png" || candidate.mediaType == "image/jpeg" {
                return SendAttachment(mediaType: candidate.mediaType, data: candidate.data)
            }
            return nil
        }
    }

    /// ストリップ用の小さいPNGプレビューをキャッシュする。
    nonisolated static func makeAttachmentPreview(from data: Data) -> Data {
        ImageAttachmentPreparer.preview(data) ?? Data()
    }
}
