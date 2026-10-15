---
status: active
last-verified: 2026-10-15
---

# Dashboard 3ペインレイアウトと幅クランプ

> **このファイルの役割**: メインウィンドウの3ペイン（左サイドバー・detail・右インスペクター）構成と、ペイン幅の決定・クランプ機構の現行仕様。
> **書かないもの**: 決定の理由（→ adr/0195）、ファイルと差分のデータフロー（→ file-explorer-and-markdown-editing.md・terminal-editor-panels.md）。

## 構成（Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/）

- `DashboardView.navigationShell` — `GeometryReader` + `HStack(spacing: 0)` の自前3ペイン。左=`DashboardSidebarView`、中央=子タブ、右=`InspectorView`（ファイル / Git。ADR 0195）。表示状態は `AppRouter.sidebarVisible` / `inspectorVisible`。右は260〜340pt（既定280pt）。中央に480ptを残せない場合は右をカードとして重ね、Gitから変更タブへ渡すとカードを閉じる。
- `PaneWidthPolicy.resolve` は `DSLayout.sidebarWidth` / `inspectorWidth` で幅をクランプする純関数。中央の最小幅は480pt。横に並ばない右ペインは重ね表示にし、左も横に並ばなければ自動で隠す。隠れた左は一時表示できる。
- `DashboardView` はウィンドウ幅・表示状態から毎回 `resolve` して配置する。幅は `SceneStorage` でウィンドウごとに保持する。`ResizeGripView` のドラッグは `draggedSidebarWidth` / `draggedInspectorWidth` を通し、中央の最小幅と範囲を守る。
- Git内の上下の境目は見た目1pt・操作領域8pt。一覧は最小84pt（3行）、差分は最小120pt。リサイズ時に比率を保ち、VoiceOverの増減操作でも調整できる。一覧の高さは UserDefaults に保存し、タブ再表示・アプリ再起動で復元する。通常のキーボード調整は追加しない（2026-10-14 ユーザー決定）。
- Git の行はフォルダを先に縮め、ファイル名・種類・行数を優先する。差分本文は文字単位で折り返す。バイナリは名前・種類・サイズ、未追跡は追加のハンク見出しを出す。共有差分色は変えず Git 側だけ塗りを薄くする。寸法は既存 DesignSystem トークンの近似値を使う。

## 中央の下部パネル（ADR 0196・0197）

境界は上下向きの `ResizeGripView`（ADR 0202）。左右境界と同じ区切り線色の3ptの帯がホバー・ドラッグ中に0.12秒で現れ、上下カーソルをドラッグ中も維持する。マウス操作中はウィンドウ移動を抑止し、終了・取り外し・アプリ非アクティブ化で復元する。ダブルクリックで既定高に戻す。端末のフォーカス外枠は描かず、見出しの文字の強調で入力先を示す。

`SessionTabsContainer` がタブ列より下の中央本文を `BottomPanelContainer` で包み、その下だけに `BottomPanelView` を配置する。左右のペインと `.safeAreaInset` の使用量バーはこの容器の外側。開閉・フォーカスは ウィンドウごとの `DashboardView` の `BottomPanelState` に分離し、親の `DashboardView` は開閉・ドラッグの値を読まない。ドラッグ中は境界の予告線だけを更新して内容の高さを固定し、終了時だけ保存・レイアウト更新する。

`BottomPanelLayout` はタブ列より下の本文高（使用量バーは親の safeAreaInset）から最大 `min(本文高×0.7, 本文高−200)` を計算する。通常は120pt以上、320pt未満の中央では上の内容の確保を優先する。保存した希望高はウィンドウを縮めても書き換えず、広げると復元する。高さ変更は VoiceOver の増減操作と、境界へのフォーカス中の上下キーでも行える。

プロジェクトは単体では選択中のプロジェクト、グリッドでは選択中のタイルのプロジェクト。選択タイルの装飾を変更しない。表示メニューは `FocusedValues` で操作中のウィンドウへ接続する。操作はヘッダー右端、表示メニュー、⌘J（ADR 0200）。ヘッダーの開閉ボタンは閉じているときに透明な面・補助文字色、開いているときにインスペクタと同じ選択の塗り・主文字色を使う（ADR 0198）。アクセシビリティ表現は Toggle とし、実際の開閉を AXValue のオン／オフで公開する（[ADR 0199](../adr/0199-file-rename-menu-and-accessibility-state.md)）。表示モード・下部パネル・インスペクタは別々の ToolbarItem として公開し、読み上げ名を互いに継承させない。開いたことがないプロジェクトの再起動メニューは無効、起動済みなら閉じていても再起動して開く。

シェル終了の案内と再起動ボタンは、ライトでも暗いターミナルの面の内側に置く。専用の DesignSystem トークンで補助文字・ボタンの面・文字・縁を揃える。

`ToolbarInteractionTests` は標準タイトルバーの AX 操作要素を日英・明暗で検査する。下部パネル、インスペクタの順で開閉し、各押下後に両者の状態と AXCheckBox の AXValue を確認する。VoiceOver の音声出力は未検証。

下部パネルのテストは `BottomPanelTests` と `BottomPanelResizeTests` に置く。`ResizeGripTests` は上下・左右の移動量、カーソル、ダブルクリック、窓の固定・復元と矢印キーを検査する。下部の上下キーは共通部品の AppKit レスポンダで受け取り、VoiceOver の増減は下部境界のアクセシビリティ操作に残す。

`DesignSnapshotRenderTests.bottomPanelSnapshots` は `PHLOX_DESIGN_SNAPSHOTS=1` で画面外描画する。`PHLOX_DESIGN_SNAPSHOT_SCOPE=focus-borders` は下部パネルを開き、端末／ファイルツリーに実際の入力先を移した状態だけを日英・明暗で出力する。

## テスト

- `PaneLayoutPolicyTests` は右の重ね表示・左の自動非表示・ドラッグ幅の境界を検査する。
- `DesignSnapshotRenderTests.gitInspectorSnapshots` は260/280/340pt、日英・明暗、一覧＋差分／変更なし／管理外／取得失敗と再試行／長い差分／バイナリ／未追跡を画面外描画する。明示指定 `PHLOX_DESIGN_SNAPSHOTS=1` の場合だけ画像を出す。

## 前提・境界

- 使用量バーは下端のまま。Gitタブ追加で左右の幅の規則を変更しない。
