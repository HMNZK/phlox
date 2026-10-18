---
status: accepted
last-verified: 2026-10-17
---

# ADR 0216: 入力欄の設定（推論の深さ・権限・Plan）とプロジェクト一覧を Control API に載せる

> **このファイルの役割**: iPhone から推論の深さ・権限・Plan を新規作成時と実行中に指定でき、プロジェクトを一覧から選べるようにするとき、それをどうワイヤに載せ・どう失敗させるかの決定理由。
> **書かないもの**: ワイヤの詳細な形とエラー表（→ [ios/docs/specs/mobile-api-extensions-contract.md](../../../ios/docs/specs/mobile-api-extensions-contract.md) §8）、現行のエンドポイント表（→ [architecture/mobile-proxy.md](../architecture/mobile-proxy.md)）。

## 文脈

iPhone の入力欄を Mac の新規チャットと揃える（iOS 再設計）。Mac の中には仕組みが揃っている。新規チャットは
`CodexAppServerSessionSettings`（モデル・推論の深さ・権限・Plan）を初期設定として `launchNewChat` から渡し、
実行中は `ChatSessionViewModel` の `setModel(model:effort:)`・`setPermissionProfile(id:)`・`setPlanMode`・
`setSpawnAgentPermission`・`setSpawnAgentEffort` で変える。足りないのは Control API の入口だけだった。

- `POST /sessions` は kind/backend/workingDirectory/projectId/role/model しか受けず、`spawnNewSessionFromControlAPI` は初期設定を渡さない。
- 実行中に変えられるのはモデルだけ（`POST /sessions/{id}/model`）。`GET /sessions/{id}/settings` はモデルしか返さない。
- 権限・推論の深さの選択肢と表示名が iPhone に届かない。
- プロジェクトの取得口が無く、iPhone は `GET /sessions` の projectId/projectName から組み立てるしかない。セッションが 0 件のプロジェクトが見えない。

## 決定

1. **新規作成時の設定は `POST /sessions` の省略可の 3 項目（`effort`・`permission`・`planMode`）で受け、Mac の新規チャットと同じ初期設定（`CodexAppServerSessionSettings`）として起動時に適用する。**
   - 値は `ControlRequest.Action.spawn` の associated value で運ぶ。`ControlSpawnContext`（TaskLocal＋actor の一時状態）には足さない（ADR 0141 と同じ理由。並列テストで踏み合う）。
   - 3 項目のどれかがあるときは `model` も初期設定に入れ、spawn 後の `setSessionModel` は呼ばない。Codex ではこの後追いの適用が推論の深さを既定に戻すため。3 項目とも無いときは従来の経路をそのまま通す（古い iOS の互換）。
   - 新項目は**不正な値を 400 で拒否する**。`model` の「黙って無視」は互換のために残すが、新項目には広げない（黙って既定で作ると、指定が効いていないことに気づけない）。
   - PTY では設定が意味を持たないので、新項目付きの PTY spawn は 400。
2. **実行中の変更は `PATCH /sessions/{id}/settings` の部分更新 1 本にする。** 取得口の `GET /sessions/{id}/settings` と対にする。モデルは既存の `POST /sessions/{id}/model` のまま変えない。
   - Mac の入口は種類ごとに throw したり黙って return したりと揃っていない。Control API 用に、失敗を握りつぶさない結果型（適用・不正値・非対応・変更中・thread 開始前・失敗）を `ChatSessionViewModel` に置き、`applyControlModel` と同じ形でステータスへ写す（400・409・409・425・500）。
   - 「変更中」で拒む条件は Mac の入力欄と同じものを使う（権限の切り替え中・送信中・画像送信の準備中）。新しい条件は作らない。
   - 非対応は 409 にする。§6 の model が非対応を 404 にしているのは凍結済みなので変えない。新しい口は、セッションはあるのに変えられないことを区別できる 409（interrupt・画像と同じ流儀）にする。
3. **選択肢は値と表示名の組で返し、Mac の画面と同じ出所から作る。** 新規作成用は `GET /agents/{kind}/settings`（新設）、実行中用は `GET /sessions/{id}/settings` に追加する。
   - 新規作成用は Mac の新規チャット画面の選択肢、実行中用は Mac の実行中セッションの入力欄の選択肢をそのまま使う（同じ関数を共用し、写しを作らない）。
   - 表示名は Mac のアプリの言語設定で返す。iPhone は訳さない。
   - Plan は権限の選択肢に入れず、Bool で別に扱う（`CodexAppServerSessionSettings` の `selectedPermissionProfile`＋`isPlanMode` と同じ形）。
4. **プロジェクト一覧は `GET /projects`（新設）で id と名前だけを返す。** id は `projectId` と同じ文字列にして、そのまま `POST /sessions` に送れるようにする。

## 棄却案

- **実行中の変更を項目ごとのエンドポイントに分ける**（`/effort`・`/permission`・`/plan-mode`）: 口が 3 つ増える。取得口が 1 つ（`/settings`）なのに更新口がばらけ、iPhone が対応を覚える必要がある。
- **`GET /agents/{kind}/models` の各モデルに選択肢を足す**: 凍結済みの `ModelCatalogTests` が組み立てる型（`ControlAgentModelsResponse`）を変えることになる。権限はモデルに属さないので置き場所も合わない。
- **表示名を iPhone 側で持つ**: 値の対応表が Mac と iPhone の 2 か所に分かれ、Mac 側の文言変更に追随できない。
- **`Accept-Language` で表示言語を選ぶ**: `ControlRequest` にヘッダを通す配線が増える。利用者は Mac と iPhone を同じ言語で使う前提で、まずは Mac の設定に揃える。必要になったら足す。
- **新項目の不正値を黙って無視する**（`model` と同じ）: ADR 0141 と同じ理由で棄却。

## 結果

- iPhone は Mac の新規チャットと同じ選択肢・表示名で推論の深さ・権限・Plan を選んで始められ、実行中にも変えられる。
- 古い iOS（新項目を送らない）は今までどおり動く。`GET /sessions/{id}/settings` はキーが増えるだけ。
- 新しい iOS と古い Mac では、`POST /sessions` の新項目が黙って無視され既定で作られる（ADR 0141 と同じサイレント劣化）。新しい取得口は 404 になるので、iOS は非対応として扱う。
- 新規チャットの推論の深さは Mac の新規チャット画面の規則（`haiku` は無し）に、実行中の推論の深さは実行中の入力欄の規則（`claudeModelSupportsEffort`）に従う。両画面の規則の食い違いはそのまま写る。
- 承認の「このセッション中は許可」は当初は範囲外としたが、下の追記で Claude Code の分を足した。

## 追記（2026-10-17）: Claude の「このセッション中は許可」と、model の 409

5. **Claude Code の「このセッション中は許可」は、質問カードに `allowsSessionScope`（省略可）を足すだけで返せるようにする。**
   - Claude のツール使用許可は `/approvals` ではなく質問カード（`POST /sessions/{id}/question`）として iPhone に届く。Mac の承認カードはこの質問に隠しラベル `"AllowForSession"` を答えるだけで、Control API の `/question` も同じ `ChatSessionViewModel.respondToUserQuestion` に届く。足りないのは「その質問で返せるか」を iPhone に伝える項目だけだった。値の出所は `ChatToolPermission.allowsSessionScope`。
   - 省略可にし、通常の質問では出さない。`options` に 3 つ目の選択肢を足さないのは、古い iOS がそれを普通の選択肢として表示してしまうため。
   - 棄却案: Claude の許可を `/approvals` に統一する。承認 ID の形が違う（Codex は UUID、Claude は transcript の項目 ID）ことと、Mac の承認カードの「出てから 0.5 秒は受け付けない」守りの扱いを作り直す必要があり、配線だけでは済まない。
   - Cursor には対話的な承認が無いので対象外。Codex は従来どおり `/approvals` の `acceptForSession`。
6. **`POST /sessions/{id}/model` の「Mac が変更を受け付けない状態」を 500 から 409 に変える。** §6 は凍結していたが、同じ状態を新しい PATCH は 409 で返すので、同じ API の中で意味が割れないよう揃える。本当の適用失敗は 500 のまま。iOS の `setModel` は 500 を特別扱いしていない（失敗を黙って現状維持にするだけ）ことを確かめたうえで変える。

## 追記（2026-10-17）: 承認一覧に操作の種類を足す

7. **`GET /approvals` の各要素に、省略可の `actionKind`（`command`・`fileChange`・`permissions`）を足す。** iPhone の承認カードの見出し「承認待ち · {操作の種類}」（iOS 再設計の D2）を Codex でも出すため。
   - 出所は Mac の承認カードと同じ `ChatApprovalRequest.kind`（`ChatApprovalKind`）。写すのは中立型 `ControlApproval` を作る 1 か所だけにする。
   - 既存の `kind` はエージェントの種類のまま変えない。名前が似ているが、意味を変えると古い iOS（`kind` を `AgentKind` として読む）が承認を捨てる。
   - 表示名ではなく固定の語で返す。Mac の見出しの文言は翻訳を通るため、値として送ると iPhone で比較できない。
   - 棄却案: `prompt` の文字列から推測する。Mac の文言の変更で壊れる。
   - Claude Code の許可はこの一覧に載らない（追記 5 の質問カード）ので対象外。

## 追記（2026-10-17）: 一覧の無応答・未読・親子・端末と、許可の質問の印

8. **`GET /sessions` の各要素に `backend`・`isStalled`・`hasUnseenCompletion`・`parentSessionId`・`statusEnteredAt` を足し、並びを Mac のサイドバーの順にする**（契約 §8.10。iOS 再設計の U-2・U-3・U-6）。
   - iPhone の一覧を Mac のサイドバーと同じ規則で描くため。表示の状態は値を送るのではなく、元の値を送って iPhone も共有の `SessionDisplayState.resolve` で決める。規則を 2 か所に持たない。
   - `status` は変えない。Phlox CLI の `wait` などが今の意味で使っている。背景作業中の昇格（`displayStatus`）は一覧の見た目のための値で、CLI の完了判定に混ぜると待ちが変わる。
   - 「終了」は足さない。Mac の `SessionStatus` に無く、端末のプロセスが終わると完了（終了コード 0）かエラーになる。新しい状態を作るのは Mac の挙動を変えることになり、iPhone の再設計の範囲を超える。
   - 端末かどうかは `backend`（spawn の `backend` と同じ語）。iPhone は端末のセッションを会話の形で読めないので「表示できません」を出す（iOS ADR 0044）。
   - 棄却案: 表示用の状態の語（「無応答」「未読」）を Mac が文字列で返す。表示言語に依存し、iPhone で比較できない。
9. **質問に `toolName`・`toolDetail` を足す**（契約 §8.11。U-8）。Claude Code のツール使用の許可の質問を、iPhone が Mac と同じく承認のカードで出すため。`allowsSessionScope` は false のときにキーが省かれるので、許可の質問かどうかの印にならなかった。出所は `ChatUserQuestion.permission`。
   - 棄却案: 形（選択肢が Allow・Deny の 1 問）から iPhone で見分ける。Mac の文言の変更で壊れる。

## 追記（2026-10-18）: 新規チャットの既定を Mac から返す

10. **`GET /agents/{kind}/settings` に省略可の `defaultEfforts`・`defaultPermission` を足す**（契約 §8.2）。iPhone の新規チャットが保存値の無いときの初期値を、Mac の新規チャットと同じにするため。
    - 足さないと iPhone が既定を自前で持つことになり、Claude の権限の既定（Mac の「Bypass を使う」設定で bypassPermissions か auto かが変わる）を iPhone が推測するしかない。推測で `bypassPermissions` を送ると、Mac で Bypass を切っている利用者のセッションが iPhone からだけ強い権限で始まる。権限を強める方向の推測は避ける。
    - 古い Mac ではキーが無い。iPhone は推論の深さ・権限を送らず、Mac の既定で起動する（§8.1 の「省略」と同じ）。

## 追記（2026-10-18）: 発言・返答の時刻を返す

11. **`GET /sessions/{id}/messages` の `user`・`agent` の要素に省略可の `createdAt` を足す**（契約 §8.12。iOS 再設計の U-24）。iPhone の長押しのメニューの見出しに、見本どおり発言の時刻を出すため。
    - Mac の `ChatItem` は時刻を持っているが、ワイヤに載せていなかった。iPhone には他に時刻の出所が無く、取得した時刻で代えると表示が嘘になる。
    - 使い道が長押しの見出しだけなので、`user`・`agent` 以外には付けない。
    - 棄却案: 見出しを出さない。見本（`ChatCopy`）から外れ、どの発言をコピーするか見分ける手がかりが減る。
