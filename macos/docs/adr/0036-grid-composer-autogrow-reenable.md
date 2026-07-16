---
status: active
last-verified: 2026-07-06
---

# ADR 0036: グリッド入力欄の auto-grow 再有効化と `ComposerHeightBounds` 単一真実源

> **更新**: 安静時の高さ（grid=40 / single=44）は ADR 0044 で single/grid とも **80** に更新した（auto-grow 再有効化＝本 ADR の核は維持）→ **ADR 0046 がさらに 36 に変更**（「80px はパネル全体の見た目高さ」と解釈確定し ADR 0044 の高さ部分を supersede。現行の最小高は single/grid とも 36）。

- Status: Accepted
- Date: 2026-07-06
- 関連: ADR 0030（CPU 暴走根治・前提条件）、ADR 0010（描画中の @Observable 変更の教訓）、`DashboardFeature/Session/ComposerHeightPolicy.swift`、`DashboardFeature/Session/ChatSessionView.swift`（`GridComposerBar` / `IMESafeTextView`）

## 背景

グリッド表示のチャット入力欄 `GridComposerBar` は、導入時（339b41a）から一貫して**固定高 40** だった（デグレではない）。可変高にすると ADR 0010/0030 で観測された「レイアウト中の状態変更 → 再無効化」の CPU 100% 固着ハングを誘発したため、`min == max == 40` に固定する防御的回避策を取っていた。一方、単一表示 `ChatComposer` は初出から 44〜160 の auto-grow で健在。ユーザーはグリッドでも長文入力で高さが伸びることを要望した。

前提が変化した: ハングの真因（トランスクリプトの LazyVStack）は ADR 0030 決定#1 で VStack 化により根治済み。真因除去後の今、グリッドの可変高を再有効化できる。

## 決定

1. **グリッド入力欄を 40〜160 の可変（auto-grow）へ戻す**。下限 = 40（据置）、上限 = 160（単一表示と統一）。上限超は内部スクロール。
2. **高さ境界の単一真実源 `ComposerHeightBounds`** を `ComposerHeightPolicy.swift` に導入し、`single = 44/160`・`grid = 40/160` を集約する（分散ハードコードの排除）。
3. **既存の高さ機構をそのまま再利用し、新たな高さ駆動・同期書込を新設しない**。`ComposerHeightPolicy.resolvedHeight/shouldWrite`（純関数・クランプ・ceil・0.5pt 差分ガード）と、`IMESafeTextView` のイベント文脈書込（textDidChange）＋ `updateNSView` の遅延 Task はいずれも不変。これが Bug A（view update 中の @Binding 同期書込）と固着ループの再燃を防ぐ構造的な歯止め。
4. **検証分担**: 境界契約は `swift test`（受け入れテストを実装前に front-load・不変）＋二段独立レビューで PM が担保。**CPU 非固着の実機 runtime 判定はユーザーが実施**（swift test green はハングの非存在を保証しないため。ADR 0010 の教訓）。

## 棄却案

- **固定高 40 の維持**: 真因が除去済みの現在、防御的回避策を残す根拠が消失。単一表示との挙動非対称はユーザー体験の欠陥として残る。
- **グリッド専用の新しい高さ制御の新設**: 収束保証のない駆動系を増やすことは ADR 0030 の一方向化原則に逆行。既存機構の再利用のみ許可。

## 結果

- 実装差分は `ComposerHeightPolicy.swift`（Bounds 追加）・`ChatSessionView.swift`（`GridComposerBar` の測定値駆動 frame 化）・`ComposerHeightPolicyTests.swift` の 3 ファイルに閉じた。
- ユニット/受け入れテスト green・ヘッドレス E2E 17 tests pass・二段独立レビュー（persona-reviewer / Codex）とも pass。実機 runtime 検証（CPU 非固着）はユーザー実施で確認済み（2026-07-06）。
- リスク: CPU 固着ループの再燃。再現したら本 ADR の実装を即 revert し、固定高へ戻す。
