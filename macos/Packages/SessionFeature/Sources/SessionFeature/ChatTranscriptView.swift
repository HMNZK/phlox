import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

struct ChatTranscriptView: View {
    @Bindable var viewModel: ChatSessionViewModel
    @Binding private var requestedScrollTarget: String?
    private let transcript: [ChatItem]?
    private let showsThinkingIndicator: Bool
    private let contentMaxWidth: CGFloat?
    private let bottomScrollContentMargin: CGFloat
    private let onSelectSubAgent: (String) -> Void
    @State private var autoFollow = ChatAutoFollowController()
    /// Thinking は transcript の最下部セルなので、最下部が viewport 外なら TimelineView を止める。
    /// 値は NSScrollView の bounds 変更イベントからのみ更新する。
    @State private var isThinkingIndicatorInViewport = true
    // 表示件数制限（末尾 N 件のみ描画。ADR 0030:22）。view-local な @State に住み、
    // body 評価中には書かない（visibleRange は読み取りのみ）。expand はボタン action、
    // reset はセッション切替の onChange から呼ぶ（ADR 0010: 描画中 state 変更の禁止）。
    @State private var window: TranscriptWindow
    // 遅延 scrollTo の世代トークン。ジャンプごと・セッション切替ごと・展開ごとに増やし、pending 遅延
    // Task は捕捉した世代が現在値と一致するときだけ scrollTo する（stale/後続操作時の誤スクロール防止）。
    @State private var jumpGeneration = 0
    // 「以前のメッセージを表示」押下時に、展開前の先頭可視 item の id を捕捉して置く一時アンカー。
    // 展開後にビューポートが履歴の先頭へ飛ぶのを防ぎ、押下時に見えていた位置へ留めるための単発シグナル
    // （requestedScrollTarget と同じ @State ワンショット方式・ScrollViewReader レベルの onChange で処理）。
    @State private var pendingExpandAnchor: String?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    init(
        viewModel: ChatSessionViewModel,
        transcript: [ChatItem]? = nil,
        showsThinkingIndicator: Bool = true,
        contentMaxWidth: CGFloat? = nil,
        bottomScrollContentMargin: CGFloat = 0,
        requestedScrollTarget: Binding<String?> = .constant(nil),
        presentationContext: TranscriptPresentationContext = .single,
        onSelectSubAgent: @escaping (String) -> Void = { _ in }
    ) {
        _viewModel = Bindable(wrappedValue: viewModel)
        _requestedScrollTarget = requestedScrollTarget
        self.transcript = transcript
        self.showsThinkingIndicator = showsThinkingIndicator
        self.contentMaxWidth = contentMaxWidth
        self.bottomScrollContentMargin = bottomScrollContentMargin
        _window = State(initialValue: TranscriptWindow(context: presentationContext))
        self.onSelectSubAgent = onSelectSubAgent
    }

    var body: some View {
        let _ = themeID
        ScrollViewReader { proxy in
            let transcriptSignal = transcriptFollowSignal
            let items = transcriptItems
            ScrollView {
                transcriptContent(items: items, transcriptSignal: transcriptSignal)
                    .background(
                        ChatAutoFollowScrollObserver(
                            controller: autoFollow,
                            onViewportVisibilityChanged: updateThinkingIndicatorViewport
                        )
                    )
            }
            .onChange(of: transcriptSignal) { _, newSignal in
                scrollToBottomIfNeeded(
                    proxy,
                    trigger: .transcript(newSignal)
                )
            }
            .onChange(of: viewModel.status) { _, newStatus in
                scrollToBottomIfNeeded(
                    proxy,
                    trigger: .status(newStatus)
                )
            }
            .onChange(of: requestedScrollTarget) { _, target in
                guard let target else { return }
                jumpToTarget(target, proxy: proxy)
                requestedScrollTarget = nil
            }
            .onChange(of: pendingExpandAnchor) { _, anchor in
                // 「以前のメッセージを表示」押下による展開後、押下時の先頭可視 item を
                // ビューポート上端へ据える（履歴の一番最初へ飛ばさず、そこから上へ遡れるように）。
                // window 拡張で上に挿入された行がレンダされた後に届くよう次の MainActor ターンへ遅延。
                // scroll 観測には連動しない単発イベント（ADR 0030 非該当）。世代ガードで stale を無効化。
                guard let anchor else { return }
                pendingExpandAnchor = nil
                jumpGeneration += 1
                let generation = jumpGeneration
                Task { @MainActor in
                    guard generation == jumpGeneration else { return }
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
            .onChange(of: viewModel.id) { _, _ in
                // セッション切替（vm identity 変化）で表示件数を既定へ戻す。
                // イベント文脈での mutation なので body 中の観測 state 変更にならない（ADR 0010）。
                window.reset()
                // 直前セッションの pending 遅延 scrollTo を無効化する（stale target 防止）。
                jumpGeneration += 1
            }
            .onAppear {
                scrollToBottomIfNeeded(proxy, trigger: .appear)
            }
        }
        .background(DSColor.chatBackground)
    }

    @ViewBuilder
    private func transcriptContent(
        items: [ChatItem],
        transcriptSignal: TranscriptFollowSignal
    ) -> some View {
        if let contentMaxWidth {
            VStack(spacing: 0) {
                transcriptStack(items: items, transcriptSignal: transcriptSignal)
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        } else {
            transcriptStack(items: items, transcriptSignal: transcriptSignal)
        }
    }

    private func transcriptStack(
        items: [ChatItem],
        transcriptSignal: TranscriptFollowSignal
    ) -> some View {
        // IMPORTANT(CPU 暴走の根治・task-8): ここは意図的に Lazy でない VStack。
        // LazyVStack だと「実行中タイルの更新と同時のスクロール」で行の実体化/破棄と
        // anchor translation の不動点が成立しなくなり、入力が止まっても自走し続ける
        // 再レイアウトループ（CPU 55-100% 固着・body 再評価ゼロ・state 書込ゼロ）に
        // 陥ることを実機の単一変数対照実験で確定した（2026-07-05・E6 暴走/E7 収束、
        // スクロール体感差なし。詳細は ADR 0030）。Lazy 化を再導入しないこと。
        // 長大トランスクリプトの先行レイアウトコストは「末尾 N 件のみ描画」（window）で
        // 抑える（遅延機構の再導入ではなく件数制限。ADR 0030:22）。
        // window は totalCount のみに依存する純関数で、スクロール量・可視領域には連動しない。
        let range = window.visibleRange(totalCount: items.count)
        // window 境界以降だけを集約する。境界がグループ内部なら後半だけの部分ブロックにし、
        // id は全 transcript 上のグループ先頭 item.id に固定する。これにより描画数を window 上限内に
        // 保ちつつ、展開で部分ブロックの内容が増えても identity を揺らさない（ADR 0030）。
        let visibleSlice = ChatTranscriptGrouping.visibleSlice(from: items, startingAt: range.startIndex)
        return VStack(alignment: .leading, spacing: DSSpacing.m) {
            if visibleSlice.hiddenItemCount > 0 {
                // 展開前の先頭可視 item をアンカーに（押下時に見えていた最初のメッセージ）。
                loadEarlierButton(
                    hiddenCount: visibleSlice.hiddenItemCount,
                    anchorID: visibleSlice.blocks.first?.id
                )
            }
            ForEach(visibleSlice.blocks) { block in
                transcriptBlock(block.content, lastTranscriptID: transcriptSignal.lastID)
                    .id(block.id)
            }
            if shouldShowThinkingIndicator {
                ThinkingIndicatorCell(
                    descriptor: agentDescriptor,
                    recap: { viewModel.recap(now: $0) },
                    hangAssessment: { viewModel.hangAssessment(now: $0) },
                    onInterrupt: { await viewModel.turnInterrupt() },
                    isInTranscriptViewport: isThinkingIndicatorInViewport
                )
                    .id("chat-thinking")
            }
            // 浮遊 composer の逃し余白はスクロールコンテンツ内部のスペーサーで確保する。
            // .contentMargins(for: .scrollContent) は macOS ではオーバーレイスクローラも
            // インセットしてしまい（2026-07-10 実機実測: つまみ終端＝下端−composer高）、
            // 「バーを画面下端まで届かせる」目的が達成できない。コンテンツ内スペーサーは
            // スクローラ形状に影響しない。scrollTo("chat-bottom", anchor: .bottom) が
            // このスペーサー下端を viewport 下端に揃えるため、最終メッセージは composer 上に出る。
            Color.clear
                .frame(height: max(1, bottomScrollContentMargin))
                .id("chat-bottom")
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.m)
    }

    @ViewBuilder
    private func transcriptBlock(_ block: ChatTranscriptBlock, lastTranscriptID: String?) -> some View {
        switch block {
        case .single(let item):
            ChatItemView(
                item: item,
                isRunningCommand: isRunningCommand(item, lastTranscriptID: lastTranscriptID),
                agentDescriptor: agentDescriptor,
                onSelectSubAgent: onSelectSubAgent,
                onRespondToUserQuestion: { requestId, answers in
                    await viewModel.respondToUserQuestion(requestId: requestId, answers: answers)
                }
            )
        case .commandGroup(_, let items):
            CommandGroupCell(
                items: items,
                lastTranscriptID: lastTranscriptID,
                isTurnRunning: viewModel.status.isRunning
            )
        }
    }

    /// 先頭に隠れた古いメッセージを段階的に表示するボタン。
    /// window の拡張契機は「このボタンの押下のみ」。スクロール位置・可視領域には一切連動しない
    /// （ADR 0030 再入禁止）。expand はボタン action での mutation なので body 中書込にならない。
    /// - Parameter anchorID: 押下時の先頭可視 item の id。展開後にこの位置へ留めるためのアンカー。
    private func loadEarlierButton(hiddenCount: Int, anchorID: String?) -> some View {
        Button {
            // anchorID は描画時（＝展開前）の先頭可視 item。展開して上に古い行を追加し、
            // その後アンカー位置へ留めるシグナルを立てる（ビューポートを履歴先頭へ飛ばさない）。
            window.expand()
            pendingExpandAnchor = anchorID
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "chevron.up")
                Text("以前のメッセージを表示")
                Text("残り \(hiddenCount) 件")
                    .font(DSFont.caption)
            }
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.chatTextSecondary)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .background(DSColor.fillSubtle, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ChatTranscript.loadEarlier")
        .id("chat-load-earlier")
    }

    private var agentDescriptor: AgentDescriptor {
        if let kind = viewModel.agentRef.builtinKind {
            return AgentRegistry.descriptor(for: kind)
        }
        return AgentDescriptor(
            ref: viewModel.agentRef,
            displayName: viewModel.agentRef.id,
            binaryName: viewModel.agentRef.id,
            symbolName: "terminal",
            colorRGB: AgentRGB(0x8A, 0x8F, 0x98),
            bypassKey: "phlox.bypass.\(viewModel.agentRef.id)",
            launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
        )
    }

    private var shouldShowThinkingIndicator: Bool {
        showsThinkingIndicator && viewModel.showsProcessingIndicator
    }

    private var transcriptItems: [ChatItem] {
        transcript ?? viewModel.transcript
    }

    private var transcriptFollowSignal: TranscriptFollowSignal {
        TranscriptFollowSignal(
            count: transcriptItems.count,
            lastID: transcriptItems.last?.id,
            lastContentLength: transcriptItems.last.map(lastContentLength) ?? 0
        )
    }

    private func isRunningCommand(_ item: ChatItem, lastTranscriptID: String?) -> Bool {
        guard case .commandExecution = item else { return false }
        return item.id == lastTranscriptID && viewModel.status.isRunning
    }

    private func lastContentLength(for item: ChatItem) -> Int {
        switch item {
        case .userMessage(_, let text, _, _),
             .agentMessage(_, let text, _),
             .reasoning(_, let text, _),
             .error(_, let text, _):
            text.utf8.count
        case .commandExecution(_, let command, let output, _):
            (command?.utf8.count ?? 0) + output.utf8.count
        case .fileChange(_, let changes, _):
            changes.reduce(0) { partial, change in
                partial + change.path.utf8.count + change.diff.utf8.count
            }
        case .subAgentMarker(_, let subagentType, let description, let status):
            subagentType.utf8.count + description.utf8.count + status.rawValue.utf8.count
        case .turnCost:
            0
        case .userQuestion(_, _, let questions, let answers, let state, _):
            // 回答・状態の変化を content 変化として検知させる（windowing/自動追従の更新判定用）。
            questions.count + (answers?.values.reduce(0) { $0 + $1.count } ?? 0) + state.rawValue.utf8.count
        }
    }

    /// NSScrollView のスクロールイベント側でのみ呼ばれる。body 内では変更しない。
    private func updateThinkingIndicatorViewport(_ isInViewport: Bool) {
        guard isThinkingIndicatorInViewport != isInViewport else { return }
        isThinkingIndicatorInViewport = isInViewport
    }

    /// ユーザー起点のジャンプ（実行中バックグラウンドタスク・sub-agent 等への飛び先）を処理する。
    /// windowing で対象行が隠れ域（既定 N 件より前）にあると scrollTo は無言 no-op になり、
    /// AutoFollow 離脱だけが起きて目的地に行かない壊れた操作になる（ステージ1 HIGH 指摘）。
    /// 裁定=案b（reveal-on-jump）: 隠れ域ターゲットは scrollTo の前に window を広げて可視化する。
    /// 集約された command の個別 id は折りたたみ中のビュー階層に存在しないため、全 transcript 上で
    /// 安定した block id（group は先頭 item.id）へ解決してから scrollTo する。
    /// これはユーザー操作起点であり、スクロール量・可視領域の観測連動ではない（ADR 0030 非該当）。
    private func jumpToTarget(_ target: String, proxy: ScrollViewProxy) {
        autoFollow.userInitiatedJump()
        // 新しいジャンプは以前の pending 遅延 scrollTo を無効化する。
        jumpGeneration += 1
        let generation = jumpGeneration
        let currentItems = transcriptItems
        let scrollTarget = ChatTranscriptGrouping.scrollTargetID(containing: target, in: currentItems)
        // 対象が現セッションの items にあり、かつ隠れ域なら reveal してから遅延 scrollTo。
        if let index = currentItems.firstIndex(where: { $0.id == target }) {
            let start = window.visibleRange(totalCount: currentItems.count).startIndex
            if index < start {
                window.reveal(index: index, totalCount: currentItems.count)
                // window 拡張（@State 書込）で新規行がまだ未レンダのため、同一イベント内 scrollTo は
                // 空振りしうる。次の MainActor ターンへ遅延させ、再レンダ後に確実に届かせる。
                // 遅延中に後続ジャンプ・セッション切替（reset）が来たら世代不一致で何もしない。
                Task { @MainActor in
                    guard generation == jumpGeneration else { return }
                    proxy.scrollTo(scrollTarget, anchor: .center)
                }
                return
            }
        }
        // 可視域 or items に存在しない別セッション id: 従来どおり即 scrollTo（no-op を含む）。
        proxy.scrollTo(scrollTarget, anchor: .center)
    }

    private func scrollToBottomIfNeeded(
        _ proxy: ScrollViewProxy,
        trigger: ChatScrollTrigger
    ) {
        switch trigger {
        case .appear:
            guard autoFollow.isFollowing else { return }
        case .transcript, .status:
            guard autoFollow.contentDidChange() else { return }
        }
        proxy.scrollTo(ChatScrollTarget.bottom.rawValue, anchor: .bottom)
    }
}

private struct TranscriptFollowSignal: Equatable {
    let count: Int
    let lastID: String?
    let lastContentLength: Int
}

private enum ChatScrollTarget: String, Equatable {
    case bottom = "chat-bottom"
}

private enum ChatScrollTrigger: Equatable {
    case appear
    case transcript(TranscriptFollowSignal)
    case status(SessionStatus)
}
