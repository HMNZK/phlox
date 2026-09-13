**差し戻しが必要です。** 同一入力に相反する期待値があり、配線検査と目視ハーネスにも契約を守れない箇所があります。退避中の Swift 2 ファイルと Ruby は `dde44dc` の凍結内容とバイト一致を確認しました。

検査軸は、表示種類、本文・要約、コマンド経路・件数・出力・実行状態、開閉と更新、描画上限、操作、幅・倍率・テーマです。以下の行番号は実ファイルで確認済みです。Swift／Ruby／GUI の実行再現は **unverified**（read-only 制約。一時ファイル作成も拒否されたため）。作成担当の報告は未読、変更なしです。

## MUST

**1. 同じ開閉関数に `true` と `false` の両方を要求している**

- **該当行：** [受け入れテスト:69](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptItemPresentationTests.swift:69)、同72–77・170。
- **理由：** 回答の `defaultExpanded == true` を要求した直後、`isExpanded(userOverride: false, defaultExpanded: true)` に `true` を要求。一方170行は同一入力に `false` を要求しています。契約の `userOverride ?? defaultExpanded` とも前者が矛盾します。「回答を詳細用 override で隠さない」は View の配線条件です。
- **修正案：** 共通関数は override 優先へ統一し、回答の常時表示は実回答 View が詳細用 Binding に依存しないこととして検査する。

## HIGH

**2. task-47 の指定描画経路を恒久検査が拒否する**

- **該当行：** [Ruby:528](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task46-wiring.rb:528)、同1026–1033、[task-47:340](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-47.md:340)。
- **理由：** 検査は `Text(text)` または `RichMarkdownView(...)` を要求しますが、task-47 は secondary 色を指定した `AgentMessageBody` を要求します。到達先探索は Structured ファイル内だけなので、別ファイルの描画経路を追えません。正常 fixture も契約と異なる直接 `RichMarkdownView` 呼び出しです。
- **修正案：** 指定された `AgentMessageBody(text:…, bodyColor:…)` 経路を正常 fixture にし、別ファイルへの原文・本文色転送まで検査する。

**3. モデルの存在を調べるだけで、必要な配線を検査していない**

- **該当行：** [Ruby:520](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task46-wiring.rb:520)–618。
- **理由：** 思考の見出し・補足、タスクの操作可能な Binding、モデルの意味色、件数の実入力などを確認していません。例えば思考の `title` を固定文字列、タスクを `.constant(false)` にしても該当判定では検出されません。グループは `header.shouldRender` を検査せず、活動ラベルと AX も同じ状態か照合していません。エラー見出しは逆にソース内の `"エラー"` を要求し、モデルから正しく供給する実装を拒否します。
- **修正案：** 実カードの引数・Binding の getter/setter・表示ガードをモデルの結果と対応づける。見出し、補足、件数、意味色、活動 AX を個別に誤配線した負例を追加する。

**4. コメント内の偽宣言と未使用呼び出しを接続として認める**

- **該当行：** [Ruby:181](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task46-wiring.rb:181)、同276–277・292–322・525・572。
- **理由：** 宣言抽出はコメント・文字列を除外する前のソースへ正規表現を適用します。実宣言より前のコメントに正常な `struct TaskListCell { … }` を置くと、その内部を検査対象として抽出できます。また、思考・タスクのモデル検査は直接 `include?` を使い、用意された破棄呼び出し除去すら適用していません。`let unused = TranscriptItemPresentation.taskList(...)` の結果利用も判定しません。
- **修正案：** 宣言位置を字句解析上のコード領域から選び、返される View に使われる値だけを追う。偽宣言、未使用変数、戻り値破棄をそれぞれ単独の負例にする。

**5. 変更範囲検査が本番の変更一覧を取得せず、恒久的な構造比較もない**

- **該当行：** [Ruby:676](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task46-wiring.rb:676)–740、同1276–1278。
- **理由：** 範囲外変更を受け取る `extra_changed` は fixture にしか入りません。本番の `worktree_files` は生成せず、固定5パス外の変更を検出できません。許可ファイル内の比較も一部の型だけで、既存の `CommandGroupHeader`、コピー、差分描画、タスクの状態・AX、サブエージェント操作などが対象外です。構造の基準比較はすべて scope 分岐内にあり、契約237行の恒久保護がありません。
- **修正案：** B46 からの実変更一覧を取得し、許可した変更部分以外を構造単位で比較する。後続タスクでも不変の構造は恒久検査へ分離する。

**6. task-40 の文字体系を参照1個で代用できる**

- **該当行：** [Ruby:498](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task46-wiring.rb:498)–502、同1106–1110。
- **理由：** フォント・余白・行間を区別せず、3種類の名前のいずれかが残れば接続ありとします。本文フォントを固定値へ戻しても `TranscriptTypography.withinAnswer` が残れば検出されません。正常 fixture 自体が倍率を `1` に固定しており、倍率追随も守れません。実 [ChatScaledFont.swift:8](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatScaledFont.swift:8) の転送先も検査対象に含まれません。
- **修正案：** フォントの役割・倍率、余白、行間を別々に確認し、既存アダプター経由の転送を追う。それぞれ1箇所だけ退行させた負例を追加する。

**7. 通常実行では目視ハーネスのアサーションを丸ごと回避する**

- **該当行：** [目視ハーネス:21](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask46Tests.swift:21)–24、[契約:289](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-46.md:289)。
- **理由：** 環境変数なしでは副作用のある処理へ進みませんが、固定シナリオの確認も一切行わず成功します。契約は通常実行時の自動確認を要求し、環境変数によるアサーション回避を明示的に禁止しています。
- **修正案：** 固定シナリオと状態アサーションは常時実行し、ウィンドウの表示・操作待ちだけを環境変数で切り替える。

**8. 目視ハーネスでは契約の更新・経路・表示条件を再現できない**

- **該当行：** [目視ハーネス:50](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask46Tests.swift:50)–95、同156–186・227–258。
- **理由：** 実行開始・完了をホスト生成前に終え、その後は不変配列を表示するだけです。同一 ID 更新、空白を挟む再表示、開閉後の実行終了を操作できません。`cmd-single` を含む3コマンドは連続しており、実 [グループ化処理:45](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptGrouping.swift:45) により1グループになります。単体経路・1件グループ・51件・501行もありません。幅720、倍率1、明テーマに固定され、composer 計測側には専用 AppStorage が注入されていません。
- **修正案：** 安定した Observable なシナリオモデルと操作ボタンを追加し、同じホスト上で更新・イベントを発生させる。単体経路を別途設置し、指定の件数・行数・幅・倍率・明暗を選べるようにする。composer と transcript に同じ設定を注入する。

## MEDIUM

**9. 描画上限・単体行の検査に、製品を通らない自己確認がある**

- **該当行：** [受け入れテスト:243](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptItemPresentationTests.swift:243)–245、同561・569。
- **理由：** 差分501行の確認は `min(501, 500)` と引き算だけで、実際の切り出しを呼びません。単体行 ID も期待値と fixture から作った配列を比較しています。実製品には [FileChangeCell.visibleSections:325](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift:325) があり、既存テストからも利用されています。
- **修正案：** 実セルの切り出し結果を固定期待値へ照合する。単体行の到達性は実 `ChatItemView` 経路で確認する。

**10. selftest が単一違反の検出力を証明していない**

- **該当行：** [Ruby:1072](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task46-wiring.rb:1072)–1118、同1237–1244。
- **理由：** 補足と実行状態、エラー見出しと色、フォントと余白を同時に変更しています。片方だけの欠落を見逃しても自己試験は成立します。環境変数による分離も述語とソース中の名前を確認するだけで、本番分岐の実行結果を比較していません。
- **修正案：** 1変更・1期待エラー集合へ分割し、同じ入力に対する scope 未設定／0／1 の本番判定を照合する。

**11. 終了処理が VM の購読を閉じない**

- **該当行：** [目視ハーネス:99](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/PMTranscriptVisualTask46Tests.swift:99)–102。
- **理由：** 終了するのは client のイベント stream だけです。VM は別途承認・質問の購読も開始し、それらを取り消す実 API は [ChatSessionViewModel.terminate:3062](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift:3062) です。途中で `#require` が失敗した場合の client 終了経路もありません。
- **修正案：** 正常終了・失敗の両経路で `await viewModel.terminate()` とウィンドウ解放を保証する。

**12. 基準ファイルの不存在と Git 取得失敗を区別していない**

- **該当行：** [Ruby:236](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task46-wiring.rb:236)–239、同439–445・472。
- **理由：** `git_show` は非ゼロ終了をすべて `nil` にし、新規製品ファイルについてはそれを正常な不存在として扱います。契約219行が要求する「不存在と Git 障害の区別」がありません。
- **修正案：** 基準 tree でパスの有無を判定し、存在する blob の取得失敗は stderr とともにエラーにする。