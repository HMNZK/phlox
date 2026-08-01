import AppKit
import Foundation
import Testing
@testable import SessionFeature

// task-1（Thinking インジケータの可視性シグナルが固着する不具合）の受け入れテスト。
// PM が著す不変の契約（実装役は編集禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約の骨子:
// - ChatAutoFollowScrollEventBridge は「最下部が見えているか」を、スクロールイベントだけでなく
//   **コンテンツ側の寸法変化**（documentView の frame 変化）でも再評価しなければならない。
// - 一度 false を報告したあと、スクロールイベントが一切来なくても、コンテンツが縮んで
//   実態が at-bottom へ戻ったら true を報告し直さなければならない（＝固着しない）。
//
// なぜこれが要るか: この可視性シグナルは ThinkingIndicatorCell のシマー（CALayer pause）と
// 経過秒（HangStatusTimelineSchedule）の両方を止める唯一のゲートである。スクロール通知でしか
// 更新されないと、サブエージェントペインの開閉・ストリーミング中のコンテンツ伸縮で false が
// 焼き付き、セッションが静かな間は復帰しない（ADR 0067 決定4 の配線の欠陥）。

@MainActor
private final class ViewportSignalRecorder {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }
}

/// clip view より高い documentView を持つスクロールビューを組み、最下部まで送った状態で返す。
@MainActor
private func makeScrollViewScrolledToBottom(
    viewportHeight: CGFloat = 400,
    contentHeight: CGFloat = 1000
) -> (scrollView: NSScrollView, documentView: NSView) {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: viewportHeight))
    let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: contentHeight))
    scrollView.documentView = documentView
    scrollView.layoutSubtreeIfNeeded()
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: contentHeight - viewportHeight))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    return (scrollView, documentView)
}

@MainActor
private func makeBridge(
    recorder: ViewportSignalRecorder
) -> ChatAutoFollowScrollEventBridge {
    ChatAutoFollowScrollEventBridge(
        controller: ChatAutoFollowController(),
        onViewportVisibilityChanged: { recorder.record($0) },
        onViewportCenterChanged: { _ in }
    )
}

// MARK: - ハーネスの健全性（この2件が赤なら契約ではなくテスト側の欠陥）

@MainActor
@Test
func harness_scrollViewStartsAtBottom() {
    let (scrollView, _) = makeScrollViewScrolledToBottom()
    #expect(ChatAutoFollowGeometry.isAtBottom(scrollView))
}

@MainActor
@Test
func harness_attachReportsInitialVisibility() {
    let recorder = ViewportSignalRecorder()
    let bridge = makeBridge(recorder: recorder)
    let (scrollView, _) = makeScrollViewScrolledToBottom()

    bridge.attach(to: scrollView)
    defer { bridge.detach() }

    #expect(recorder.values == [true])
}

// MARK: - 契約 1: コンテンツが伸びたら（スクロールせずに）非可視を報告する

@MainActor
@Test
func viewportSignal_reportsFalse_whenContentGrowsWithoutScrolling() {
    let recorder = ViewportSignalRecorder()
    let bridge = makeBridge(recorder: recorder)
    let (scrollView, documentView) = makeScrollViewScrolledToBottom()

    bridge.attach(to: scrollView)
    defer { bridge.detach() }
    #expect(recorder.values == [true])

    // スクロールは一切行わない。コンテンツだけが縦に伸びる
    // （新着デルタの追加・サブエージェントペインを開いた際の折り返し増加に相当）。
    documentView.frame = NSRect(x: 0, y: 0, width: 400, height: 2000)

    #expect(
        recorder.values == [true, false],
        "コンテンツの伸長で最下部が viewport から外れたのに再評価されていない（記録: \(recorder.values)）"
    )
}

// MARK: - 契約 2: 固着しない（コンテンツが縮んだら可視へ戻る）

@MainActor
@Test
func viewportSignal_recoversToTrue_whenContentShrinksWithoutScrolling() {
    let recorder = ViewportSignalRecorder()
    let bridge = makeBridge(recorder: recorder)
    let (scrollView, documentView) = makeScrollViewScrolledToBottom()

    bridge.attach(to: scrollView)
    defer { bridge.detach() }

    documentView.frame = NSRect(x: 0, y: 0, width: 400, height: 2000)
    // 描画予算による先頭ブロックの脱落・カードの畳み込みでコンテンツが縮み、
    // 実態としては再び最下部が見えている状態に戻る。スクロールは発生しない。
    documentView.frame = NSRect(x: 0, y: 0, width: 400, height: 1000)

    #expect(
        recorder.values == [true, false, true],
        "コンテンツの伸縮だけで false → true へ復帰できていない（＝スクロールが来るまで固着する。記録: \(recorder.values)）"
    )
}

// MARK: - 契約 3: 値が変わらない寸法変化では通知を増やさない（帰還ループの燃料にしない）

@MainActor
@Test
func viewportSignal_doesNotRepeatUnchangedValue_onNoOpResize() {
    let recorder = ViewportSignalRecorder()
    let bridge = makeBridge(recorder: recorder)
    let (scrollView, documentView) = makeScrollViewScrolledToBottom()

    bridge.attach(to: scrollView)
    defer { bridge.detach() }

    // 幅だけを変える。最下部との距離は変わらないので可視性の値は true のまま。
    documentView.frame = NSRect(x: 0, y: 0, width: 500, height: 1000)
    documentView.frame = NSRect(x: 0, y: 0, width: 600, height: 1000)

    #expect(
        recorder.values == [true],
        "値が変わっていないのにコールバックが重複発火している（記録: \(recorder.values)）"
    )
}

// MARK: - 契約 4: detach 後は寸法変化に反応しない（購読漏れの検出）

@MainActor
@Test
func viewportSignal_stopsAfterDetach() {
    let recorder = ViewportSignalRecorder()
    let bridge = makeBridge(recorder: recorder)
    let (scrollView, documentView) = makeScrollViewScrolledToBottom()

    bridge.attach(to: scrollView)
    bridge.detach()

    documentView.frame = NSRect(x: 0, y: 0, width: 400, height: 2000)

    #expect(
        recorder.values == [true],
        "detach 後も通知を受け取っている（購読解除漏れ。記録: \(recorder.values)）"
    )
}
