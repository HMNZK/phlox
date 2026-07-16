---
status: active
last-verified: 2026-07-06
---

# ADR 0037: チャット自動追従の離脱判定をオフセット推測からユーザー操作イベント駆動へ

- Status: Accepted
- Date: 2026-07-06
- 関連: ADR 0030（トランスクリプト非遅延レイアウト・計測一方向化）、ADR 0010（描画中の @Observable 変更禁止）、`DashboardFeature/Session/ChatAutoFollow.swift`（新設）、`DashboardFeature/Session/ChatSessionView.swift`（`ChatTranscriptView`）

## 背景

チャットモード（単一表示・グリッド共通の `ChatTranscriptView`）はストリーミング中に最下部へ自動追従するはずが、実際には古い位置に留まり恒久停止するバグがあった。

真因: 旧 `ChatAutoFollowController` は末尾マーカーの `bottomOffset`（PreferenceKey 計測）1変数で「ユーザーが手動離脱したか」を判定していた。しかしこの値は **「ユーザーが上へスクロールした」場合と「ストリーミングでコンテンツが伸びて下端が押し下げられた」場合の両方で増える**ため、単一スカラーでは弁別不能。1回の更新で 80pt しきい値を超える伸長（または scrollTo 実行前に PreferenceKey 更新が先着するレース）で、無操作でも「手動離脱」と誤認して追従を止め、以後復帰しなかった。

## 決定

1. **離脱はユーザー操作イベントのみが引き起こす**。`NSScrollView.willStartLiveScrollNotification` / `didEndLiveScrollNotification`（ユーザー起因スクロールのみで発火し、プログラム起因 `scrollTo` では発火しない）を introspection 用の小さな NSViewRepresentable で購読する。オフセット値からの離脱推測は全廃（`ChatBottomOffsetPreferenceKey` ごと撤去）。
2. **状態機械は3状態**（`ChatAutoFollowController`・専用ファイル・非 @Observable）: following（追従中）/ userScrolling（操作中）/ detached（離脱中）。コンテンツ増加は状態を一切変えない。位置変化（contentView の `boundsDidChange`）は **detached 中に最下部へ達したときの復帰にのみ**使う（慣性スクロールが didEndLiveScroll 後に最下部へ滑り込むケースを拾う。following/userScrolling 中は no-op＝自前 scrollTo の誤検知防止）。
3. **メッセージジャンプ（`requestedScrollTarget`）はユーザー意図の離脱**として `userInitiatedJump()` で detached へ遷移させる（following のまま残すと次のデルタで最下部へ引き戻される）。ジャンプ先が最下部近傍なら着地後の位置変化で自然に追従再開する。
4. `isAtBottom` は NSScrollView ジオメトリから導出（`documentVisibleRect.maxY >= documentView.frame.maxY - 80`。ビューポートより短いコンテンツは常に最下部扱い）。しきい値 80pt は旧実装の定数を踏襲。
5. 状態機械の意味論は受け入れテスト `ChatAutoFollowAcceptanceTests`（12本）で凍結。核心契約は「**コンテンツ増加だけでは追従は絶対に解除されない**」。

## 棄却案

- **SwiftUI `onScrollPhaseChange`**: 意味論的には最適だが macOS 15+ であり、デプロイターゲット 14.0 で使えない。
- **オフセットヒューリスティクスの改良**（伸長中は解除を抑止するゲート等）: 伸長とユーザースクロールが同時に起きるケースを1変数では原理的に弁別できず、従来バグの変種を残す。
- **@Observable 化・PreferenceKey 継続**: 追従状態の変化で view を無効化する経路や計測フィードバックの再導入は ADR 0010/0030 に逆行。

## 結果

- 単一表示・グリッドは `ChatTranscriptView` 共有のため1箇所の修正で両対応。
- swift test 684 green（受け入れ12＋白箱5含む）・ヘッドレス E2E 17 pass・二段独立レビュー通過（詳細は delivery 0020）。
- **実機 runtime 検証はユーザーが実施**（追従継続・トラックパッド/マウスホイール両方での離脱・最下部復帰・CPU 非固着。レガシーマウスホイールでの live-scroll 通知発火は AppKit 挙動が未確認のため実機確認が必須）。
- 既知の理論上の限界: `userInitiatedJump` はドラッグ中（userScrolling）も detached へ上書きするが、ドラッグとジャンプ操作の同時発火は実 UI で不可能なため実害なし（ステージ1レビュー LOW）。
