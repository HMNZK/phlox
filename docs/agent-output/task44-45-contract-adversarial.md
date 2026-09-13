---
status: completed
verdict: requires_revision
reviewed_head: dcd9cf313b58e4f2e538e12acd6ac8b5ffae7dd1
output_file: docs/agent-output/task44-45-contract-adversarial.md
file_saved: false
---

指定の6観点を契約本文と実コードで照合し、MUST 1件、HIGH 4件、MED 3件を検出した。受け入れテスト・ビルド・GUIは実行していない。読み取り専用環境のため、指定ファイルへの保存は未実施。

先行task-41について、公開API名は一致するが、`SessionTitleDeriver.swift:124` は現在も行全体を半角変換しており、`tasks/task-41.md:160` の確定修正と不一致。task-44が要求する「task-41成立後」の凍結前提は、現在の実コードでは確認できない。

1. **MUST — task-40の不変検査と両契約が衝突する〔⑤〕**

   `tasks/task-44.md:266` と `tasks/task-45.md:192` はtask-39との衝突だけを扱う。しかし `.claude/scripts/task40-wiring.rb:253` は、task-44が変更する `ChatSessionViewModel.swift`・`DashboardViewModel.swift` と、task-45が変更する `ChatSessionView.swift` を全ファイル不変対象にしている。同スクリプト`:1220`・`:2241` は凍結blobとの比較を実施するため、契約どおりの実装でも先行検査が失敗する。現行 `.claude/verify.sh` はこのRuby検査を実行せず、統合ゲートだけでは衝突を検出できない。

   **契約修正案:** task-40の保護検査改訂・独立レビュー・再凍結をPMの着手前条件へ追加し、名前関連差分だけを許す改訂版の回帰実行を両契約に明記する。

2. **HIGH — 公開initializerが作れる不整合状態の扱いが未定義〔②③〕**

   `tasks/task-44.md:94` の公開initializerは、`source: .derived, fullDerivedTitle: nil` や、名前と花名が異なるflower状態を構築できる。descriptorの読み込み規則はあるが、このinitializerの正規化・拒否規則はない。一方、`tasks/task-45.md:98` はderivedの任意値から非Optionalの `fullTitle` を返すことを要求し、`:106` は表示側での状態正規化を禁じている。したがって、この入力の期待値を契約から一意に決められない。

   **契約修正案:** 公開initializer・生成関数・descriptorで共有する状態不変条件と不整合時の結果を固定し、derived全文nil・flower不一致・空白だけの花名をリテラル期待値へ追加する。

3. **HIGH — サーバーから戻る送信用本文の混入条件が未被覆〔②③〕**

   `tasks/task-44.md:140` は送信用補足の混入を禁止するが、`ChatSessionViewModel.swift:2014` はサーバーの開始・完了イベントを `chatItem(from:)` 経由でメインtranscriptへ格納する。ローカル履歴がない復元も同ファイル`:877` → `:2462` → `:2484` でサーバー本文をuserMessageへ変換する。例えば花名状態で、ローカル本文が導出不可の `/review`、送信文字列には再送補足が付いている場合、その補足を含むサーバー本文が後から候補になり得る。「メインtranscriptのuserMessage」と「元のユーザー本文」が一致しない場合の採否が未定義である。

   **契約修正案:** ローカル本文・サーバー反映・サーバー履歴復元ごとの候補採用条件を定め、元本文を識別できない補足付き入力では花名を維持する等の期待値を固定する。

4. **HIGH — 復元完了時のPID書き戻しが名前を巻き戻す競合が未被覆〔②③〕**

   `SessionRestoreCoordinator.swift:169`・`:221` は復元開始時のdescriptorからPID更新用スナップショットを作り、`:92` で全セッション復元後に保存する。保存先の `SessionPersistenceCoordinator.swift:104` は同じIDのdescriptor全体を置換する。この間に導出・手動renameが保存されると、後続のPID保存が古い名前を戻し得る。`tasks/task-44.md:179` の初回保存競合、`:148` の復元待機中の手動変更保護だけでは、この別経路の最終保存値が明示されていない。

   **契約修正案:** 復元Aの名前変更を保存後、復元Bの待機を解放してPID書き戻しを実行する順序を固定し、保存名4フィールドが最新状態のままで削除済みAも復活しないことを受け入れ条件へ追加する。

5. **HIGH — 課金なしの到達手順が単体PTYまで保証していない〔⑥〕**

   `tasks/task-45.md:249` の正本手順は `backend: appServer` 用であり、単体PTYへは到達しない。PTYの復元失敗経路は `SessionSpawnService.swift:735` で保存済みcommandを起動要求へ渡し、`:757` の起動抑止は限定条件でしか有効にならない。通常の `markRestoreFailed` は起動を抑止せず、画面のサイズ通知から `SessionViewModel.swift:644` → `:658` → `:293` と遅延起動する。custom kindのbinary不在だけでは、保存済みcommandの起動まで防げない。

   **契約修正案:** PTY専用fixtureのbackend・command・args・env・pid不在・作業場所を固定し、描画・サイズ変更後も課金CLIが起動しないことを確認する手順を4面ゲートへ追加する。

6. **MED — 単体ヘッダー追加と既存ADRの整合を取る担当・変更範囲がない〔④⑤〕**

   `tasks/task-45.md:121` は旧コメントの更新だけを要求するが、ADR 0042`:24` は選択名を設定ギアと同じ行へ集約し、ADR 0073`:23` は単体・グリッドとメイン・サブのヘッダー高さを揃える決定を記載している。現在の `ChatSessionView.swift:32`・`:39` はメインとサブを横並びにし、`SubAgentDrawerView.swift:63` は共有高さを使用する。新設ヘッダーがどの決定を維持・変更するか不明で、ADRの更新パスも許可範囲にない。

   **契約修正案:** ヘッダー位置とサブペインとの高さ整合を裁定し、該当ADRの更新をPMの凍結前作業へ割り当てるか、必要な文書パスをallowed_pathsへ追加する。

7. **MED — 表示ゲートにテーマ・実際の名前領域幅・コントラスト条件がない〔②③⑥〕**

   `tasks/task-45.md:228` は通常幅とウィンドウ幅1024ptだけを指定する。実際のグリッドは `PaneLayoutView.swift:22` の240pt幅まで縮み、サイドバーでは階層の字下げと時刻表示も名前幅を消費する。さらに `docs/phase0.md:25` が要求する明暗テーマ、文字と背景の組合せ、小さい文字の4.5:1以上という条件が本契約に引き継がれていない。広い名前領域と一つのテーマだけで目視ゲートを通過できる。

   **契約修正案:** 明暗テーマ・選択／注意状態・深い階層・240ptペインを検査条件に固定し、主名と補助花名のコントラストおよび操作領域の欠けを独立した合否条件にする。

8. **MED — 「確定後は全件走査しない」を反証する検査が指定されていない〔③〕**

   `tasks/task-44.md:147` はderived／manual確定後の全件走査を禁止する。しかし成功基準は名前の不変を検査するだけで、走査の有無は区別しない。状態遷移が無変更を返す限り、確定状態のガードを削除して毎回履歴全件を走査しても、記載された状態・保存結果は同じになる。Rubyの必須項目にも、この早期終了の保護はない。

   **契約修正案:** 確定状態では履歴抽出へ到達しないことをRuby検査と単独のガード削除変異で保護するか、走査回数を観測できる受け入れ検査を指定する。

=== REPORT COMPLETE ===