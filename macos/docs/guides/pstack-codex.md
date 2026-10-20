---
status: active
last-verified: 2026-10-20
---

# Phlox の Codex で pstack を使う

Codex 向けの独立した移植版をローカルプラグインとして導入する。Cursor 本体は不要。Cursor Automations、Grok Bot、Cursor cloud VM、永続的な `/loop` は提供しない。対応方針は [設計](../architecture/pstack-codex.md) を参照。

## 導入

必要なものは Python 3.9 以降、Git、プラグイン機能付き Codex CLI、ログイン済みの Codex。Bun と `gh` は該当する補助スクリプトを実行するときに必要になる。

リポジトリルートで実行する。固定コミットの上流を `.verification/pstack-codex/upstream/` に取得する。導入後も出力先を保持する。

```sh
python3 integrations/pstack-codex/build.py \
  --output "$HOME/.local/share/phlox/pstack-codex/0.15.28-codex.4"
codex plugin marketplace add "$HOME/.local/share/phlox/pstack-codex/0.15.28-codex.4" --json
codex plugin add pstack-codex@phlox-pstack --json
```

成功時は `phlox-pstack` と `pstack-codex@phlox-pstack` が登録され、59 個のスキルを含むインストール先が返る。`make-bot-ui` は非対応を説明する入口として含まれる。59 個すべてのワークフローが同等動作するという意味ではない。

長いスキルは短い入口と同じフォルダの `workflow.md` に分ける。Codex の入力上限で本文を失わないよう、入口から対応表と全文を先に読む。

## Phlox から使う

1. Codex の新規チャットを開始する。
2. 入力欄に `/pstack-codex:poteto-mode` と入力し、表示された候補を選ぶ。
3. `$pstack-codex:poteto-mode` に置き換わったことを確認し、依頼を続けて入力して送信する。

```text
$pstack-codex:poteto-mode この不具合を再現し、原因を修正してテストしてください。
```

候補の更新後に再選択を求められた場合は、再び検索して選ぶ。候補が現れなければ `codex plugin list --json` で有効状態を確認し、新しい Codex セッションで読み込む。

本変更を含む Phlox は、更新通知後も候補とファイル内容が同じなら選択を保持する。変更前の Release では通知直後に再選択を要求され、送信できない事象を確認した。プラグインの導入だけではこの本体修正は反映されない。

モデルの初期設定は不要。子エージェントは親のモデル・推論設定を継承する。変更する場合は `/pstack-codex:setup-pstack` を選ぶ。設定は `$CODEX_HOME/pstack-codex/models.json`（未指定時は `~/.codex/pstack-codex/models.json`）に保存し、各実行時に読む。Codex 全体の設定は変更しない。同一モデルの複数レビューは異なるモデル同士のレビューと区別して報告する。

## 更新

1. 新しい上流を別の検証用ディレクトリで確認する。`source.json` のコミット、上流バージョン、取り込むファイル全体の SHA-256、移植版のバージョンを更新する。依存分類と対応表も見直す。
2. 生成器のテスト、固定上流からの生成、実 Codex での読み込みを確認する。既存出力は上書きせず、新しい版のディレクトリへ生成する。
3. 使用中の pstack セッションを終えてから、以下を一つずつ実行する。同名マーケットプレイスを異なるパスへ直接再登録すると CLI が拒否するため、旧登録を先に削除する。

```sh
codex plugin remove pstack-codex@phlox-pstack
codex plugin marketplace remove phlox-pstack
codex plugin marketplace add /absolute/path/to/new-marketplace --json
codex plugin add pstack-codex@phlox-pstack --json
```

更新失敗時は保持してある旧版のパスを再登録して復旧する。手編集した生成物を変換器が消すことはない。専用のモデル設定はプラグインの再導入でも保持される。

## 削除

使用中の pstack セッションを終え、以下を実行する。

```sh
codex plugin remove pstack-codex@phlox-pstack
codex plugin marketplace remove phlox-pstack
```

保存したマーケットプレイスは削除されない。不要なら該当版のフォルダをゴミ箱へ移す。専用の `models.json` も自動削除しない。他のプラグインやスキルは対象外。

## 開発時の検査

生成器・設定検証の単体テストを実行する。

```sh
~/.agents/scripts/compact-test pstack-codex-generator \
  env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s integrations/pstack-codex/tests -v
```

生成物を変更せず照合するには `build.py` に `--check` を付ける。Bun の依存などを追加した検証用コピーは照合対象にしない。

実 Codex の読み込み確認ではインストール済みプラグインの絶対パスを指定する。

```sh
~/.agents/scripts/compact-test --full pstack-codex-discovery \
  env PYTHONDONTWRITEBYTECODE=1 python3 integrations/pstack-codex/tests/verify_discovery.py \
  --cwd "$PWD" --plugin /absolute/path/to/installed/pstack-codex \
  --record "$PWD/.verification/pstack-codex/discovery"
```

この検査は生成されたスキルの集合と実 `skills/list` の集合を照合し、エラー・欠損・無効なスキルがあれば失敗する。`verify_workflow.py` は隔離した `CODEX_HOME` と `.verification` 内の専用 clamp フィクスチャで修正・レビューを実行する。親の会話記録を参照できなかった実測があるため、子エージェント検証で `codex exec --ephemeral` は使用しない。

上流補助スクリプトは検証用コピーで `bun install --frozen-lockfile` 後、同梱 `package.json` の `test` と `typecheck` を実行する。テストは `compact-test` を経由し、`TMPDIR` を検証ディレクトリ配下へ設定する。
