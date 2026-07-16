---
status: active
last-verified: 2026-07-05
---

# ADR 0032: エージェントのブランドアイコンは DesignSystem の xcassets+SVG（actool）で組み込む——swift test では描画されない制約込み

## 文脈

チャットアバターとセッション行に Claude/Codex/Cursor の公式ロゴを表示する要求。素材は公式 SVG（Wikimedia Commons 取得の claude-ai-symbol.svg / chatgpt-logo.svg と既存 cursor-ai-code-icon.svg。`assets/icons/` が原本）。アプリにはそれまで画像アセット機構が存在しなかった（SF Symbols のみ・`Image("...")` 参照 0 件）。

## 決定

`Packages/DesignSystem/Sources/DesignSystem/Icons.xcassets` に imageset（`"preserves-vector-representation": true`、黒単色の codex ロゴのみ `template-rendering-intent: template` でテーマ前景色に追随）として登録し、`resources: [.process("Icons.xcassets")]` で処理する。表示は共通ビュー `AgentBrandIcon(descriptor:size:)`（ブランド 3 種はアセット、他 kind/カスタムは SF Symbol・頭文字フォールバック）。

## スパイクで実証した制約（本決定の核心・2026-07-05）

- **SwiftPM 単体（`swift build`/`swift test`/`swift run`）は xcassets を actool でコンパイルせず生フォルダのままコピーする**。`Image(_:bundle:)` は解決できず、ブランド画像は**常に空白描画**（エラーにならない）。
- **xcodebuild 経由（実アプリのビルド）では actool が走り**、`Assets.car` に Image(1x/2x)+Vector で同梱され、多色グラデ・mask 含め 3 アイコンとも警告ゼロで正しく描画される（スパイク＋`assetutil --info` で確認済み）。

**帰結（テスト規約）**: ブランド画像の実描画ピクセルを検証するテストを swift test に書いてはならない（永久 red）。swift test で検証するのは (a) フォールバック描画（SF Symbol は actool 非依存）、(b) アセット同梱（生 xcassets or Assets.car の存在）まで。実描画の確認は xcodebuild ビルド＋目視（または `assetutil --info`）で行う。

## 棄却した代替案

- **WebP ラスタ（当初 assets/ にあった 250px 素材）**: ベクタでなく、ユーザーが公式 SVG 再取得を選択（ゲート①）。
- **SVG→PDF/PNG 変換して plain resource で同梱**: swift test でも描画可能になる利点はあるが、変換工程でベクタ品質・原本性が落ちる。実アプリ経路（xcodebuild）では SVG がそのまま使えるため不要と判断。
- **実行時 SVG デコード**: macOS の公開 API に SVG デコーダがない（private CoreSVG 依存は不可）。

## 結果

- `swift run`+ImageRenderer の使い捨てプレビュー手法（CLAUDE.md 記載）はブランドアイコンには使えない。代替のオフスクリーン確認は `qlmanage -t` / `sips -s format png`（SVG 直変換）が使える。
- カスタムエージェントのアイコンは、未割当一覧では実 descriptor、プロジェクトツリーでは汎用フォールバックと非対称（ツリー行は catalog 非参照の `agentRef` 解決。既知の制限。対称化するなら `descriptorForPresentation` のツリー配線で対応可能）。
