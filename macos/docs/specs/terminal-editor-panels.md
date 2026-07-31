---
status: active
last-verified: 2026-08-01
---

# terminal-editor-panels（要件仕様）

**役割（ここにしか書かない）**: ターミナルパネル・エディタパネルが満たすべき要件（FR/NFR）・
受け入れ基準・仮定・スコープ外。

**書かないもの**: 設計・実装の詳細（→ [architecture/terminal-editor-panels.md](../architecture/terminal-editor-panels.md)）、
なぜその方式にしたか（→ adr/0148〜0151）。

**Diátaxis**: Reference

## 背景

Phlox はエージェントセッションを並べて監視・操作するアプリだが、①ユーザー自身がコマンドを打つ場所
（外部ターミナルへの切替が必要だった）、②エージェントが編集したファイルを確認・修正する場所
（チャット内 diff カードは「報告された変更」であり、ワーキングツリーの現状ではない）が無かった。
この2つをホットキーで即座に開けるパネルとして追加する。

## 機能要件（FR）

| ID | 要件 |
|---|---|
| FR-1 | ⌘⌥T でターミナルパネルをトグル表示・非表示できる |
| FR-2 | ⌘⌥E でエディタパネルをトグル表示・非表示できる |
| FR-3 | 両パネルはメインウィンドウ内の trailing ドロワーに、レイアウトフロー内（overlay ではない）で開閉する |
| FR-4 | ドロワーは分割線をドラッグして幅調整できる（最小幅あり、幅は永続化） |
| FR-5 | ターミナルパネルはホームディレクトリを cwd とするシェルを起動し、入力・出力ができる |
| FR-6 | ターミナルパネルを閉じてもシェルはバックグラウンドで存続し、再度開くと scrollback ごと復帰する |
| FR-7 | アプリ終了時にユーザーターミナルのシェルを終了させる（パネルを閉じただけでは終了しない） |
| FR-8 | エディタパネルは、選択中セッションのプロジェクトの「HEAD からの変更」一覧（staged/未ステージ/未追跡を区別しない）を表示する |
| FR-9 | 変更一覧からファイルを選ぶと、追跡ファイルは unified diff、未追跡テキストファイルは全文、バイナリは編集不可のプレースホルダを表示する |
| FR-10 | 選択したファイルはその場で編集でき、保存するとディスクへ書き込まれる |
| FR-11 | 保存時、選択（ロード）時点からディスクの内容が外部で変わっていた場合は書き込まず警告し、ユーザーが選べば上書きできる |
| FR-12 | 変更一覧・diff の更新は「Refresh」の明示操作でのみ行う（自動リロードはしない） |
| FR-13 | エディタパネルはセッション切替に追従し、選択中セッションのプロジェクトが対象になる。未選択時・非 git プロジェクトでは空状態を表示する |
| FR-14 | トップバー（Usage 表示等）はパネルの開閉・幅変更の影響を受けず、ウィンドウ幅基準の位置・大きさを保つ |

## 非機能要件（NFR）

| ID | 要件 |
|---|---|
| NFR-1 | パネルの開閉・幅ドラッグはグリッドの全タイル再レイアウトを毎フレーム誘発しない（ADR 0116/0136 のゴースト方式を踏襲） |
| NFR-2 | エディタパネルの変更一覧は git の出力（`status`/`diff`）だけから構築し、大きなリポジトリでも全ファイル内容を読まない |
| NFR-3 | git 読み取り操作は git の意味論的状態（追跡内容・ステージ状態・HEAD・porcelain 出力・write-tree 結果）を変更しない（ADR 0150） |
| NFR-4 | PTY spawn は無関係な fd（他プロセスが開いているパイプ等）を子プロセスへ継承しない（ADR 0151） |
| NFR-5 | 大きな diff・大きなファイルの表示で応答性を落とさない（プレビューの行数上限・編集可能ファイルサイズ上限） |

## 受け入れ基準（凍結受け入れテスト）

以下は task-0 で凍結され、後続タスクで実装・全数 green を維持する受け入れテスト
（`macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/`）。

| ファイル | 対象 |
|---|---|
| `AcceptancePanelRouterTests.swift` | `AppRouter` のパネル表示フラグ・トグル |
| `AcceptanceUserTerminalTests.swift` | `UserTerminalController` の起動・入出力・自然終了・再起動・shutdown |
| `AcceptanceWorkingTreeTests.swift` | `WorkingTreeService` の変更一覧・diff・保存・競合検出 |
| `AcceptanceTerminalPanelWiringTests.swift` | ターミナルパネルのホットキー配線・ドロワー配置（オーバーレイでないこと） |
| `AcceptanceEditorPanelVMTests.swift` | `EditorPanelViewModel` の一覧・選択・編集・保存・競合フロー |
| `AcceptancePanelIntegrationTests.swift` | 確定容器への統合・プロトタイプ撤去・⌘⌥E 配線・shutdown 配線 |

XCUITest（`macos/PhloxUITests/PanelUITests.swift`）: ⌘⌥T でターミナルパネルが
`user-terminal-panel` の accessibilityIdentifier で出現・再押下で消えること、⌘⌥E で
エディタパネルが `editor-panel` の accessibilityIdentifier で出現することを検査する。

検証コマンドの全体は `.claude/verify.sh`（`DashboardFeature`・`SessionFeature`・`PTYKit` の
`swift test` 全数と、凍結受け入れテスト6ファイルのフェーズ1凍結コミットからの無改変チェック）。

## 仮定・エッジケース

- 選択中セッションにプロジェクトが割り当てられていない、またはプロジェクトが git リポジトリでない
  場合、エディタパネルは操作不能ではなく明示的な空状態（`noProject` / `notARepository`）を表示する。
- バイナリファイルは編集対象外（プレースホルダ表示）。
- 巨大ファイルは編集領域への読み込みに上限を設ける（`EditorPanelViewModel.maximumEditableFileSize`
  = 1,000,000 バイト。超過時は「too large to edit」表示で閲覧専用）。diff/内容プレビューは
  500 行単位で段階表示する（`EditorPanelView.previewLineLimit`）。
- 非 UTF-8・削除済みファイルの選択は、読み込み失敗として安全側（選択解除または読み込み専用表示）へ
  倒す。

## スコープ外

- iOS アプリへの同機能追加（ターミナルが読み取り専用の装飾テキストとして実装されており土台が無い。
  ADR 0039 参照）。
- git の stage/commit/push/PR 作成 UI。
- タブ・ペイン分割つきの本格ターミナルマルチプレクサ（1 パネル 1 シェル）。
- アプリ非アクティブ時も効くグローバルホットキー。
- 汎用ファイルブラウザ・任意ファイルのオープン（対象は「変更ファイルのレビュー・修正」に限る）。
- ファイル監視による自動リロード（一覧・diff の更新は手動 Refresh のみ）。
