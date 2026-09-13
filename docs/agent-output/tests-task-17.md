受け入れ検査 `.claude/scripts/task17-wiring.rb` を新規作成し、製品コード・契約・台帳は触っていません。

`ruby .claude/scripts/task17-wiring.rb --selftest` は **exit 0**（`task17-wiring --selftest: OK`）です。比較対象は常に `git show <TASK17_BASELINE>:macos/App/SettingsView.swift` の blob で、作業ファイル同士の自己比較や HEAD フォールバックはありません。

製品検査の RED は、契約どおり凍結前なので `TASK17_BASELINE` では走らせていません。selftest の「未実装」負例が、旧 3 ボタン（`RichButtonStyle` 残存・`.bordered` 欠落・焦点抑制が減らないこと）を理由に NG を返します。`TASK17_SELFTEST_SKIP_FREEZE` のような迂回は作っていません。

報告は `docs/agent-output/tests-task-17.md` です。PM 凍結後は `env TASK17_BASELINE=<SHA> ruby .claude/scripts/task17-wiring.rb` を実装前 RED → 実装後 GREEN で確認してください。`.claude/` は gitignore のため、凍結コミット時は `git add -f .claude/scripts/task17-wiring.rb` が必要です。コミットはしていません。先にタイムアウトした selftest は、検査が遅すぎて止まっていた途中実行です。その後に切り出しを速くして、最終の `ruby .claude/scripts/task17-wiring.rb --selftest` は **OK（exit 0）** になっています。追加の作業はありません。
on の識別: `Button("通知テスト")` / `Button("今すぐ確認")` / `Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver")`。各 1 件。所属は到達可能な Section「通知」「アップデート」「エージェント」と `generalForm` / `agentsForm`。`.buttonStyle(.bordered)` は修飾列の引数がちょうど `.bordered`（`.borderedProminent` の部分一致では合格しない）。
- `RichButtonStyle` 定義は `struct RichButtonStyle`、使用は `RichButtonStyle(`。文字列・コメントは数えない。
- `.focusEffectDisabled()` はコード上の呼び出し数を基準と比較し、減少はちょうど 3・対象 3 Button の直接修飾に限定。対象外の件数・所属は不変。
- 許可差分（対象 3 の `RichButtonStyle()`→`.bordered`、対象 3 の焦点抑制削除、`RichButtonStyle` 定義削除）を局所除去した残余を基準と同一比較。他 Section・宣言単位・destructive role / 色 / action / QR を保護。Section の欠落・重複・移動・順序変更、TabView 接続変更、未使用ヘルパー、`if false` 隠蔽、解析不能は拒否。
- 基準 blob は 5 タブ（`TabView` + `SettingsGroup.all`）かつ対象 3 Button に旧スタイルと焦点抑制、`RichButtonStyle` 定義ありであること。実装済み blob は基準にできない。

## selftest の正例・負例

負例は合格する正例へ違反 1 件を加えたもの（未実装は基準 fixture を現行として渡す）。

### 正例

- 文字列内の `//` を残す / 行コメントを除去する / `/* */` を除去する
- 補間文字列を保持する / 文字列中の括弧を壊さず Section を切り出す / 文字列内空白を正規化で消さない
- `@ViewBuilder` 改行の var を切り出す / 複数行 Button を切り出す / 対象 Button の `RichButtonStyle` を直接修飾として見る / 文字列中の `RichButtonStyle` は定義に数えない
- 実装前 blob は基準として受理
- 契約どおりの 3 置換・3 削除・旧定義削除
- コメント・改行・文字列中の括弧・URL・補間を正しく扱う
- 対象外に焦点抑制がある基準でも対象 3 件だけ削除
- HEAD と一致し得る SHA 形式は拒否しない / 契約 `baseline_commit` のクォート有無 / 凍結 rb と作業ツリーが同一 / git show と作業ツリーが同一

### 負例（製品）

- 文字列内空白の改変 / 構文切り出し失敗は nil
- 未実装（旧 3 ボタン・`RichButtonStyle`・焦点抑制を理由にする）
- 1 ボタンだけ旧スタイル / 旧定義残存 / 標準スタイルの欠落 / 別ボタンへの適用 / 強調スタイルへの置換
- 焦点抑制の残存 / 対象外の削除 / 親への移設 / 焦点無効化の追加
- 通知・管理・更新の action / 更新の disabled / 管理アイコン / ラベル / footer
- 失効の destructive role・色・action / QR 処理 / Binding・保存キー・既定値
- Section の欠落・重複・移動・順序変更 / TabView 接続変更 / 未使用コードへの退避 / 常時非表示への退避
- ヘッダーなど対象外宣言 / テーマ見本など対象外宣言 / 文字列内空白 / 構文切り出し失敗

### 負例（基準）

- SHA 欠落・不正 / HEAD 指定 / `HEAD~1` / `@` / ブランチ名
- 契約 `baseline_commit` 欠落・プレースホルダ・不正 / 環境変数との不一致
- blob 欠落 / 実装済み基準 / 凍結検査の改変 / git show 失敗は同一ではない

### 実行結果原文

```
task17-wiring --selftest: OK
```

exit 0。製品検査の RED は凍結前のため `TASK17_BASELINE` では示していない。selftest の「未実装」負例が、基準 blob と同じソースを現行として渡し、`RichButtonStyle` 残存・`.buttonStyle(.bordered)` 欠落・`.focusEffectDisabled()` が 3 件減少しないことを理由に非ゼロ相当の NG を返す。

## PM が凍結時に行うべきコマンド

契約 `baseline_commit` を実 SHA へ置換し、検査ファイルを `git add -f` した凍結コミットの SHA を `<SHA>` とする。実装前に RED、実装後に GREEN。

```sh
ruby .claude/scripts/task17-wiring.rb --selftest
env TASK17_BASELINE=<SHA> ruby .claude/scripts/task17-wiring.rb
```

契約記載の compact-test ラッパを使う場合:

```sh
~/.agents/scripts/compact-test task17-wiring-selftest ruby .claude/scripts/task17-wiring.rb --selftest
~/.agents/scripts/compact-test task17-wiring env TASK17_BASELINE=<SHA> ruby .claude/scripts/task17-wiring.rb
```

実装前の期待: selftest は OK。製品検査は旧 3 ボタン（`RichButtonStyle` 定義・使用、直接 `.bordered` 欠落、焦点抑制が基準比 0 件減）で NG。基準未設定・プレースホルダ・解析エラーは RED に数えない。実装後は両コマンド exit 0。

## 未対応事項

- 成功基準 3（task-35 / task-38 配線検査との衝突の正式改訂）は PM 所有。本担当では契約・先行検査を変更していない。
- 成功基準 4（Debug App ビルド）と成功基準 5（隔離 Debug・AX・目視）は未実施。PM / 観測担当の範囲。
- `env TASK17_BASELINE=<SHA> ruby .claude/scripts/task17-wiring.rb` の製品 RED は、契約 `baseline_commit` がプレースホルダのため未実行。凍結後に PM が行う。
- コミットしていない。

=== REPORT COMPLETE ===
