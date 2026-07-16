---
status: active
last-verified: 2026-07-11
---

# 0078: チャット composer footer は幅駆動の3段階適応レイアウトにする

## 文脈

チャット composer は transcript の `.overlay(alignment: .bottom)`（クリップなし）に置かれ、`.frame(maxWidth:)` は上限しか課さない。footer の設定コントロール群（model/effort/permission/mode/branch）は `.fixedSize(horizontal: true)` で水平圧縮を拒むため、**footer の固有最小幅が提案幅を超えると中央揃えのまま左右へあふれる**。ドロワー＋左サイドバー・右サイドバー（使用量インスペクタ）・グリッドタイル（実測約290pt）で実際にはみ出しがユーザー報告された（2026-07-11、スクリーンショット4枚）。

実測の固有最小幅: standard 559pt / compact 479pt / minimal 157pt。

## 決定

1. **footer レイアウトを `ComposerFooterLayout`（standard / compact / minimal）の3段階にし、幅から純関数で選択する**。
   - 単一表示: `ComposerLayout.controlsLayout(proposedWidth:)` — 600pt 未満→compact、490pt 未満→minimal。
   - グリッド: `ComposerLayout.gridControlsLayout(proposedWidth:)` — **standard を返さない**（490pt 以上→compact、未満→minimal）。タイルは常に狭く、広いタイルでも従来どおり compact が上限。
2. **minimal は設定を overflow メニュー（ellipsis.circle・`ComposerSettingsOverflowMenu`）へ集約**する。agent 種別ごとの設定集合（Claude=model/effort/permission、Codex=model/permission、Cursor=model/mode）＋ブランチをサブメニューで全て到達可能に保つ。
3. **幅は単一真実源から一方向に流す**: 親（ChatSessionView / GridChatColumn）が GeometryReader の幅を `ComposerLayout.proposedWidth(mainColumnWidth:)` → 純関数に通して footer へ注入する。body 評価中に @Observable state へ書き戻さない（ADR 0010 の再無効化ループ防止規約に準拠）。
4. **グリッドと単一表示で footer 部品を共有する**（`ChatComposerFooter`・`ComposerSendButton` 再利用）。グリッド専用の二重実装を作らない。副作用として compact 時のグリッド送信ボタンの見た目が微変化（角丸 DSRadius.s→m・無効時の背景ピルが clear）するが、挙動不変・一貫性向上として受容した（decision-log 2026-07-11 裁定）。

## 棄却した代替案

- **footer のクリップ / 水平スクロール**: はみ出しの症状は消えるが設定コントロールが不可視・操作不能になる（対症療法）。
- **タイル・カラムの最小幅導入**: レイアウト設計の変更が波及し、多列グリッドの成立条件を変えてしまう。composer 側の適応で解決できる。
- **グリッド専用の縮小 footer 実装**: 二重実装は設定項目追加のたびに乖離する。共有部品＋レイアウト enum の切替に寄せた。

## 結果

- 受け入れテスト `AcceptanceGridComposerOverflowTests`（290/250/700pt で実描画幅≤提案幅+1pt、ImageRenderer オラクル）と `ComposerOverflowLayoutTests` が回帰を固定。
- ImageRenderer はコンテナ（overlay 親）を測ると overflow が現れないため、**footer/bar 本体を直接描画して測る**（GridComposerBar を internal にした理由）。
- しきい値（600/490）は実測固有幅＋余裕。Menu/NSViewRepresentable はプレースホルダ描画で数 pt ずれうるため、最終確認は実機目視で行う。
