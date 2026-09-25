# C分類 決定記録

方針: 見本（`/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-redesign/design_handoff_phlox_ui/designs/*.dc.html` と README.md）を実際に開き、図・注記・文言のうち見本が示す形に最も近い案を選んだ。`c-choices.md` の「推奨」欄は判断に使わず、見本の記述だけを根拠にした。「今のまま」としたのは、見本を関連キーワードで検索して該当する図・注記が見つからなかった項目のみ。機能を消す案は見本がその機能を明確に持たない形で描いている場合に限り採用した。

---

## 01 Main Window / 02 Tabs

### C-1 対応待ち0件のときのボタン表示
- 決定: ①押せなくする（今のまま）
- 根拠: `01 Main Window.dc.html` / `PhloxWindow.dc.html` / `03 Sidebar.dc.html` を「対応待ち」「0件」「disabled」「無効」で検索したが該当なし。見本の全シナリオで対応待ちは3〜4件固定で、0件時の表示は描かれていない。
- 実装: 不要

### C-2 エージェント管理を別ウィンドウで開いていること
- 決定: ①別ウィンドウのまま
- 根拠: `13 Review.dc.html:43,128`「13章 エージェント管理ウィンドウはどの回でも画面を作っていない。入口と、スキル削除の確認ダイアログだけがある」。README.md:71「13章 エージェント管理ウィンドウは未設計。当面は現行UIを維持」。
- 実装: 不要

### C-3 ターミナル型セッションの子タブ名
- 決定: ②「ターミナル」と明示する（会話も同様に短い名称「会話」を使う）
- 根拠: `PhloxWindow.dc.html:222-224` の実タブ表示は `<span>会話</span>` `<span>ターミナル</span>` `<span>変更 3</span>` という短い名称のみ。`PhloxTabs.dc.html:205` の `subBar` 生成コードも同様。長い名称「会話（このセッション）」等はタブ追加メニューの説明文にのみ使われ、開いたタブ自体には出ない。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/` 配下の子タブラベル生成箇所（`会話（このセッション）` 等のリテラルをGrepして特定）

### C-4 プロジェクト未選択時のタブ列
- 決定: ①共通ターミナルだけ出す（今のまま）
- 根拠: `01/02/03` と部品ファイルを「未選択」「共通ターミナル」で検索。ヒットした `03 Sidebar.dc.html:95` は新規セッションダイアログの話で、プロジェクト未選択時のタブ列そのものを描いた箇所はない。
- 実装: 不要

### C-5 使用量チップの低残量マーク「▲」
- 決定: ①文字段にも低残量マークを付ける
- 根拠: `01 Main Window.dc.html:180`「残り20%未満は3段階とも琥珀＋▲。承認待ちと同じ色だが、形（ゲージ・▲）で区別する」。文字表示段階（同:178）を含む3段階すべてに▲を付ける前提。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/UsageTopBarView.swift`

### C-6 ターミナルを閉じる際の実行中プロセス確認
- 決定: ②プロセスがあるときだけ確認する
- 根拠: `02 Tabs.dc.html:76`「ターミナルのタブを閉じるとシェルを終了する（実行中のプロセスがあれば確認）。」
- 実装: 要（中）| `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalCoordinator.swift`, `macos/Packages/DashboardFeature/Sources/DashboardFeature/UserTerminal/UserTerminalController.swift`

## 03 サイドバー

### C-7 サイドバーの並べ替え
- 決定: ③ドラッグとキー操作の両方に対応する
- 根拠: `03 Sidebar.dc.html:115-117`（F10候補）「reorderSession を使う想定。同じ親の中だけで並べ替え…キーボードでは ⌥⇧⌘↑↓ で1つずつ動かす（案）」。ドラッグ描画とキー操作の両方が明記されている。
- 実装: 要（中）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift`（`reorderSession`）, `SessionTreeSidebarSection.swift`

### C-8 オーケストレーションの子セッションをサイドバーに出すか
- 決定: ②親の下に畳んで表示する
- 根拠: `03 Sidebar.dc.html:170-173`（G3「案B: 親の下に『内部セッション n』として畳んで出す」）。`PhloxSidebar.dc.html:112-119` の `isInternal` 行が `scenario="deep"` のデータで実際に描画されている。
- 実装: 要（中）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionTreeSidebarSection.swift`, `macos/Packages/SessionFeature/Sources/SessionFeature/SessionTreeViewModel.swift`

### C-9 選択操作によるフォーカス移動
- 決定: ①今のまま
- 根拠: 「フォーカスを自動」「0.5秒」等で検索。唯一のヒットは `01 Main Window.dc.html:190`（対応待ち一覧の1行目フォーカス）で、C-9が問うクリック/キー選択時のサイドバーフォーカス挙動は描かれていない。
- 実装: 不要

### C-10 プロジェクト名を空欄で確定した場合の戻り先
- 決定: ②空欄ならフォルダ名に戻す
- 根拠: `03 Sidebar.dc.html:100`（F6）「空欄で確定すると自動の名前（花名＋短縮ID）に戻る。プロジェクト名も同じ方式で、変わるのは表示名だけでフォルダ名は変わらない。」＝自動表示名の元がフォルダ名であるため。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift`（プロジェクト名編集確定処理）

### C-11 名前変更欄で選択した文字の色
- 決定: ②AppKit製の入力欄に置き換える
- 根拠: `PhloxSidebar.dc.html:126` 名前変更行で選択文字部分に `--selText`（`:205-206` accent橙のハイライト）を明示的に適用しており、標準の選択色ではない。SwiftUI標準TextFieldでは選択背景色を制御できないためAppKit経由が必要。
- 実装: 要（中）| `macos/Packages/DesignSystem/Sources/DesignSystem/` にNSViewRepresentable化したテキストフィールドを新設、`SessionTreeSidebarSection.swift` のインライン編集箇所を置換

### C-12 「既存のworktreeを使う」というメニュー項目
- 決定: ②既存worktreeを選んで関連付ける項目を足す（見本は複数候補選択ではなく単一候補への単純ボタン）
- 根拠: `09 Dialogs.dc.html:159`（E4）`buttons:[['隔離なしで起動','normal'],['既存の worktree を使う','normal'],...]`、`PhloxStart.dc.html:180` `ok:'既存の worktree を使う'`。worktree作成失敗時の回復ボタンとして実在。
- 実装: 要（小〜中）| `macos/Packages/AgentDomain/Sources/AgentDomain/WorktreeIsolationPlanner.swift`, `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift`

## 04 セッションのチャット画面

### C-13 セッション名を空欄で確定したときの表示
- 決定: ②花の名前に戻す（自動の名前に戻る、の初期形）
- 根拠: `04 Session Chat.dc.html:66`「タイトルをダブルクリックすると名前を編集でき、空欄で確定すると自動の名前に戻る。」
- 実装: 要（小）| `macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleState.swift`, `SessionTitlePresentation.swift`

### C-14 ツールバーのタイトル表示
- 決定: ①01の仕様を優先する（今のまま）
- 根拠: `04 Session Chat.dc.html:206`「ツールバーのタイトルはこれと同じ内容を1行に縮めたもの。」＝01の内容をそのまま縮約する設計。
- 実装: 不要

### C-15 Codexのプラン・子スレッドの表示位置
- 決定: ①会話の中のカードに統合する
- 根拠: `PhloxChat.dc.html:213-228`（`it.isCodex` の描画）、`:402`「if (sc === 'codex') items = [..., {isCodex:true}, ...]」＝items配列（会話の中）に挿入されている。
- 実装: 要（中）| `macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift`, `ChatSessionViewModel.swift`

### C-16 カードの既定の開閉状態
- 決定: ③カードの種類ごとに決める
- 根拠: `04 Session Chat.dc.html:24-33` の表で種類ごとに既定を個別定義（推論=閉じる[案]、コマンドグループ=実行中のみ開く[現行]、コマンド単体=失敗のみ開く[案]、ファイル変更=常に閉じる[現行]、タスクリスト=最新のみ開く[案]、エラー・質問・承認=常に全展開[現行]）。
- 実装: 要（中）| `macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptItemPresentation.swift`

### C-17 プロセス終了（completed(exitCode)）の見せ方
- 決定: ①終了コードと「この会話から再開」を表示する
- 根拠: `04 Session Chat.dc.html:86`「入力欄の代わりに終了コードと『この会話から再開』を出した」、`PhloxChat.dc.html:255-256`「セッションは終了しました（exit 0）。会話は保存されています。」＋「この会話から再開」ボタン。成功時限定の条件は描かれていない。
- 実装: 要（小〜中）| `macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift`, `ChatSessionViewModel.swift`

### C-18 Codexの画像添付（モデルによって解消しない）
- 決定: ①対応モデルだけ添付を許可する
- 根拠: `05 Reply Area.dc.html:102-104`（案B、根拠「Codexは選択モデル次第」）、`PhloxReply.dc.html:293`「gpt-5.5は画像入力に対応していないため、この画像は送られません。モデルを切り替えると送れます。」
- 実装: 要（中）| `macos/Packages/SessionFeature/Sources/SessionFeature/ComposerAttachments.swift`

### C-19 Markdown見出しの文字サイズ
- 決定: ①今のまま
- 根拠: `04 Session Chat.dc.html`・`PhloxChat.dc.html` を「見出し」「heading」で検索。ヒットは見本用の小見出しやコードブロックの「コピー」見出しのみで、Markdown見出し自体の文字サイズへの言及はない。
- 実装: 不要

### C-20 終了コードの表示方式
- 決定: ①Claude限定の表示のまま
- 根拠: 「Exit code」「exitCode」で検索。ヒットは `completed(exitCode)` というプロセス状態名の言及のみ（`04 Session Chat.dc.html:86,216`）で、エージェント別の取得方式（文字列解析 vs 構造化データ）の描き分けはない。
- 実装: 不要

### C-21 履歴カードの行数・最後の発言
- 決定: ②履歴の元データから行数と最後の発言を取得して表示する
- 根拠: `PhloxChat.dc.html:485` `historyCards` の例に `hc.last`（最後の発言）と「18 件」（行数相当）を実際に描画（テンプレートは`:50-54`）。
- 実装: 要（中）| `macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift`

### C-22 失敗コマンド・推論プレビューの自動展開
- 決定: ③失敗したコマンドだけ自動で開く
- 根拠: `PhloxChat.dc.html:408`（`sc === 'error'` 分岐で `cmd(true, {exit:1,...})`）、`04 Session Chat.dc.html:91`「失敗したコマンドは開いたままにし…」。推論・タスクリストは同分岐で開いていない。
- 実装: 要（小）| `macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+CommandGroup.swift`, `TranscriptItemPresentation.swift`

### C-23 ターミナル型Codexの質問を承認待ちとして扱う制約
- 決定: ①今のまま
- 根拠: `04 Session Chat.dc.html:197`「質問を検知したら状態は『承認待ち』になり、サイドバーの対応待ちに出る」＝識別できる情報の有無で区別する仕組みは描かれておらず一律「承認待ち」化。
- 実装: 不要

## 05 入力欄・返信エリア

### C-24 Claudeのツール許可カードの通知上の呼び方
- 決定: ①今のまま質問待ちで統一する
- 根拠: 「タブ」「通知」表記の変更に関する記述は見つからず。カード自体のラベル（`PhloxReply.dc.html:25`「承認待ち・{{ap.kind}}」）はカード内部の話で通知・タブ表記の変更を裏付けない。
- 実装: 不要

### C-25 「このセッション中は許可」の適用範囲
- 決定: ③範囲を調べてから共通の説明にする
- 根拠: `05 Reply Area.dc.html:170`（分岐候補）「範囲（同じコマンドか、同じ種類か）はエージェントごとのクライアント実装に依存し未確認」、`PhloxReply.dc.html:58` の説明文は全エージェント共通の仮置き1文。
- 実装: 要（小）| `macos/Packages/SessionFeature/Sources/SessionFeature/ChatApprovalBroker.swift`

### C-26 Claudeへの`setMode`送信
- 決定: ①今のまま送らない
- 根拠: `05 Reply Area.dc.html`・`PhloxReply.dc.html` を「setMode」「モード変更」で検索したが該当箇所なし。
- 実装: 不要

### C-27 権限変更の対象・追加先の表示
- 決定: ②プロトコル側が情報をくれるか確認してから表示を広げる（見本は先行して対象・追加先を表示する形で描いている）
- 根拠: `05 Reply Area.dc.html:25`「権限はルール文字列と追加先を出す（R6）」、`PhloxReply.dc.html:47-48`「追加する: Bash(git push:*)」「追加先: 許可リスト（このプロジェクトの.claude/settings.json）」を実際に表示。ただし静的モック値で、Codexが実際にこの情報を返すかは見本内で未確認。
- 実装: 要（中）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel+ControlApprovals.swift`

### C-28 入力履歴を↑キーで呼び出す機能
- 決定: ③フォーカスや候補表示の状態に応じて条件付きで呼び戻す
- 根拠: `PhloxReply.dc.html:300` の既定キー案内配列に「↑ 入力履歴（候補がないとき）」が実装されている＝候補がない条件下での↑キー呼び出し。
- 実装: 要（小）| `macos/Packages/SessionFeature/Sources/SessionFeature/InputHistoryPolicy.swift`, `ChatInputHistoryScrubber.swift`

### C-29 画像添付できないエージェント・モデルの扱い
- 決定: ①エージェントごとに調べて1つの方式に決める
- 根拠: `05 Reply Area.dc.html:107`「3つの層のどれが正しいかを確かめてから1つに決める」＝見本自身がエージェントごとの実態確認→一本化を明言。
- 実装: 要（中）| `macos/Packages/SessionFeature/Sources/SessionFeature/ComposerAttachments.swift`

### C-30 承認前・拒否後もファイル変更が「変更済み」と表示される
- 決定: ①今のまま
- 根拠: `PhloxChat.dc.html:374` `file()` カードは常に `label:'編集済み'` 固定表示。承認前後で表示を分ける記述・要素は見つからなかった。
- 実装: 不要

### C-31 承認待ち中でも入力欄から送信できる
- 決定: ③入力はできるが送信だけ止める
- 根拠: `05 Reply Area.dc.html:175`「本案では入力は可能で、送信は承認のあとにした」、`PhloxReply.dc.html:299`「承認待ちの間も入力できます（送信は承認後）」、`:242` `running = sc==='running' || isAp || isQ` で承認待ち中は送信ボタンが提供されない。
- 実装: 要（小）| `macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift`

### C-32 許可の返答が送信失敗しても回答済み表示になる
- 決定: 今のまま
- 根拠: 「回答済み」「再送」「送信失敗」を検索したが、承認・質問への回答送信が失敗した場合の扱いに関する記述は見本に見つからなかった。
- 実装: 不要

### C-33 送信失敗後の再送で発言が二重に残る
- 決定: 今のまま
- 根拠: 「二重」「重複」「1つにまとめ」で検索したが該当なし。`05 Reply Area.dc.html:58` は送信前の挙動のみで、再送後の履歴上の重複表示への言及はない。
- 実装: 不要

## 06 グリッド

### C-34 大タイルのチャット表示と入力欄上の宛先表示
- 決定: ②末尾と操作・入力欄だけの簡略表示にする
- 根拠: `06 Grid.dc.html:27`「大（480×330pt以上）は会話の末尾＋操作＋入力欄。中は最後の発言と操作だけ。」、`PhloxGrid.dc.html:88`（大タイル入力欄は簡略表示のみ）。
- 実装: 要（中）| `macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift`, `GridTileBorderPolicy.swift`

### C-35 タイルの矢印キーでの入れ替え
- 決定: ②案を採用する（⌥⌘⇧＋矢印で隣と入れ替え）
- 根拠: `06 Grid.dc.html:86`「案: ⌥⌘⇧＋矢印で隣と入れ替え、⌃⌥＋矢印で分割線を5%ずつ動かす（現行にキー操作はない）。」
- 実装: 要（小）| `macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayout/PaneTreeGeometry.swift`, `PaneLayoutView.swift`

### C-36 分割線の矢印キーでの移動
- 決定: ②5%ずつ動かす案を採用する
- 根拠: `06 Grid.dc.html:86`「⌃⌥＋矢印で分割線を5%ずつ動かす（現行にキー操作はない）。」
- 実装: 要（小）| `macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayout/PaneTreeGeometry.swift`, `PaneLayoutView.swift`

### C-37 グリッド内ターミナルの文字サイズ
- 決定: ②グリッド専用に11ptへ分ける
- 根拠: `PhloxGrid.dc.html:42`（PTYタイル本文）`font-size:11px`。単体表示側（`PhloxAux.dc.html` termStyle）は既定11.5px。
- 実装: 要（小）| `macos/Packages/TerminalUI` 内フォント設定、`PaneLayoutView.swift`

### C-38 「このセッション中は許可」表示の条件
- 決定: ②常時表示にする
- 根拠: `PhloxGrid.dc.html:58`（表示条件は `{{ t.notSmall }}` のみでエージェント種別分岐なし）、`05 Reply Area.dc.html:32`「ボタンの文言は『許可 / このセッション中は許可 / 拒否 / キャンセル』に揃える」。
- 実装: 要（中）| `macos/Packages/SessionFeature/Sources/SessionFeature/ChatApprovalBroker.swift`, `macos/Packages/AgentDomain/Sources/AgentDomain/ApprovalDecision.swift`

### C-39 Cursor使用量が0%と表示される
- 決定: ①取得元の値と表示計算を調べて直す
- 根拠: `PhloxAux.dc.html:235`「const txt = us==='failed' ? '—' : `${v}%`;」＝失敗時は「—」表示が正しく、「0%」表示は取り違えのバグ。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Usage/CursorUsageProvider.swift`, `UsageDisplay.swift`

### C-40 分割線の読み上げ内容
- 決定: ①今のまま
- 根拠: 「VoiceOver」「読み上げ」「aria-label」「role="separator"」で検索したが、分割線（`PhloxGrid.dc.html:107-109`）に読み上げ内容の指定は見つからず、ドラッグ中の吹き出し文言のみ。
- 実装: 不要

## 07 インスペクタとツール

### C-41 使用量取得に失敗したときの表示
- 決定: ②保持期間を見本に合わせて変える
- 根拠: `PhloxAux.dc.html:51`「ネットワークに接続できません（14:32）。下の値は2時間前のものです。」＝見本は2時間前の値をそのまま出しており、5分失効を前提にしていない。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Usage/UsageMonitor.swift`, `ClaudeUsageStaleness.swift`

### C-42 端末見出しの「再起動」ボタン
- 決定: ①子タブの見出しに再起動ボタンを追加する
- 根拠: `07 Inspector and Tools.dc.html:78`「ヘッダに文字サイズ（A− / A+、⌘− / ⌘+）と再起動。」、`PhloxAux.dc.html:178` `<span role="button" aria-label="シェルを再起動" ...>再起動</span>`。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/UserTerminal/TerminalPanelView.swift`

### C-43 保存競合時に相手のセッション名を出すか
- 決定: ①相手の名前が分かる場合は表示する
- 根拠: `PhloxAux.dc.html:158`「開いてから別のセッション（アザミ・Codex）が書き換えました。上書きすると、その変更は失われます。」
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Editor/EditorPanelView.swift`

### C-44 Git操作中の状態文言
- 決定: ①操作別の文言を追加する
- 根拠: `PhloxAux.dc.html:261` `committing:{t:'コミットしています…',k:'busy'}`、`:292` `commitLabel: ed==='committing' ? 'コミット中…' : 'コミット（3）'`。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Editor/GitCommitPanel.swift`

### C-45 Git失敗時のメッセージの英語化
- 決定: ②状態文言を英語にも対応させる
- 根拠: `12 Design System.dc.html:223`「Localizableに未登録の直書き文言…この用語に合わせて登録する。英語で長くなっても崩れないよう…」、`PhloxAux.dc.html:257` の状態文言（例: `pushError`）は固定短文でローカライズ対象。提供元の理由文（ログ原文）の翻訳指示は見つからない。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Editor/GitCommitPanel.swift`

### C-46 使用量の「古さ」の基準・呼び名
- 決定: ①今の基準・呼び名のまま
- 根拠: `07 Inspector and Tools.dc.html:64,140`「何分で『古い』とするかはClaudeUsageStalenessの本体が未読のため未確定」＝見本側も基準を確定させておらず、既存の仕組みを変える描写がない。
- 実装: 不要

### C-47 使用量取得失敗時の「再検出・インストール」導線
- 決定: ①今のまま未インストール時だけ案内
- 根拠: `PhloxAux.dc.html:69-71`（インストール案内ボタンは `us==='unavailable'` 分岐にのみ存在。`stale`/`failed` のCursorカードには付かない）。
- 実装: 不要

## 08 開始・新規セッション

### C-48 「再検出」ボタンが探すPATHの範囲
- 決定: ①今のまま起動時のPATHに限定
- 根拠: 「再検出」「PATH」で検索。`PhloxStart.dc.html:97,99` に再検出ボタンはあるが、走査範囲についての記述は見本・READMEに見つからない。
- 実装: 不要

### C-49 未検出のカスタムエージェント向け「入手方法」リンク
- 決定: ①今のまま
- 根拠: `08 Start and New Session.dc.html:45`「カードは隠さず、淡くして理由と『入手方法』『再検出』を出す」は組込・カスタムを区別しておらず、カスタムのみへのリンク追加を示す図は見つからない。
- 実装: 不要

## 09 ダイアログ

### C-50 worktreeの作り直し確認
- 決定: ②復元時に必ず確認画面を出す
- 根拠: `09 Dialogs.dc.html:157`（E2）「worktree『tsubaki-a3f9』を作り直しますか?…作り直すと、このworktreeの未コミットの変更は失われます。」、`PhloxStart.dc.html:181` `wtRecreate:{title:'前回のworktreeが使えない状態です',...}`。既定ボタンはキャンセル側。
- 実装: 要（中）| `macos/Packages/AgentDomain/Sources/AgentDomain/WorktreeIsolationPlanner.swift`, `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift`

### C-51 削除確認と後始末警告の表示順
- 決定: ①今のまま順番に別画面で出す
- 根拠: `09 Dialogs.dc.html` のD2（後始末の失敗）とD3（セッション削除）は別々の独立ダイアログとして定義されており、1画面に統合した図は見つからない。
- 実装: 不要

### C-52 後始末警告に出すエラーの原文
- 決定: ①後始末処理で実際のエラー内容を保持して表示する（取得できない場合は場所のみ）
- 根拠: `09 Dialogs.dc.html`（D2）`log:'~/Library/Application Support/Phlox/workspaces/a3f9/hooks.json（Permission denied）'`＝場所だけでなく実際のエラー理由も等幅ログで表示している。
- 実装: 要（小）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift`（`workspaceCleanupWarning` 周辺）

## 10 設定

### C-53 エージェント権限の説明文
- 決定: ②見本の文言を出しつつCLIごとの違いを別途注記する
- 根拠: `PhloxSettings.dc.html:152` の共通注記は危険性の注記（「オンの間は、エージェントがファイルの変更やコマンドを確認なしで実行します。信頼できるプロジェクトでだけ使ってください。」）で今の「CLIごとに違う」注記とは内容が異なる。各行（:146-151）には今と同様に起動指定を表示。見本にCLI差異注記を消す描写はない（ルール上、削除は不可）。
- 実装: 要（小）| `macos/App/SettingsView.swift`

### C-54 接続端末の「接続中／未接続」表示
- 決定: ②接続状態を新たに取得して表示する
- 根拠: `PhloxSettings.dc.html:183-184` `R('kenta の iPhone','Revoke',{desc:'9月20日にペアリング・接続中'})` / `R('iPad','Revoke',{desc:'9月12日にペアリング・未接続'})`＝ペアリング日に加えて実際の接続状態を明示。
- 実装: 要（中）| `macos/App/MobileTokenViewModel.swift`, `macos/Packages/AgentDomain/Sources/AgentDomain/PairedDeviceStore.swift`

### C-55 匿名の利用状況・Dockバッジ数・プッシュ通知・トークン再発行の設定項目
- 決定: ②③相当（4項目とも「未確認/推測/分岐候補」タグ付きでUIに追加済みの形で描かれている。単純な「保留」ではない）
- 根拠: `PhloxSettings.dc.html:135`（匿名の利用状況トグル, tag:'未確認'）、`:144`（Dockバッジ数え方Popup, tag:'分岐候補'）、`:187`（プッシュ通知トグル, tag:'推測'）、`:188`（トークン再発行ボタン, tag:'推測'）。4項目全てが仕様未確定タグ付きのままUI要素として描かれている。
- 実装: 要（中〜大）| `macos/App/SettingsView.swift`

### C-56 テーマ・アイコンのタイルを矢印キーで選べるか
- 決定: ②ラジオボタンのグループにして矢印キーで移動できるようにする
- 根拠: `PhloxSettings.dc.html:71,80` テーマ・アイコンのタイルはいずれも `<div role="radio" aria-checked="...">` として明示的に描かれている（ボタンではない）。
- 実装: 要（小）| `macos/App/SettingsView.swift`, `macos/Packages/DesignSystem/Sources/DesignSystem/AppIconStore.swift`

### C-57 「S8の減光」の対象・条件
- 決定: ②対象画面と減光条件を決める（見本内に既に答えがある）
- 根拠: id="S8" は `PhloxSettings.dc.html` ではなく `06 Grid.dc.html:57-58`（「S8 ドラッグ中・右端にドロップして分割挿入」）に存在し、実体はグリッドのタイルドラッグ機能。`PhloxGrid.dc.html:91` `<sc-if value="{{ t.dragging }}">` でドラッグ元タイルに40%の減光オーバーレイ。`12 Design System.dc.html:261`「元は40%で残す。ドロップ先はaccentの淡い面＋2ptの縁」。対象=グリッドのドラッグ元タイル、条件=ドラッグ中、として既に確定している。設問前提（Settings内のS8）自体が誤り。
- 実装: 要（小）| グリッドのタイル/ドラッグ実装（`macos/Packages/DashboardFeature`/`SessionFeature` 内、要追加調査）

### C-58 カスタムエージェント名「(カスタム)」表記の言語対応
- 決定: 今のまま
- 根拠: 「英語」「locale」「表記ルール」を `10 Settings.dc.html` / `PhloxSettings.dc.html` 内で検索したが該当なし。唯一の該当箇所 `PhloxSettings.dc.html:151` `R('aider（カスタム）',...)` は日本語文言のみで言語切替の仕様は描かれていない。
- 実装: 不要

## 11 通知

### C-59 ターミナル型セッションの無応答通知
- 決定: ①今のまま（チャット型だけを対象にする）
- 根拠: `12 Design System.dc.html:246` `stalled:'...・通知・Dockに数える（チャット型のみ）'`。`11 Notifications and Startup.dc.html:149`「通知の発火条件（PTYは単純化、チャット型はhasActiveTurn必須）」＝ターミナル(PTY)は対象拡大が描かれていない。
- 実装: 不要

### C-60 終了コードが0以外のときの通知
- 決定: ②別の通知として終了コードを知らせる通知を追加する
- 根拠: `11 Notifications and Startup.dc.html:31`（表）終了種別「セッションが終了しました: {セッション名}」＋「終了コード（exit 1など）。0のときは通知しない」。実例 `:187` `{id:'N6',kind:'終了（exit ≠ 0）',...body:'exit 1',...}`。ただし`:159`で「分岐候補」とも併記。
- 実装: 要（小〜中）| `macos/Packages/SessionFeature/Sources/SessionFeature/SessionNotificationPolicy.swift`, `RemoteSessionNotifier.swift`

### C-61 Dockバッジの数え方を切り替える設定
- 決定: ②対応待ち／未読完了のどちらを数えるか選べるようにする
- 根拠: `PhloxSettings.dc.html:144` `R('バッジに出す数','Popup',{value:'対応待ちの数',tag:'分岐候補',desc:'現行は未読の完了の数。骨格の回の提案で対応待ちの数を既定にした'})`＝Popup（選択式）として両方を選べる形で描かれている。
- 実装: 要（小）| `macos/App/PhloxApp.swift`（`updateDockBadge`, `unseenCompletionCount`）, `macos/App/SettingsView.swift`

### C-62 スマホ側（APNs/Live Activity）に渡す通知情報の範囲
- 決定: ②パソコン側の通知の種類・文言をすべてスマホ側にも渡す
- 根拠: `11 Notifications and Startup.dc.html:146`（機能対応表）「APNs / Live Activity（リモート通知への委譲）」→「同じ文言をiOS側にも渡す。送信の設定はSettings L3」。承認・完了の2種類に限定する描写はない。
- 実装: 要（中）| `macos/Packages/AppBootstrap/Sources/AppBootstrap/APNsNotificationBridge.swift`, `macos/Packages/SessionFeature/Sources/SessionFeature/RemoteSessionNotifier.swift`

### C-63 起動中に表示する進捗の文言
- 決定: ①汎用的な起動中表示のまま
- 根拠: `11 Notifications and Startup.dc.html:201`（I1画面の段階文言）に対し、同ファイル`:158`（分岐候補）で「段階の文言は推測」と明記。見本自体が計測保証のない表示をそのまま採用しており、計測可能な段階だけに絞る変更は描かれていない。
- 実装: 不要

### C-64 壊れたJSONファイルを起動失敗として扱うか
- 決定: ②壊れたJSONも移行失敗として起動を止める
- 根拠: `11 Notifications and Startup.dc.html:203`（I3画面、`isError:true`）タイトル「Phloxを起動できませんでした」、ログ「AppSupportMigrator: ~/Library/Application Support/Phlox/sessions.json — The data couldn't be read because it isn't in the correct format.」、メモ「移行の失敗はデータを消さずに止めることを最初に伝える。」
- 実装: 要（中）| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Environment/AppSupportMigrator.swift`

### C-65 移行処理のロック取得に失敗した場合の起動エラー
- 決定: ①エラー画面を出して再試行を促す（今のまま）
- 根拠: 「ロック」「同時起動」で検索したが該当記述なし。同ファイルのI2画面（ポート競合の初期化エラー）は「起動できませんでした」＋ログ＋「再試行 ⌘R」という今と同型の構成。
- 実装: 不要

## 12 デザインシステム

### C-66 全画面の文字サイズを共通の仕組み（トークン）経由に揃える
- 決定: ②対象と例外を決めて段階的に統一する
- 根拠: `12 Design System.dc.html:60`「大きさはTranscriptTypographyの役割に対応させる。」、`:277-287` の文字テーブルで9種の役割別サイズを一覧化しており、画面ごとの直書きではなく役割(トークン)に対応させる方向を明示。
- 実装: 要（大）| `macos/Packages/DesignSystem/Sources/DesignSystem/TranscriptTypography.swift`（既存トークン）、各Feature内の直書きフォントサイズ（要棚卸し）

### C-67 小さい文字を一律11ptにするか
- 決定: ①画面ごとのサイズをそのまま維持する
- 根拠: `12 Design System.dc.html:284-285` の文字テーブルに「11.5/Semibold」（状態の文言）と「11/Regular」（時刻・メタ・キー）の2つの小さいサイズが役割別に併記されており、一律11ptへ統一する描写はない。
- 実装: 不要

### C-68 無応答の経過時間の表示形式
- 決定: ①今の形式のまま
- 根拠: `12 Design System.dc.html:247-250` のCapsuleBadgeロジックで無応答(stalled)ラベルは `${name} 2:14`（mm:ss形式）という専用形式で描かれており、既存の専用表示形式を踏襲した具体例のみ。別形式へ変更する内容はこの範囲から確認できない。
- 実装: 不要

---

## 実装が要る項目（規模順）

**大（1件）**
- C-66 全画面の文字サイズをトークン経由に揃える | `macos/Packages/DesignSystem/Sources/DesignSystem/TranscriptTypography.swift` ほか（棚卸し含む）

**中〜大（1件）**
- C-55 匿名の利用状況・Dockバッジ数・プッシュ通知・トークン再発行の設定項目追加 | `macos/App/SettingsView.swift`

**小〜中（3件）**
- C-12 「既存のworktreeを使う」メニュー項目 | `WorktreeIsolationPlanner.swift`, `SessionSpawnService.swift`
- C-17 プロセス終了時に終了コード＋再開ボタン表示 | `ChatSessionView.swift`, `ChatSessionViewModel.swift`
- C-60 終了コード非0時の通知追加 | `SessionNotificationPolicy.swift`, `RemoteSessionNotifier.swift`

**中（16件）**
- C-6 ターミナル閉時プロセス確認 | `TerminalCoordinator.swift`, `UserTerminalController.swift`
- C-7 サイドバー並べ替え（ドラッグ＋キー） | `DashboardViewModel.swift`, `SessionTreeSidebarSection.swift`
- C-8 子セッションをサイドバーに畳んで表示 | `SessionTreeSidebarSection.swift`, `SessionTreeViewModel.swift`
- C-11 名前変更欄をAppKit製に置換 | `DesignSystem/`（新規NSViewRepresentable）, `SessionTreeSidebarSection.swift`
- C-15 Codexプラン・子スレッドを会話内カードに統合 | `ChatMessageCells+Structured.swift`, `ChatSessionViewModel.swift`
- C-16 カード既定開閉を種類ごとに設定 | `TranscriptItemPresentation.swift`
- C-18 Codex画像添付を対応モデルのみ許可 | `ComposerAttachments.swift`
- C-21 履歴カードに行数・最後の発言を表示 | `ChatSessionView.swift`
- C-27 権限変更の対象・追加先表示を拡張 | `DashboardViewModel+ControlApprovals.swift`
- C-29 画像添付不可の扱いをエージェントごとに一本化 | `ComposerAttachments.swift`
- C-34 大タイルを簡略表示に変更 | `PaneLayoutView.swift`, `GridTileBorderPolicy.swift`
- C-38 「このセッション中は許可」を常時表示 | `ChatApprovalBroker.swift`, `ApprovalDecision.swift`
- C-50 worktree作り直し時に確認画面を追加 | `WorktreeIsolationPlanner.swift`, `SessionSpawnService.swift`
- C-54 接続端末の実接続状態を取得・表示 | `MobileTokenViewModel.swift`, `PairedDeviceStore.swift`
- C-62 スマホ側への通知情報を全種類同期 | `APNsNotificationBridge.swift`, `RemoteSessionNotifier.swift`
- C-64 壊れたJSONを移行失敗として起動停止 | `AppSupportMigrator.swift`

**小（22件）**
- C-3 子タブ名を短縮名に統一 | DashboardFeature子タブラベル生成箇所
- C-5 使用量チップの文字段にも▲表示 | `UsageTopBarView.swift`
- C-10 プロジェクト名空欄確定でフォルダ名に戻す | `DashboardViewModel.swift`
- C-13 セッション名空欄確定で花の名前に戻す | `SessionTitleState.swift`, `SessionTitlePresentation.swift`
- C-22 失敗コマンドのみ自動展開 | `ChatMessageCells+CommandGroup.swift`, `TranscriptItemPresentation.swift`
- C-25 「このセッション中は許可」説明文を範囲確定後に共通化 | `ChatApprovalBroker.swift`
- C-28 ↑キー入力履歴を条件付きで有効化 | `InputHistoryPolicy.swift`, `ChatInputHistoryScrubber.swift`
- C-31 承認待ち中は送信のみ停止 | `ChatComposer.swift`
- C-35 タイルの矢印キー入れ替え | `PaneTreeGeometry.swift`, `PaneLayoutView.swift`
- C-36 分割線を5%ずつキー移動 | `PaneTreeGeometry.swift`, `PaneLayoutView.swift`
- C-37 グリッド内ターミナルを11ptに分離 | TerminalUIフォント設定, `PaneLayoutView.swift`
- C-39 Cursor使用量0%表示のバグ修正 | `CursorUsageProvider.swift`, `UsageDisplay.swift`
- C-41 使用量失敗時の保持期間を見本に合わせる | `UsageMonitor.swift`, `ClaudeUsageStaleness.swift`
- C-42 端末見出しに再起動ボタン追加 | `TerminalPanelView.swift`
- C-43 保存競合で相手セッション名を表示 | `EditorPanelView.swift`
- C-44 Git操作別の状態文言を追加 | `GitCommitPanel.swift`
- C-45 Git状態文言を英語対応 | `GitCommitPanel.swift`
- C-52 後始末警告に実エラー内容を表示 | `DashboardViewModel.swift`
- C-53 エージェント権限説明文を見本＋CLI差異注記の併記に | `SettingsView.swift`
- C-56 テーマ・アイコンタイルをラジオボタン化 | `SettingsView.swift`, `AppIconStore.swift`
- C-57 S8減光をグリッドのドラッグ元タイルとして実装確認 | グリッド/ドラッグ実装（要追加調査）
- C-61 Dockバッジ数え方の切替設定を追加 | `PhloxApp.swift`, `SettingsView.swift`
