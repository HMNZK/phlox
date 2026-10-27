---
status: active
last-verified: 2026-10-25
---

# スマホのスキル候補

## 解決したい問題
スマホの新規・既存チャットで `/` を入力しても、Mac にあるスキルを選べない。

## 設計
- Mac の既存スキル探索と Codex の `skills/list` を再利用する。
- `GET /agents/{kind}/skills?projectID=...&workspace=...` は登録済みプロジェクトのスキルを返す。プロジェクト未指定時はホームを使う。
- `GET /sessions/{id}/skills` はそのセッションの候補を返す。
- 応答は `{skills:[{name,description,path,runtimeFingerprint?}]}`。
- Codex は選択時に `$name` を挿入し、`POST /send` の任意 `skill` に name/path/runtimeFingerprint を渡す。Mac は現在の候補とファイルの一致を確認してから既存の native skill 送信を使う。
- スマホの選択は native input に直接渡し、デスクトップのスキル選択・再選択要求を変更しない。送信待ちの間にデスクトップで選び直した場合もその選択を保持する。
- Claude/Cursor は `/name` のテキストとして送る。
- 古い Mac の 404 は iOS 側で候補非対応として扱う。
- 常駐プロセスのprotocol versionは1を保ち、handshakeの任意 `supportsControlSkills` で対応能力を確認する。未対応の相手へのスキル付き送信は拒否し、通常の送信は従来の互換性を保つ。

## HTTP契約
既存の認証を適用する。`projectID` は登録済みUUID、`workspace` はプロジェクト名とする。両方ある場合は `projectID` を優先し、任意のディレクトリ指定は受け付けない。

候補取得は成功時200、対象セッション・プロジェクトの不在時404、Codexの候補更新失敗時503。`POST /send` の `skill` は省略可能で、指定する場合はCodexの `$name` トークンと有効な現在の識別情報が必要。変更済み・無効なスキルは400で拒否する。

## 検証
候補取得・プロジェクト指定の転送・送信時の無効な skill の拒否を単体テストで確認する。共有選択の保持と、projection から owner を経由する native input 送信を含め、標準パッケージ入口で実行する。iOS の候補選択と画面描画は iOS 側で検証する。

## 制約
XCUITest は実行しない。既存の未コミット変更を巻き戻さず、`.env*` に触れない。
