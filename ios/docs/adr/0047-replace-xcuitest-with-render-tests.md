---
status: accepted
last-verified: 2026-10-17
---

# ADR 0047: UI の確認を XCUITest から描画テストに移し、UI テストのターゲットを消す

> **このファイルの役割**: iPhone アプリの画面の確認を、XCUITest（`PhloxMobileUITests`）から、シミュレーター上の単体テストで画面を PNG に書き出す描画テストへ移した決定と理由。
> **書かないもの**: 実行の手順（→ [delivery/0020](../delivery/0020-ios-redesign-plan.md) 6 章、`make -C ios snapshot`）。

## 文脈

UI テストは XCUITest 29 本（`ScreenshotTests`・`doc/screenshots/`・`scripts/compare-screenshots.py` を含む）。XCUITest の `typeText`・`typeKey` は Mac の入力ソースに「Unicode Hex Input」を自動で足すため、利用者の全体の規則で XCUITest は実行しない（2026-10-13）。実行できないテストは画面の回帰を守らない。一方、再設計では画面を見本（428×926・375×667、ライト・ダーク、Dynamic Type 最大）と見比べる手段が要る。macOS は既に、環境変数を立てたときだけ部品の画像を書き出す `DesignSnapshotRenderTests` を持っている。

## 決定

1. **アプリに載る単体テストのターゲット `PhloxMobileSnapshotTests` を足し、画面を PNG に書き出す。** 見本と同じ大きさ・外観・文字の大きさで描く。書き出すのは `PHLOX_DESIGN_SNAPSHOTS=1` のときだけで、出力先は worktree の `.verification/ios-redesign/snapshots/`。データは `run-simulator.sh --screen` と同じ見本のデータを使う。
2. **実行は専用のスキーム `PhloxMobileSnapshots`（UI テストを含めない）と `make -C ios snapshot` に限る。** 文字の入力はしない。
3. **`PhloxMobileUITests` のターゲットは段階 1 で消す**（計画書 D6）。画面の振る舞いは表示用の状態と ViewModel の単体テストで守り、見た目は描画テストの画像で確かめる。

## 棄却案

- **XCUITest を残し、入力を伴わないテストだけ走らせる**: 起動・操作の一部で `typeText` 相当が混じり、規則を機械的に守れない。29 本のうち再設計後も意味を持つものが少ない。
- **画像の自動比較（ピクセルの差分で合否）**: 盤面は HTML で、iOS の描画と画素が一致しない。比べるのは人（と PM）の目で、テストは書き出しまでにする。

## 結果

- 描画の方式（`ImageRenderer` か、ウィンドウに載せて撮るか）は段階 0 の実装で決め、テストのファイルの冒頭に理由を書く。
- 画面の構造に結び付いた UI テストの回帰の守りは無くなる。代わりに、振る舞いを ViewModel・表示用の状態の単体テストへ寄せる（計画書 7 章）。
- 比べる相手の盤面の画像は、見本の HTML を手元のブラウザで描いて書き出す（D4。計画書 6 章）。

## 段階 8a 追記（2026-10-18）

- 描画テストへ `Pair*`・`Set*` と一覧・チャット・新規作成・返答・シェル・使用量の未収録場面を加えた。盤面名・寸法・外観・文字サイズごとに PNG を出す。
- OS 標準メニュー・シート・アラート・キーボード、カメラ、Dynamic Island、押下中／引っ張り中の状態と注釈用の盤面は撮らない。理由と見比べの結果は [作業記録0028](../delivery/0028-ios-redesign-stage8-worklog.md) に記録する。
