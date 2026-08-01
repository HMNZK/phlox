---
status: accepted
last-verified: 2026-08-01
---

# ADR 0152: codex app-server の未対応 server request を承認バナーに化けさせない

> **このファイルの役割**: `ChatApprovalBroker` が未知の server request を「権限承認」として
> 扱っていたのをやめ、JSON-RPC のエラー（`-32601 Method not found`）で返すことにした決定。
> **書かないもの**: `item/tool/requestUserInput` を質問カードとして実装した決定（→ [ADR 0153](0153-codex-request-user-input-as-question-card.md)）、
> フルアクセス設定の適用先（→ [ADR 0154](0154-full-access-setting-applies-to-app-server.md)）。

## 文脈

「Codex をフルアクセスにしているのに `Unsupported server request: item/tool/requestUserInput`
の承認プロンプトが出る」という不具合報告から調査した。

codex app-server は client 側へ 11 種の server request を送る。Phlox が実装していたのは
コマンド実行承認・パッチ適用承認・ログイン系の 3 種だけで、残りは `ChatApprovalBroker` の
`makeApproval` が **`.unknown` をまとめて `kind: .permissions` の承認へ写像**していた。
その結果:

- 承認ではない要求（質問・情報提供・進捗通知）まで **承認バナーとして画面に出る**。
- ユーザーが Accept を押すと `{"permissions": null, "scope": "turn"}` という、
  その method が期待していない形の応答が wire へ返る。
- 承認ではないので `approvalPolicy` の支配下になく、**フルアクセスにしても抑止できない**。
  （報告された「フルアクセスなのに承認が出る」の直接の原因はここ。）

## 決定

未対応の server request は承認に化けさせず、**JSON-RPC のエラーで返す**。
`ChatApprovalBroker` は `.unknown` を受けたら `unsupportedServerRequest` を throw し、
`JSONRPCClient` がそれを `-32601 Method not found` として応答する。

## 結果

- 未対応の要求は画面に何も出さず、codex 側が「この client は未対応」と判定できる形で返る。
  ユーザーに意味のない承認を押させない。
- 承認バナーに出るのは**本当に承認である 3 種だけ**になり、`approvalPolicy` の設定と
  画面に出る承認が一致する（ADR 0154 の前提でもある）。
- 未対応のまま残る 8 種は、必要になった時点で個別に実装する。今回そのうち
  `item/tool/requestUserInput` だけを実装した（→ ADR 0153）。
- 代償: 未対応 method は「静かに失敗する」ため、ユーザーには何も起きていないように見える。
  可視化（診断ログへの記録）は今回のスコープに含めていない。
