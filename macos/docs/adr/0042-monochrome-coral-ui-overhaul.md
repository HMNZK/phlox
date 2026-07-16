---
status: active
last-verified: 2026-07-07
---

# ADR 0042: UI カラースキーマをモノクロ基調＋Claude コーラル単一アクセントへ刷新し、ライトテーマとシームレスなセッション chrome を導入する

> **このファイルの役割**: なぜ紫基調ダーク専用から「モノクロ＋コーラル＋ライト対応」へ全面転換したか、UI chrome を再設計したかの決定・文脈・結果。
> **書かないもの**: 現行トークン値・テーマ一覧・コンポーネント仕様（→ `architecture/design-system.md`）。
> **更新**: point5 の「running のみ控えめインジケータ」は ADR 0044 で撤回（実行中インジケータ全廃）。point7 の入力欄チップ文字の控えめ化は本 run（delivery 0023 / task-3 item9）で実挙動として是正した。

## 文脈

従来のデザインシステムは既定テーマ `phlox` の紫アクセント（`#A855F7`）を中心に、6テーマ全てがダーク系だった。`.preferredColorScheme(.dark)` を複数箇所で強制し、hairline/fill トークン（border/separator/fillSubtle/fillSelected）は `Color.white.opacity(...)` の固定値でダーク前提だった。セッション表示は状態色の丸（StatusDot）＋エージェント名バッジ＋各種ステータス文字で情報過多、New Session ボタンやセッション名領域とメインコンテンツの間に境界線があった。

ユーザーは「モノクロ基調＋アイコン色アクセント」「ライト系を含むテーマ充実」「シームレスでミニマルな chrome」を要望した。ブランド SVG の実色を調査した結果、唯一の鮮やかな色は **Claude のコーラル `#D97757`**（`hsl(14.8,63.1%,59.6%)`）だった（Cursor はほぼ白、Codex はモノクロ）。

## 決定

1. **モノクロ基調＋単一アクセント**: 全テーマの background/surface/text をグレー階調へ再定義し、UI アクセントを全テーマ共通で **Claude コーラル `#D97757`** に統一する。
2. **ライトテーマ追加**: 著名テーマから Catppuccin Latte / Solarized Light / GitHub Light を `AppTheme.fromPalette` で導出し `ThemeStore.all` に登録する。
3. **明度追随**: `AppTheme.preferredColorScheme`（background の相対輝度 ≥0.5 で `.light`）を単一経路として導出し、ルート（PhloxApp）・設定画面・Usage ビューがこれに追随する（`.preferredColorScheme(.dark)` 固定を撤廃）。
4. **hairline/fill をテーマ追随に**: border/separator/fillSubtle/fillSelected/sessionRowHover を `theme.textPrimary` 由来の opacity へ変更（前景色基準＝常に背景と対比、ライトテーマで不可視化しない）。
5. **セッション chrome のミニマル化**: StatusDot＋エージェント名バッジを `AgentSessionIcon`（丸で囲わないブランド SVG＋running のみ控えめインジケータ）へ置換。New Session ボタン撤去（追加はホットキー＋プロジェクト行の＋ボタン）。設定ギアをサイドバーのアイコン群右へ、選択セッション名を同じ行に集約。ヘッダー境界を透明化しメイン背景と同色でシームレス化。ステータス文字を撤去。選択セッション背景を薄グレー（枠強調なし）。「ワークスペース」を「プロジェクト/Projects」に改名。
6. **チャット本文のミニマル化**: ツール/Reasoning/ファイル変更を囲う枠（DisclosureCard の背景・枠）を撤去、ユーザーバブルをニュートラルなグレー面に、エージェントアバターを丸なし・名前なしに、コピーボタンを出力左下＋押下フィードバック付きに。diff 色を追加=青（`diffAdded`）・削除=赤（`diffRemoved`）に。
7. **入力欄**: モード/モデル選択チップの chevron を撤去し文字色を薄く。

## 棄却案

- **紫アクセント維持でモノクロ化のみ**: ユーザーの「アイコン色アクセント」要望に反する。
- **hairline を黒 opacity へ反転**: ダークテーマで不可視化する。前景色由来にすることで両明度に対応。
- **awaitingApproval もサイドバー/グリッドに表示**: ユーザーがゲート判断で「running のみ最小表示を残す」を選択したため不採用（承認待ちはチャットの ApprovalBanner が担う）。

## 結果

- 全テーマがモノクロ基調＋コーラルで描画。ライトテーマ選択で chrome もライトに追随。DesignSystem 回帰テスト＋新規（AppThemePaletteTests / DSColorThemeTokenTests）で色トークン・明度追随・grayscale・ライト登録・AgentSessionIcon の running 判定を検証。
- **dead になった `AppTheme.rowSelected/rowSelectedBorder` を除去**（DSColor.sessionRowSelected は fillSelected、Border は clear へ切替わったため）。
- `newSessionGradient`（紫→ピンク）は SettingsView / UsageSidebarView で現役使用のため**残置**（New Session ボタン専用ではなかった）。脱コーラル基調では浮くため将来の再検討候補。
- テーマ切替は従来どおり**再起動反映**（既存制約は維持）。
- 視覚の最終確認は Debug 版起動での目視に委ねる（swift test は `Icons.xcassets` を actool 非コンパイル＝ブランド SVG のピクセル検証不可。ADR 0032）。
</content>
