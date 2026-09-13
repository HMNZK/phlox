**判定：needs_changes。** 契約・4テスト・実コード・ADR・Ruby 検査を静的に照合しました。4テストと Ruby は凍結 SHA `a3822de` と一致しています。Ruby 自己検査は必須ラッパーの `mktemp: Operation not permitted` で実行に到達せず、Swift 実走・変異検査は **unverified** です。新規型不在によるコンパイル RED は指摘対象にしていません。

入力空間は、PTY／チャット、flower／derived／manual、rename 前後・同名・空白、本文の由来、追加・置換・復元、初回保存・PID・削除の順序、旧／未知 source に分けて確認しました。以下の行番号は実ファイル確認済みです。テストの現所在は `tasks/frozen/staged/` です。

## MUST

### M1. 「識別可能／不能」の履歴テストに、由来を区別する情報がない

**該当行：** `AcceptanceSessionTitleLifecycleTests.swift:463–525`、`ChatSessionViewModel.swift:826–844,868–889`、`ChatItem.swift:27`。

**理由：** 「サーバー履歴」と称する3ケースはいずれも通常の `ChatItem.userMessage` をローカル `TranscriptStore` に入れ、Claude 用クライアントで復元しています。実際には `threadRead` 経路を通りません。「識別不能」と「識別可能」の違いは本文と任意の ID だけで、元本文フィールドや対応情報はありません。この期待値は、契約194–199行が禁止する本文の見た目による推測を実装者へ要求します。

**修正案：** ローカル履歴とサーバー履歴を分離し、後者は実際の `threadRead` 経路へ注入する。由来情報の有無だけを変えた同一本文で採否を固定し、識別不能項目を飛ばすケースも同じ情報モデルで作る。

### M2. 凍結前の必須条件だった task-39 検査の改訂が未成立

**該当行：** `tasks/task-44.md:385`、`.claude/scripts/task39-wiring.rb:415–423,855–866,1348–1350`。

**理由：** 契約は、task-39 の全体不変比較を正式改訂し、未解決なら凍結しないと明記しています。しかし現在も `SessionViewModel.swift` と `PaneLayoutView.swift` が全体比較対象です。task-44 が要求する VM の名前状態追加と両立しません。

**修正案：** PM が名前関連差分を許容する限定比較へ改訂し、端末所有権・入出力の保護と検査自身の凍結を確立してから再凍結する。

### M3. task-44 の配線検査が通常の検証入口に接続されていない

**該当行：** `.claude/scripts/ui-ux-verify-task.sh:56–65`、`.claude/verify.sh:5–10`。

**理由：** task-44 分岐がなく、59行の汎用 verifier へ進みます。その既定先 `.claude/verify.sh` はパッケージテスト等のみで、task44 Ruby・自己検査・scope 検査を実行しません。契約にコマンドを書くだけでは、配線検査が下流の合否判定に入りません。

**修正案：** 実装ディスパッチ前に、59行の `exec` より前へ task-44 分岐を登録する。凍結テストの実パス復帰、固定 SHA、自己検査、scope／恒久検査、対象パッケージを接続する。

## HIGH

### H1. サーバー本文反映のテストが、別種のイベントを送っている

**該当行：** `AcceptanceSessionTitleLifecycleTests.swift:305–359`、`ChatSessionViewModel.swift:1490–1494,2014–2023`。

**理由：** 補足付きユーザー本文の反映を検査すべき箇所で、送っているのは `.agentMessageDelta` です。実製品のユーザー項目反映は `.itemStarted／.itemCompleted` → `chatItem` → `appendOrReplace` です。また327・337行からのケースはイベント投入後に処理完了を待たず、305行のケースも全イベント処理を保証しない条件で待っています。質問「回答」の入力もありません。

**修正案：** 現在 thread に一致するユーザー項目イベントと対応 ID を使い、補足付き本文を実際に反映させる。各対象外項目・質問回答も独立させ、対象イベントの反映完了を確認してから名前を検査する。

### H2. 置換・巻き戻しと、復元待機中 rename の競合を起こしていない

**該当行：** `AcceptanceSessionTitleLifecycleTests.swift:363–404`、`ChatSessionViewModel.swift:827–830,1042–1073`。

**理由：** 置換テストはテストストアを直接変更するだけで、VM に再読込・置換・`revert` を実行させません。復元競合テストは履歴なしで `client.resume` を止めていますが、現行のローカル履歴取込みはその前です。rename 後に古い候補が戻ってくる状況を検査できません。

**修正案：** VM の実際の置換・再読込・巻き戻し経路を呼ぶ。競合ケースは適格本文を返す履歴取得を停止し、rename 後に解放する。derived／manual の両方を固定する。

### H3. 初回保存前の変更・削除が未被覆

**該当行：** `AcceptanceSessionTitlePersistenceTests.swift:141–180`、`DashboardViewModel.swift:1113–1144`。

**理由：** テストは `await spawnNewClaudeCodeSession()` 完了後に rename します。この時点では初回 descriptor が既に保存キューへ投入されています。実際の危険区間は、VM 登録後から PID 取得などの待機を経て初回保存するまでです。初回保存前の自動導出、およびその区間の削除もありません。

**修正案：** `livePIDProvider` 等の既存待機点で spawn を止め、未保存を確認して導出・rename・削除を行い、その後解放する。PTY／チャットの該当ケースを分ける。

### H4. PID テストのゲートは解放を取りこぼし、無期限待機し得る

**該当行：** `AcceptanceSessionTitlePersistenceTests.swift:49–62,543–558`、`SessionRestoreCoordinator.swift:149–170,206–222`。

**理由：** 待っているのは A のノード出現だけです。A は復元完了・PID 取得前に公開されます。B が continuation を登録する前に `release(idB)` が呼ばれると解放が消え、後から B が永久停止します。また、PID 更新時の「他メタ情報保持」は何も変更・検査していません。

**修正案：** A の復元完了と B の待機到達を明示的に待つ。解放済み状態を記録し、失敗時の後始末と期限を設ける。B 待機中に role 等も更新し、最終 descriptor で保持を検査する。

### H5. 復元中削除の期待値と既存 ADR の扱いが未裁定

**該当行：** `AcceptanceSessionTitlePersistenceTests.swift:552–560`、`SessionPersistenceCoordinator.swift:110–117,318–325`、`macos/docs/adr/0024-restore-gate-and-commands-reactivity.md:17`、`E2EPersistenceTests.swift:280–296`。

**理由：** 新テストは復元中に削除を完了させ、復元終了後のストアから消えることを要求します。既存実装・ADR・既存テストは復元中の件数減少保存を抑止します。現行の削除は抑止された後に再実行されないため、PID を現存 descriptor の更新だけに直しても新期待値を満たしません。ゲートを単純に撤去すると既存保護を壊します。

**修正案：** 復元中の明示削除を終了後へ繰り越すなど、既存保護を維持する方針を契約へ明記する。削除の要求時点・保存時点・PID 更新との順序をテストで固定する。

### H6. 早期ガード検査が制御フローを検査していない

**該当行：** `.claude/scripts/task44-wiring.rb:311–337,367–375`。

**理由：** 抽出呼出しの前1200文字に `.derived`・`.manual`・`return` があれば合格します。無関係な条件や未実行クロージャ内の return でも条件を満たせます。一方、正しい `guard source == .flower else { return }` は拒否します。computed property、別ヘルパー経由の走査、同一関数内の後続呼出しも十分に追跡していません。

**修正案：** 名前採用の実経路と支配するガードを限定して検査し、同等の正しいガードを許容する。無関係な return、ヘルパー経由、ガード単独削除を独立した負例にする。

### H7. Ruby の主要な配線検査と自己検査が、必要な処理の欠落を見逃す

**該当行：** `.claude/scripts/task44-wiring.rb:382–510,574–600,642–798,892–929`。

**理由：**

- CodingKeys 検査はファイル全体にフィールド名があるかを見るだけで、引数宣言だけでも条件を満たします。
- VM・保存・復元失敗の検査は `titleState` 等の単語だけで、引数の値・保存接続・最新状態取得を確認しません。
- PID 検査はファイル内の無関係な `firstIndex` でも生存確認扱いになり、古い全体保存は特定の綴りしか拒否しません。
- 正例には未使用ヘルパー、`renamed` が `self` を返す実装、名前メタ情報を encode しない descriptor が含まれます。
- 「initializer 正規化欠落」の負例は initializer を変更せず、「補足付き本文採用」の負例も由来ではなくガード欠落で落ちる構成です。

**修正案：** 各入口から状態設定・四フィールド更新・同じ保存キューまでを検査する。正例を契約成立例へ置換し、負例は対象違反だけを変更して、対応するエラー集合全体を比較する。

### H8. scope と既存処理保護が、契約の範囲を検査していない

**該当行：** `.claude/scripts/task44-wiring.rb:548–569,604–639`、`tasks/task-44.md:337–347`。

**理由：** 比較へ渡すファイルは許可パスと追加2ファイルだけで、別の製品ファイル変更を発見できません。許可パスは内容を丸ごと比較対象外にしています。PTY 検査は自動導出の呼出しだけ、AI 呼出し検査はパスに `SessionTitle` を含むファイルだけです。送信・認可の変更や、Chat VM に追加した命名用通信を保護できません。

**修正案：** 基準との差分から製品変更ファイルを列挙する。許可ファイル内も名前関連の限定差分以外を比較し、認可・送信・PTY・秘密情報保護は指定領域を恒久検査する。

### H9. 「エラー記録へ到達」を検査していない

**該当行：** `AcceptanceSessionTitlePersistenceTests.swift:300–323`、`AcceptanceSessionTitleDescriptorTests.swift:320–355`、`SessionPersistenceCoordinator.swift:106,127–130`、`.claude/scripts/task44-wiring.rb:382–398,458–489`。

**理由：** 保存失敗テストは保存試行回数と VM の名前しか検査しません。既存の初回保存の `try?` が残っても検出できません。未知 source・不整合 source の decode も診断出力を検査せず、Ruby にも診断接続の検査がありません。

**修正案：** 初回保存失敗と既存セッションの名前保存失敗を分離し、既存 `logError` の受信を観測する。decode のフォールバック分岐から診断への接続も、削除変異で検査する。

### H10. 花名保持の自己比較と、確率に依存する重複検査

**該当行：** `AcceptanceSessionTitlePersistenceTests.swift:157,180–181,201,231,235–263`、`FlowerNameGenerator.swift:4–20`。

**理由：** 保存された `flowerName` 自身を期待値へ渡している箇所は、保持の検査になりません。重複回避も Rose 1件だけで1回抽選しており、除外が壊れていても30候補中29候補で見逃します。Ruby に除外集合の実配線検査もありません。

**修正案：** rename 前の花名を保存し、保存・復元後と比較する。重複検査は既存花名一覧をすべて予約するなど、乱数に依存せず除外欠落を検出できる入力にする。

## MEDIUM

### D1. typography の恒久検査が現在内容との自己比較

**該当行：** `.claude/scripts/task44-wiring.rb:524–545,599,1056–1067`。

**理由：** `check_typography(files, files)` のため、凍結時の参照削除・定数化・ダミー追加を比較できません。参照名の集合比較だけでは、引数・適用位置・使用回数の変更も保護できません。

**修正案：** scope の有無にかかわらず凍結 blob を比較元にする。直接参照がないファイルはその事実を固定し、既存の委譲経路を必要な範囲で保護する。

### D2. 状態・descriptor の境界と実保存フィールドに穴がある

**該当行：** `AcceptanceSessionTitleStateTests.swift:148–157,252–257`、`AcceptanceSessionTitleDescriptorTests.swift:26–50,205–224,306–317,358–431`、`PersistedSessionDescriptor.swift:182–220`。

**理由：** 以下の領域に対応する検査がありません。

- 33文字以上で `name != fullDerivedTitle` になる正常な derived 状態。
- source 不在／null の JSON に孤立した花名・導出全文がある場合。
- descriptor の公開メタフィールド自体の正規化結果。現在は主に `titleState` の結果だけを検査。
- resumeID、親子関係、launchContext、Codex 設定等の既存更新後の名前保持。

38行の「descriptor.name matches」は descriptor を参照せず、34行と同じ比較です。

**修正案：** 上記を独立リテラルで追加し、descriptor の実フィールド・encode 結果・読み取り状態が一致することを検査する。

### D3. 復元失敗・送信拒否の入力領域が不足

**該当行：** `AcceptanceSessionTitlePersistenceTests.swift:326–397`、`AcceptanceSessionTitleLifecycleTests.swift:238–281,408–459`、`ChatSessionViewModel.swift:2802–2835`。

**理由：** 復元失敗プレースホルダは両 backend とも flower だけで、derived／manual／空名を通していません。状態復元4種類のテストは VM へ状態を直接渡すため、descriptor からの受け渡しを代替できません。適格本文を含む送信前拒否もありません。通信失敗ケースは、実際に失敗したことや成功状態へ誤遷移していないことを確認しません。

**修正案：** 両プレースホルダへ4状態を descriptor 経由で渡す。適格本文が送信前ガードで拒否されるケースと、確定後に通信失敗するケースを分け、本文確定・送信呼出し・状態を確認する。

### D4. 完全 SHA 必須の条件を自己検査が逆に否定

**該当行：** `tasks/task-44.md:353`、`.claude/scripts/task44-wiring.rb:245–260,964–965`。

**理由：** 契約は `TASK44_BASELINE` に完全 SHA を要求しますが、実装は7〜40桁を許容し、自己検査も7桁を正例にしています。

**修正案：** 環境変数は40桁に限定する。契約側の短縮 SHA は完全 SHA へ解決して一致比較し、7桁入力を負例へ変更する。