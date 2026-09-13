# レッスン下書き帳

### L-1 Swift Testingの集計件数を実走成功件数と同一視しない
- when: 正本Swiftテストの複数パッケージ結果を合算して報告するとき。
- why: `Test run with N tests ... passed` のNにdisabledによるskippedが含まれるのに、集計行だけを読んで全N件が実走成功と誤認した。
- fix: 全ログで個別の`✔ Test ... passed`と`➜ Test ... skipped`をパッケージごとに別集計し、別パスで再実走したテストと本当に未実走のテストを分けて報告する。
- 意義: 正本コマンドが成功しても未実走のE2Eを動作保証へ誤昇格させない。
- evidence: 2026-09-08 task8 — 「Dashboard集計1652件は個別成功1638件＋既設skip14件。実git別14件を含む8パッケージは成功3422件＋skip14件、更新12件は別。」原ログ `/tmp/phlox-task8-acceptance.9RLTtl/final-hook-path-verify.log`。
- count: 1
- status: open
- scope: project

### L-2 機械全体に可聴・可視の副作用を出す操作は、ホストの権限（TCC）を先に確認する
- when: VoiceOver・キー送信・画面操作など、ユーザーのMac全体に音や入力の副作用が出る操作を AppleScript/System Events で自動化しようとするとき
- why:  実行ホスト（このセッションの親アプリ）に Automation/Accessibility の TCC 権限が無いことを確認せず先に VoiceOver を起動したため、読み上げ文は取れず（-1743/-25211）、音だけが鳴ってユーザーを驚かせた
- fix:  副作用のある起動より前に、無害な Apple Events（例: `tell application "System Events" to key code` の空打ちや対象アプリへの軽い問い合わせ）で権限の有無を確かめ、無ければ起動せずユーザーへ「権限追加か代替手段か」を先に問う
- 意義: 証拠が取れない状態で機械全体の設定を動かす空振りと、ユーザーの不信を防ぐ
- evidence: 2026-09-11 task-8 VoiceOver試行 — 「voice overが勝手に作動しています。」
- count: 1
- status: open
- scope: project

### L-3 共有デスクトップでの GUI 操作をサブエージェントに委譲するとき、操作対象と禁止操作を列挙して縛る
- when: PM の目視ゲート用に、サブエージェントへ「Debug アプリを起動して画面を撮る」作業を委譲するとき
- why:  「撮影する」という目的だけを渡し、「System Events/AX click を使わない」「稼働中 Release を前面化・操作しない」「実 CLI を spawn するセッションを seed しない」を明示しなかったため、サブエージェントが Release Phlox を前面化・サイドバーを AX click し、別アプリ（ブラウザ）へ座標 click を着弾させ、実 claude CLI を1体起動した
- fix:  GUI 委譲のプロンプトには「許可する操作の白リスト（自分が起動した PID の起動・kill・screencapture -l のみ）」と「禁止（System Events・AX 操作・他 PID への操作・実エージェント spawn を伴うデータ seed）」を必ず書く。撮影対象が実セッション無しで描画されないと判った時点で止めて PM に返させる
- 意義: 共有デスクトップ上の誤操作はユーザーの作業と課金に直結し、取り消せない
- evidence: 2026-09-12 task-27 目視ゲート委譲 — 「稼働中の Release Phlox（PID 61465）を set frontmost で前面化」「実 claude CLI（PID 33746）が起動」
- count: 1
- status: open
- scope: project

### L-4 System Events の key code は「tell process」で指定した相手ではなく前面アプリに届く
- when: 自分が起動した Debug アプリの表示モードを切り替えるために System Events で `key code` を送るとき
- why:  `tell (process whose unix id is N) to key code …` と書いても、キーイベントは常に前面アプリへ配送される。ユーザーが別アプリ（Brave／Release Phlox）を前面で使っていたため、⌘⌃G が 3 回 Brave に着弾した。前面確認を撮影直前の 1 回しか行わず、キー送信の直前に行っていなかった
- fix:  自 PID への GUI 操作はキーイベントを使わず、AX の `click <element> of window 1 of process` で要素へ直接当てる（前面化不要・他アプリへ漏れない）。キーイベントがどうしても要るなら送信の直前に frontmost == 自 PID を確認し、不一致なら送らずスキップして記録する
- 意義: 共有デスクトップ上でユーザーの作業中アプリに未知のショートカットを撃ち込むのは取り消せない誤操作
- evidence: 2026-09-12 BUG-01 再現ハーネス run1 — 前面 Brave(PID 79793) に ⌘⌃G ×3。run2 はガードで Release Phlox(61465) 前面を検知しスキップ
- count: 1
- status: open
- scope: project

### L-5 配線検査（rb）の「自己比較禁止」を HEAD との不一致で実装させない
- when: 凍結した受け入れテスト・配線検査スクリプトが改変されていないことを rb スクリプトで機械確認させるとき
- why: 「テスト自身と比較しない」という要求を実装役（Cursor）が「HEAD の blob と不一致なら NG」と解釈し、実装後の HEAD では常に一致＝何も守らない検査になった。契約が比較対象（凍結 SHA の内容）を明示せず、否定形（〜と比較するな）だけを書いていた
- fix: 契約に「`baseline_commit` の blob と現在のファイルが同一・その SHA が HEAD の祖先・実装前マーカーが baseline に不在」を肯定形で列挙し、rb のセルフテストで「差分を入れたら RED」を凍結前に確認する
- 意義: 検査が形骸化すると独立レビューの客観層が消える
- evidence: 2026-09-13 task-38 敵対レビュー指摘「HEAD self-compare rule」、task-39 でも同型の再修正（c8a2010）が発生し Cursor 往復を各1回消費
- count: 2
- status: open
- scope: project
