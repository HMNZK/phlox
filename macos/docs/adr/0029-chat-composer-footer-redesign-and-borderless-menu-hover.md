---
status: active
last-verified: 2026-07-04
---

# ADR 0029: チャット入力欄（composer）フッター再設計と borderlessButton Menu のホバー/描画制約への対処

## 文脈

チャット（app-server）セッションの入力欄フッターを、参考 UI（Codex/Claude の composer）に寄せて再設計した。要求は実機フィードバックで反復的に固まった: (1) 設定コントロールを左右に振り分け（左=権限系、右=モデル/effort）、(2) PLAN を独立トグルから権限/モード選択へ統合、(3) 文字・ボタンの質感（透過グレー・ホバーで色変化）、(4) 入力欄をコンテンツ領域とシームレスに一体化（同色・境界線を目立たせない）、(5) 入力欄をメインカラム幅の一定割合で中央表示。

再設計中に **SwiftUI の `Menu`（`.menuStyle(.borderlessButton)`）に関する2つの実測制約**に突き当たり、これがホバー・ボタン質感の実装方式を規定した。

## 決定

### (A) フッターの左右分割は純関数を単一真実源にする
`composerControls(for:side:)`（trailing = `{.model, .effort}`、leading = 残りを元順で）を追加し、単一表示（`ChatComposer`）とグリッド（`GridComposerBar`）が同じ関数から左右のコントロール集合を得る。受け入れテストで3ビルトイン（claude/codex/cursor）のマッピングを凍結。

### (B) PLAN を権限/モードドロップダウンへ排他統合する
独立 Plan トグルを廃し、`composerModeOptions(for:codexProfileIDs:)`（純関数・単一真実源）が権限/モード項目の末尾に Plan を足す。`.plan` は `composerControls(for:)` から除去。排他制御はエージェント種別で非対称:
- Claude/Cursor（spawn agent）: 既存 `setSpawnAgentPermission("plan")` が `isPlanMode` を一元管理（"plan"→ON、他→OFF）＝UI は値を渡すだけで排他が成立。
- Codex: `permissions` と `collaborationMode` が別フィールドのため、プロフィール選択時に **`setPermissionProfile(id)` に加えて（Plan 中だったら）`setPlanMode(false)` も呼ぶ**。これを怠ると「Plan かつ プロフィール」の二重状態が残る（名指しハザード）。

### (C) borderlessButton Menu のホバーは AppKit NSTrackingArea で取り、背景・サイズは Menu の「外側」で与える【最重要の再利用知見】
実測した制約:
- **`.onHover` は `.borderlessButton` の `Menu` を包む View に配送されない**（label 内側でも wrapper 外側でも発火しない）。→ ホバー検知は AppKit の `NSTrackingArea`（`HoverReporter` = `NSViewRepresentable`）を `.background` に置き、mouseEntered/Exited で state を更新する（クリックは奪わないので Menu と両立）。
- **borderlessButton Menu はラベルの `.background`/`.frame`/`.padding` を描画・反映しない**（テキストだけ通る）。→ ボタン背景（グレー透過・ホバー時の色変化）とボタン領域サイズ（`minHeight`・水平 padding）は、ラベル内側でなく **Menu を包むラッパー（`HoverableComposerControl`）**で与える。
- 対照的に、Menu でない要素（"+" プレースホルダ・送信ボタン）は素の `.onHover`/`.background` が効く。

ホバー state の更新は mouseEntered/Exited・onChange 等の**イベント駆動に限定**し、body/派生プロパティ評価中に mutate しない（ADR 0010 の描画中 state 変更ループの再発防止）。

### (D) 入力欄をコンテンツ領域とシームレスに一体化する
- composer パネル/ストリップ背景を `chatElevated`/`chatCard` から **コンテンツ領域と同じ `chatBackground`** に統一し、色差をなくす。トランスクリプトと composer 間の Divider を除去。
- 区別は**ごく薄い枠（white 6%）**のみ＋パネルに**薄いグレー味（white 4%）**を足して軽く強調。
- 文字色は入力欄プレースホルダーと同色（`chatTextSecondary`）に揃える。

### (E) 入力欄の幅はメインカラム実測ベースで 60%（上限 800px）／狭幅時 90%
- `.containerRelativeFrame` は当レイアウトで container がペインに解決されず**ほぼ全幅のまま効かなかった**ため不採用。
- `mainColumn`（VStack）の実幅を `GeometryReader`（`.background`）で計測し `@State mainColumnWidth` に `onChange` で保持、`ChatComposer` を `.frame(maxWidth: composerMaxWidth).frame(maxWidth: .infinity)`（中央寄せ）にする。
- `composerMaxWidth`: 基本はカラム幅 60% を上限 800px でクランプ。ただし 60% が 800px 未満（狭カラム）のときは窮屈さ回避で全幅 90%。計測前は `nil`（制約なし）。
- **ADR 0010 安全**: 計測対象は外的に決まるカラム幅（composer 幅に非依存）で、composer は外側 `.frame(maxWidth: .infinity)` によりレイアウト占有が全幅のまま＝計測値を動かさない。よって `mainColumnWidth` 更新→再計測のフィードバックループが構造的に起きない。`abs差>0.5` ガードで冗長更新も抑止。

## 結果 / トレードオフ
- ホバー・ボタン質感が実機で機能し、composer が参考 UI に一致（実機 screencapture/cliclick で確認）。
- borderlessButton Menu の描画制約を「外側ラッパー＋NSTrackingArea」で回避する方式は、今後 Menu ベースの装飾チップを足す際の定石になる（(C) が再利用知見）。
- レイアウト（左右分割・幅・中央寄せ）は SwiftUI の単体テスト対象外で runtime 目視に依存する（受け入れテストは純関数マッピングのみ凍結）。
- Codex の Plan 排他はサーバ側 thread settings のマージ順（permissions→collaborationMode）に依存する余地が残るが、UI 状態は両方向で解消済み（runtime 確認）。

## 関連
- ADR 0010（描画中 state 変更による CPU 固着）— 本 ADR の (C)(E) はその制約下でイベント駆動・ループ不在を徹底。
- delivery/0012（本 run の作業経緯・タスク分解・検証）。
