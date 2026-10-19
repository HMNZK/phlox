import Foundation
import Testing
import PhloxCore
@testable import Features

// セッション詳細の UX:
//   - 開いたら本文が後から届いても必ず最下部（最新）が見える（初回スクロールと追従）。

// MARK: - 初回スクロール

@Suite("セッション詳細: 開いたら最下部（最新）から見える")
struct SessionDetailInitialScrollTests {

    @Test("onAppear 時点で本文が空なら初回スクロールを消費しない")
    func emptyContentDoesNotConsumeInitialScroll() {
        var state = SessionDetailScrollFollowState()

        let decision = state.onContentChanged(hasContent: false, distanceFromBottom: 4000)

        #expect(decision == false, "本文が無い時点ではスクロール要求を出さないこと")
        #expect(
            state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == true,
            "空の通知で初回判定を使い切らず、本文が届いた最初の1回で最下部へ寄せること"
        )
    }

    @Test("本文が届いた最初の1回は最下部から遠くても必ず最下部へ寄せる")
    func firstContentArrivalScrollsToBottomRegardlessOfDistance() {
        var state = SessionDetailScrollFollowState()

        let decision = state.onContentChanged(hasContent: true, distanceFromBottom: 4000)

        #expect(
            decision == true,
            "初回表示は距離判定（80pt）に依らず最下部へ寄せること（最上部で開く退行の防止）"
        )
    }

    @Test("初回以降は最下部付近にいる時だけ追従する")
    func laterUpdatesFollowOnlyNearBottom() {
        var state = SessionDetailScrollFollowState()
        _ = state.onContentChanged(hasContent: true, distanceFromBottom: 0)

        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 0) == true)
        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 80) == true, "閾値ちょうどは追従する")
        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 81) == false, "閾値を超えたら追従しない")
        #expect(
            state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == false,
            "上へ読み戻している間は新着で引き戻さないこと（既存の追従方針を壊さない）"
        )
    }

    @Test("セッションを切り替えたら、また初回として最下部から開く")
    func sessionSwitchRestartsInitialScroll() {
        var state = SessionDetailScrollFollowState()
        _ = state.onContentChanged(hasContent: true, distanceFromBottom: 0)
        #expect(state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == false)

        state.reset()

        #expect(
            state.onContentChanged(hasContent: true, distanceFromBottom: 4000) == true,
            "別セッションを開いたら初回扱いに戻り、最下部から表示すること"
        )
    }

    @Test("初回追従後の空更新は追従閾値の判定を維持する")
    func emptyUpdatesAfterInitialFollowDoNotResetState() {
        var state = SessionDetailScrollFollowState()

        let initialDecision = state.onContentChanged(hasContent: true, distanceFromBottom: 10_000)
        let emptyDecision = state.onContentChanged(hasContent: false, distanceFromBottom: 0)
        let laterDecision = state.onContentChanged(hasContent: true, distanceFromBottom: 81)

        #expect(initialDecision)
        #expect(!emptyDecision)
        #expect(!laterDecision)
    }

    @Test("初回スクロール状態は本文到着で消費し、セッション切替で復帰する")
    func initialScrollStateTransitionsOnContentAndReset() {
        var state = SessionDetailScrollFollowState()

        #expect(!state.hasPerformedInitialScroll)
        let shouldInitiallyScroll = state.onContentChanged(hasContent: true, distanceFromBottom: 10_000)
        #expect(shouldInitiallyScroll)
        #expect(state.hasPerformedInitialScroll)

        state.reset()

        #expect(!state.hasPerformedInitialScroll)
    }

    @MainActor
    @Test("初回スクロールは描画できる本文だけを判定する")
    func renderableContentExcludesEmptyReasoningAndIncludesVisibleContent() async {
        let viewModel = SessionDetailViewModel(
            session: session(),
            api: MockAPI(messagesOutcome: .success([
                .reasoning(id: "m1", text: "   \n")
            ]))
        )

        await viewModel.load()

        #expect(!viewModel.chatMessages.isEmpty, "空の reasoning でも取得済みメッセージは存在する")
        #expect(viewModel.visibleMessages.isEmpty, "空白だけの reasoning は描画対象ではない")
        #expect(!SessionDetailView.hasRenderableContent(
            visibleMessages: viewModel.visibleMessages
        ))
        #expect(SessionDetailView.hasRenderableContent(
            visibleMessages: [.agent(id: "m2", text: "本文")]
        ))
    }

    @MainActor
    @Test("初回スクロールだけはアニメーションしない")
    func onlySubsequentScrollsAreAnimated() {
        #expect(!SessionDetailView.shouldAnimateScroll(hasPerformedInitialScroll: false))
        #expect(SessionDetailView.shouldAnimateScroll(hasPerformedInitialScroll: true))
    }

    @MainActor
    @Test("Reduce Motionでは初回も新着追従も位置を即時に確定する")
    func reducedMotionNeverAnimatesFollowingScroll() {
        #expect(!SessionDetailView.shouldAnimateScroll(hasPerformedInitialScroll: false, reduceMotion: true))
        #expect(!SessionDetailView.shouldAnimateScroll(hasPerformedInitialScroll: true, reduceMotion: true))
        #expect(ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: 80))
        #expect(!ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: 81))
    }

    // 例外のソース検査: `scrollToBottomForContentChange` は private な View メソッドで、SwiftUI の
    // ホストなしには呼べない。初回だけ即時にする正しさは評価順序に依存するため、ここで順序を守る。
    @Test("View は描画可能本文と初回状態の述語を経由してスクロールを決める")
    func viewRoutesScrollDecisionThroughNamedPredicates() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")
        let function = try #require(SourceFunction.body(named: "scrollToBottomForContentChange", in: source))

        #expect(function.contains("Self.hasRenderableContent("))
        #expect(function.contains("visibleMessages: viewModel.visibleMessages"))
        #expect(!function.contains("viewModel.chatMessages"))
        #expect(function.contains("Self.shouldAnimateScroll("))
        #expect(function.contains("hasPerformedInitialScroll: scrollFollowState.hasPerformedInitialScroll"))

        // 初回だけ即時にする正しさは評価順序に依存する。onContentChanged が
        // hasPerformedInitialScroll を true へ書き換える前に読まないと、初回もアニメーションに戻る。
        let animateIndex = try #require(function.range(of: "Self.shouldAnimateScroll(")).lowerBound
        let decideIndex = try #require(function.range(of: "scrollFollowState.onContentChanged(")).lowerBound
        #expect(
            animateIndex < decideIndex,
            "初回判定が消費される前に hasPerformedInitialScroll を読むこと（順序を入れ替えると初回もアニメーションする）"
        )
    }

    private func session() -> Session {
        Session(
            id: "whitebox-session",
            name: "Whitebox",
            agent: .claudeCode,
            status: .running,
            subtitle: "ターミナル",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}


// MARK: - ナビゲーションバー（端スワイプで戻る）

@Suite("セッション詳細: システムのナビゲーションバーを使う")
struct SessionDetailNavigationChromeTests {
    // 例外のソース検査（ADR 0033）: ナビバーを隠す・自前 topBar に戻すと端スワイプ pop が拒否される。
    // ADR 0033 のとおりこの症状は自動テストで再現できていないため、構成の逆戻りをソースで防ぐ。
    @Test("詳細画面の chrome はシステムのナビゲーションバーへ載せる（ADR 0033）")
    func detailChromeUsesSystemNavigationBar() throws {
        let source = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")
        let chrome = try SessionViewUXSource.text("Sources/DesignSystemIOS/Support/DSSessionNavigationChrome.swift")
        #expect(source.contains(".navigationStackHomeBackButton()"))

        #expect(chrome.contains(".navigationTitle(title)"))
        #expect(chrome.contains(".navigationBarTitleDisplayMode(.inline)"))
        let homeBackButton = try SessionViewUXSource.text("Sources/DesignSystemIOS/Support/NavigationStackHomeBackButton.swift")
        #expect(homeBackButton.contains("setBackIndicatorImage(house, transitionMaskImage: house)"))
        #expect(!chrome.contains(".toolbarRole(.editor)"))
        #expect(!source.contains(".toolbarRole(.editor)"))
        #expect(!chrome.contains(".toolbarBackground("))
        #expect(!chrome.contains(".toolbarColorScheme("))
        #expect(!chrome.contains(".toolbar(.visible, for: .navigationBar)"))
        #expect(chrome.contains("ToolbarItem(placement: .topBarTrailing) { trailingMenu }"))
        #expect(chrome.contains(".sharedBackgroundVisibility(.hidden)"))
        #expect(chrome.contains("private var trailingMenu: some View"))
        let ios26AvailabilityCheck = ["if ", "#available", "(iOS 26, *)"].joined()
        #expect(chrome.contains(ios26AvailabilityCheck))
        #expect(chrome.contains(".buttonStyle(.plain)"))
        #expect(chrome.contains(".glassSurface(.roundButton)"))
        #expect(chrome.contains(".frame(width: DSTouch.minSize, height: DSTouch.minSize)"))
        #expect(
            !source.contains("private var topBar"),
            "自前 topBar を復活させない（ナビバーを隠す構成へ戻ると端スワイプが壊れる）"
        )
        #expect(
            !source.contains("interactivePopGestureRecognizer"),
            "UIKit のジェスチャへ直接触らないこと"
        )
    }
}

// MARK: - ハーネス

/// テストファイル位置を起点に PhloxKit のソースを読む。
enum SessionViewUXSource {
    static func text(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/FeaturesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PhloxKit
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private enum SourceFunction {
    static func body(named name: String, in source: String) -> String? {
        guard let declarationRange = source.range(of: "func \(name)") else { return nil }
        guard let bodyStart = source[declarationRange.upperBound...].firstIndex(of: "{") else { return nil }

        var depth = 1
        var index = source.index(after: bodyStart)
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[bodyStart...index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
