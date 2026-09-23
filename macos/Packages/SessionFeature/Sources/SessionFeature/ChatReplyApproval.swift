import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

/// 返答エリアの承認カード 1 件（05 R6）。Codex の承認要求と、Claude のツール使用許可
/// （質問として届く can_use_tool）を同じ形にそろえる。
public struct ReplyApproval: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case command
        case fileChange
        case permissions
        /// Claude の Bash / 編集系以外のツール（WebFetch など）。
        case tool
    }

    public enum Source: Equatable, Sendable {
        case approval(UUID)
        case toolPermission(requestId: String, answerKey: String)
    }

    public struct FileLine: Equatable, Sendable {
        public let mark: String
        public let path: String
        public let added: Int?
        public let removed: Int?
    }

    public let id: String
    public let source: Source
    public let kind: Kind
    /// コマンドの全文・権限のルール・ツールの対象など、カードの枠に出す 1 行。
    public let subject: String?
    public let files: [FileLine]
    public let workingDirectory: String?
    public let toolName: String?
    public let requestedAt: Date

    /// 「このセッション中は許可」を返せるか。Claude のツール使用許可はターン単位の許可しか返せない。
    public var supportsSessionScope: Bool {
        if case .approval = source { true } else { false }
    }

    /// 出た直後に押せない時間（05 R6c）。
    public static let armDelay: TimeInterval = 0.5

    /// 増減行数。unified diff の行頭だけを数える（ヘッダの +++ / --- は除く）。
    static func lineCounts(diff: String) -> (added: Int, removed: Int)? {
        guard !diff.isEmpty else { return nil }
        var added = 0
        var removed = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
            if line.hasPrefix("+") { added += 1 } else if line.hasPrefix("-") { removed += 1 }
        }
        return (added, removed)
    }

    static func fileLine(_ change: FilePatchChange) -> FileLine {
        let counts = lineCounts(diff: change.diff)
        let mark: String
        switch change.kind?.lowercased() {
        case "add", "added", "create": mark = "A"
        case "delete", "deleted", "remove": mark = "D"
        default: mark = "M"
        }
        return FileLine(mark: mark, path: change.path, added: counts?.added, removed: counts?.removed)
    }
}

extension ChatSessionViewModel {
    /// 返答エリアに出す承認（到着順）。Codex の承認要求のあとに Claude のツール使用許可を並べる。
    public var replyApprovals: [ReplyApproval] {
        var result = pendingApprovals.map(replyApproval(for:))
        // ponytail: 会話を末尾まで線形に見る。未回答の質問を索引で持つ必要が出たら VM に集合を足す。
        for item in transcript {
            guard case .userQuestion(let id, let requestId, let questions, _, .pending, let timestamp) = item,
                  questions.count == 1, let question = questions.first, let permission = question.permission
            else { continue }
            result.append(Self.replyApproval(
                itemID: id,
                requestId: requestId,
                answerKey: question.answerKey,
                permission: permission,
                workingDirectory: rawWorkspacePath,
                requestedAt: timestamp
            ))
        }
        return result
    }

    /// 表示中の承認（ページ送りの位置を範囲内に丸める）。
    public var currentReplyApproval: ReplyApproval? {
        let approvals = replyApprovals
        guard !approvals.isEmpty else { return nil }
        return approvals[min(max(approvalPageIndex, 0), approvals.count - 1)]
    }

    /// 承認カードの質問（Claude のツール使用許可）は質問カードには出さない。
    /// 一覧・タイル・ヘッダに出す状態。Claude のツール使用許可は wire 上は質問だが、返答エリアでは承認カードに出すので
    /// 状態も「承認待ち」にそろえる（質問が同時に待っていれば質問待ちのまま）。
    public var displayStatus: SessionStatus {
        let base = SessionDisplayStatus.resolve(rawStatus: status, isProcessing: isProcessing)
        guard base == .awaitingUserQuestion else { return base }
        var permissionPrompt: String?
        for item in transcript.reversed() {
            guard case .userQuestion(_, _, let questions, _, .pending, _) = item else { continue }
            guard Self.isToolPermissionQuestion(questions) else { return base }
            permissionPrompt = permissionPrompt ?? questions.first?.question
        }
        return permissionPrompt.map { .awaitingApproval(prompt: $0) } ?? base
    }

    static func isToolPermissionQuestion(_ questions: [ChatUserQuestion]) -> Bool {
        questions.count == 1 && questions.first?.permission != nil
    }

    /// 入力欄の Tab。承認か質問のカードがあればそちらへ移る。
    func moveFocusToReplyCard() -> Bool {
        let hasQuestion = transcript.contains { item in
            guard case .userQuestion(_, _, let questions, _, .pending, _) = item else { return false }
            return !Self.isToolPermissionQuestion(questions)
        }
        guard !replyApprovals.isEmpty || hasQuestion else { return false }
        requestReplyCardFocus()
        return true
    }

    /// カードが画面に出るたび（ページを戻したときも）0.5 秒の待ちからやり直す。
    func markApprovalPresented(_ id: String, at date: Date = Date()) {
        approvalPresentedAt[id] = date
    }

    /// 出てから 0.5 秒たったか。一度も出ていない要求はまだ押せない。
    func isApprovalArmed(_ id: String, now: Date = Date()) -> Bool {
        guard let shownAt = approvalPresentedAt[id] else { return false }
        return now.timeIntervalSince(shownAt) >= ReplyApproval.armDelay
    }

    /// 承認カード・メニュー（⌥⌘↩ / ⌥⌘⌫）からの返答。出た直後 0.5 秒は受け付けない。
    @discardableResult
    public func respond(to approval: ReplyApproval, decision: ApprovalDecision, now: Date = Date()) async -> Bool {
        guard isApprovalArmed(approval.id, now: now) else { return false }
        approvalPresentedAt[approval.id] = nil
        switch approval.source {
        case .approval(let id):
            await respondToApproval(id, decision: decision)
        case .toolPermission(let requestId, let answerKey):
            switch decision {
            case .accept, .acceptForSession:
                _ = await respondToUserQuestion(requestId: requestId, answers: [answerKey: ["Allow"]])
            case .decline:
                _ = await respondToUserQuestion(requestId: requestId, answers: [answerKey: ["Deny"]])
            case .cancel:
                // 質問カードの「閉じる」と同じ（ターンを中断する）。
                await turnInterrupt()
            }
        }
        return true
    }

    /// メニューの「許可 / 拒否」の対象。表示中のカードに限る。
    public func respondToCurrentApproval(_ decision: ApprovalDecision) async {
        guard let approval = currentReplyApproval else { return }
        await respond(to: approval, decision: decision)
    }

    private func replyApproval(for request: ChatApprovalRequest) -> ReplyApproval {
        switch request.kind {
        case .command:
            return ReplyApproval(
                id: request.id.uuidString,
                source: .approval(request.id),
                kind: .command,
                subject: request.command ?? request.prompt,
                files: [],
                workingDirectory: request.workingDirectory,
                toolName: nil,
                requestedAt: request.requestedAt
            )
        case .fileChange:
            // ファイルの一覧は同じ item の変更（会話に届いている fileChange）から引く。
            let changes = transcript.lazy.compactMap { item -> [FilePatchChange]? in
                if case .fileChange(let id, let changes, _) = item, id == request.itemId { return changes }
                return nil
            }.first ?? []
            return ReplyApproval(
                id: request.id.uuidString,
                source: .approval(request.id),
                kind: .fileChange,
                subject: changes.isEmpty ? request.prompt : nil,
                files: changes.map(ReplyApproval.fileLine),
                workingDirectory: request.workingDirectory,
                toolName: nil,
                requestedAt: request.requestedAt
            )
        case .permissions:
            return ReplyApproval(
                id: request.id.uuidString,
                source: .approval(request.id),
                kind: .permissions,
                subject: request.permissionsText ?? request.prompt,
                files: [],
                workingDirectory: request.workingDirectory,
                toolName: nil,
                requestedAt: request.requestedAt
            )
        }
    }

    static func replyApproval(
        itemID: String,
        requestId: String,
        answerKey: String,
        permission: ChatToolPermission,
        workingDirectory: String?,
        requestedAt: Date
    ) -> ReplyApproval {
        let kind: ReplyApproval.Kind
        var files: [ReplyApproval.FileLine] = []
        switch permission.toolName {
        case "Bash":
            kind = .command
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            kind = .fileChange
            files = [ReplyApproval.FileLine(
                mark: permission.toolName == "Write" ? "A" : "M",
                path: permission.detail,
                added: nil,
                removed: nil
            )]
        default:
            kind = .tool
        }
        return ReplyApproval(
            id: itemID,
            source: .toolPermission(requestId: requestId, answerKey: answerKey),
            kind: kind,
            subject: kind == .fileChange ? nil : permission.detail,
            files: files,
            workingDirectory: workingDirectory,
            toolName: permission.toolName,
            requestedAt: requestedAt
        )
    }
}

/// 承認カード（05 R6〜R6f）。入力欄の直上に 1 枚ずつ出す。
struct ApprovalCard: View {
    @Bindable var viewModel: ChatSessionViewModel
    let approval: ReplyApproval
    let index: Int
    let count: Int
    var onFocusChange: (Bool) -> Void = { _ in }

    @FocusState private var isFocused: Bool
    @State private var armProgress: CGFloat = 0
    @State private var isArmed = false
    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
            subjectBox
            if let meta = metaText {
                Text(verbatim: meta)
                    .font(.system(size: 11))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            buttonRow
            if isFocused, approval.supportsSessionScope {
                Text("「このセッション中は許可」は、このセッションが終わるまで有効です。")
                    .font(.system(size: 11))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(12)
        .background(DSColor.attentionTint(.approval), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DSColor.attentionMark(.approval), lineWidth: isFocused ? 2 : 1)
        )
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(characters: CharacterSet(charactersIn: "ysnYSN"), phases: .down) { press in
            switch press.characters.lowercased() {
            case "y": respond(.accept)
            case "s": if approval.supportsSessionScope { respond(.acceptForSession) }
            case "n": respond(.decline)
            default: return .ignored
            }
            return .handled
        }
        .onKeyPress(.escape) {
            respond(.cancel)
            return .handled
        }
        .onKeyPress(.tab) {
            viewModel.returnFocusToComposer()
            return .handled
        }
        .onChange(of: viewModel.replyCardFocusRequest) { _, _ in isFocused = true }
        .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
        .onDisappear { onFocusChange(false) }
        // 要求が変わるたび（1 件返して次が出たときも）0.5 秒の待ちからやり直す。
        .task(id: approval.id) {
            viewModel.markApprovalPresented(approval.id)
            isArmed = viewModel.isApprovalArmed(approval.id)
            armProgress = isArmed ? 1 : 0
            guard !isArmed else { return }
            withAnimation(.linear(duration: ReplyApproval.armDelay)) { armProgress = 1 }
            try? await Task.sleep(for: .seconds(ReplyApproval.armDelay))
            isArmed = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("承認待ち · \(kindLabel)"))
    }

    // MARK: - 見出し

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(DSColor.attentionMark(.approval))
            Text("承認待ち · \(kindLabel)")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DSColor.attentionInk(.approval))
            Spacer(minLength: DSSpacing.s)
            if count > 1 { pager }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.sinceText(approval.requestedAt, now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(DSColor.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    private var pager: some View {
        HStack(spacing: 4) {
            Button { viewModel.approvalPageIndex = index - 1 } label: {
                Image(systemName: "chevron.left").frame(width: 16, height: 16)
            }
            .disabled(index == 0)
            .accessibilityLabel(Text("前の要求"))
            Text(verbatim: "\(index + 1) / \(count)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(DSColor.textSecondary)
            Button { viewModel.approvalPageIndex = index + 1 } label: {
                Image(systemName: "chevron.right").frame(width: 16, height: 16)
            }
            .disabled(index >= count - 1)
            .accessibilityLabel(Text("次の要求"))
        }
        .buttonStyle(HoverableIconButtonStyle())
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(DSColor.textSecondary)
    }

    private var kindLabel: String { Self.kindLabel(approval.kind, locale: locale) }

    /// 「コマンドの実行」など（承認カードの見出し・グリッドのタイル）。
    static func kindLabel(_ kind: ReplyApproval.Kind, locale: Locale) -> String {
        let key: String
        switch kind {
        case .command: key = "コマンドの実行"
        case .fileChange: key = "ファイルの変更"
        case .permissions: key = "権限の変更"
        case .tool: key = "ツールの使用"
        }
        return AppLocalizedString.string(key, locale: locale)
    }

    private var title: LocalizedStringKey {
        switch approval.kind {
        case .command: return "次のコマンドを実行しようとしています"
        case .fileChange:
            return approval.files.isEmpty
                ? "ファイルを変更しようとしています"
                : "\(approval.files.count) ファイルを変更しようとしています"
        case .permissions: return "許可ルールの追加を求めています"
        case .tool: return "\(approval.toolName ?? "") を使おうとしています"
        }
    }

    static func sinceText(_ date: Date, now: Date) -> LocalizedStringKey {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        return minutes < 1 ? "たった今から" : "\(minutes) 分前から"
    }

    // MARK: - 対象

    @ViewBuilder
    private var subjectBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch approval.kind {
            case .command:
                Text(verbatim: "$ \(approval.subject ?? "")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .chatTextSelection()
            case .fileChange:
                if approval.files.isEmpty {
                    Text(verbatim: approval.subject ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(DSColor.textPrimary)
                } else {
                    ForEach(Array(approval.files.enumerated()), id: \.offset) { _, file in
                        fileRow(file)
                    }
                }
            case .permissions:
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.m) {
                    Text("追加する")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textSecondary)
                    Text(verbatim: approval.subject ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .chatTextSelection()
                }
            case .tool:
                Text(verbatim: approval.subject ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .chatTextSelection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DSColor.chatBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        )
    }

    private func fileRow(_ file: ReplyApproval.FileLine) -> some View {
        HStack(spacing: DSSpacing.m) {
            Text(verbatim: file.mark)
                .foregroundStyle(DSColor.textSecondary)
            Text(verbatim: file.path)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DSSpacing.s)
            if let added = file.added, added > 0 || file.removed == 0 {
                Text(verbatim: "+\(added)").foregroundStyle(DSColor.chatSuccess)
            }
            if let removed = file.removed, removed > 0 {
                Text(verbatim: "−\(removed)").foregroundStyle(DSColor.attentionInk(.error))
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .monospacedDigit()
    }

    private var metaText: String? {
        var parts: [String] = []
        if let directory = approval.workingDirectory, !directory.isEmpty {
            let path = (directory as NSString).abbreviatingWithTildeInPath
            parts.append(AppLocalizedString.string("作業ディレクトリ", locale: locale) + " " + path)
        }
        if let tool = approval.toolName {
            parts.append(AppLocalizedString.string("ツール", locale: locale) + " " + tool)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - ボタン

    private var buttonRow: some View {
        HStack(spacing: 6) {
            Button { respond(.accept) } label: {
                buttonLabel("許可", key: isFocused ? "Y" : "⌥⌘↩")
            }
            .buttonStyle(ApprovalPrimaryButtonStyle(progress: armProgress, isArmed: isArmed))
            if approval.supportsSessionScope {
                Button { respond(.acceptForSession) } label: {
                    buttonLabel("このセッション中は許可", key: isFocused ? "S" : nil)
                }
                .buttonStyle(ApprovalSecondaryButtonStyle())
            }
            Button { respond(.decline) } label: {
                buttonLabel("拒否", key: isFocused ? "N" : "⌥⌘⌫")
            }
            .buttonStyle(ApprovalSecondaryButtonStyle())
            Spacer(minLength: DSSpacing.s)
            Button { respond(.cancel) } label: {
                buttonLabel("キャンセル", key: isFocused ? "Esc" : nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSColor.textSecondary)
        }
        .disabled(!isArmed)
    }

    private func buttonLabel(_ title: LocalizedStringKey, key: String?) -> some View {
        HStack(spacing: 5) {
            Text(title)
            if let key {
                Text(verbatim: key).opacity(0.7).font(.system(size: 10.5))
            }
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func respond(_ decision: ApprovalDecision) {
        guard isArmed else { return }
        Task { await viewModel.respond(to: approval, decision: decision) }
    }
}

struct ApprovalPrimaryButtonStyle: ButtonStyle {
    let progress: CGFloat
    let isArmed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(DSColor.accentFill.opacity(isArmed ? (configuration.isPressed ? 0.85 : 1) : 0.55),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            // 押せるようになるまでの進み具合（05 R6c）。
            .overlay(alignment: .bottomLeading) {
                if !isArmed {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: geo.size.width * progress, height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
    }
}

struct ApprovalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(DSColor.chatBackground.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
    }
}
