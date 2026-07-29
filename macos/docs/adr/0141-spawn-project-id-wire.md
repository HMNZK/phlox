---
status: accepted
last-verified: 2026-07-30
---

# ADR 0141: spawn の projectId をワイヤに載せ、未知のプロジェクトは 422 で拒否する

> **このファイルの役割**: モバイル発のセッションをどのプロジェクトに所属させるかを、どう伝え・どう失敗させるかの決定理由。
> **書かないもの**: 現行のエンドポイント表・配線（→ [architecture/mobile-proxy.md](../architecture/mobile-proxy.md)）、
> ワイヤの詳細な形（→ [ios/docs/specs/mobile-api-extensions-contract.md](../../../ios/docs/specs/mobile-api-extensions-contract.md) §7.1）、
> 一覧側の project 付与（→ ADR 0125 系 / wave-2 契約 §7.2）。

## 文脈

iOS でプロジェクトを選んで作ったセッションが、macOS サイドバーで必ず **「その他」** に落ちていた。
「その他」は `DashboardViewModel.unassignedSessionNodes`＝`projectID == nil` の一点で決まり、
CWD（`workingDirectory`）はグルーピングに一切関与しない。

原因は 2 段の欠落だった。

1. iOS は選んだプロジェクトをローカル表示にしか使っておらず、`POST /sessions` の body には
   `kind`/`backend`/`model` しか載せていなかった。
2. macOS 側の Control API spawn 経路（`Action.spawn` → `ControlActionHandler.handleSpawn` →
   `spawnNewSessionFromControlAPI`）に **projectID を渡す引数が存在せず**、
   `spawnNewSessionImpl(projectID:)` を常に既定 nil で呼んでいた。

親からの継承も効かない。モバイルの要求元は実在セッションではないので `SessionOriginPolicy.origin` は
`parentSessionID: nil` を返し、`resolveProjectID(explicit: nil, parentSessionID: nil)` は nil になる。
つまり救済経路が無く、100% 再現する。

受け皿（`spawnNewSessionImpl(projectID:)` と、そこから CWD を導く `resolvedWorkingDirectoryPath`）は
既に存在していた。欠けていたのは配線だけである。

## 決定

**`POST /sessions` に任意フィールド `projectId`（ProjectID の UUID 文字列）を追加し、
`ControlRequest.Action.spawn` の associated value として型で運ぶ。**

- **`ControlSpawnContext` のようなサーバ側の可変一時状態に載せない。** role / model は
  `pendingSpawnRole` / `pendingSpawnModel` というリクエスト外の可変状態で受け渡しており、その結果
  ControlServer のテストは並列実行で相互に踏み合って落ちる（`.claude/verify.sh` が `--no-parallel` を
  使っている理由）。同じ轍を踏まないため、spawn 要求の一部は要求オブジェクトに置く。
  代償として `ControlServer` ↔ `AppBootstrap` ↔ `macos/App` を跨ぐシグネチャ変更になるが、
  `ControlActionDashboard` に既定実装が無いので、追随漏れはコンパイルエラーとして必ず出る。
- **エラーは形式と存在で分ける**: UUID として parse できない（空文字含む）は **パース層で 400**
  `{"error":"invalid projectId"}`、UUID だが該当プロジェクトが無いは **ハンドラ層で 422**
  `{"error":"unknown projectId"}`。既存の `invalid workingDirectory`（400）と同じ関所の考え方に揃える。
- **未知の projectId は黙って未所属で作らず、セッションを作る前に拒否する。**
- **`projectId` と `workingDirectory` が同時に来たら `workingDirectory` を優先**する
  （現行の `workingDirectoryOverride ?? project 由来` を維持）。`projectId` は所属の決定にのみ効く。
- **公開シグネチャに既定値 `= nil` を置かない**。呼び出し元には nil を明示させる。

## 棄却案

- **黙って無視して未所属で作る**（`model` の既存仕様と同型）: 今回のバグはまさに「黙って未所属になる」
  ことで気づかれずに残った。同じ失敗の形を仕様として固定することになる。
- **400 で拒否する**: iOS は **422 のときだけ** `PhloxError.spawnRejected(reason:)` としてサーバの
  `error` 文字列を画面に出す（`PhloxAPIClient.mapStatus`）。400 は汎用エラーに丸められ理由が埋もれる。
- **`workingDirectory` からプロジェクトを逆引きする**: 同じディレクトリを指す複数プロジェクトや、
  プロジェクト外の CWD を明示した spawn で破綻する。所属はパスではなく ID で決めるべきである。
- **`ControlSpawnContext` に projectId を足す**（型を変えずに済む）: 上記のとおり、既存の flaky の
  発生源そのものを拡張することになる。リクエストとの対応も暗黙のままになる。
- **`spawnNewSessionFromControlAPI` に `projectID: ProjectID? = nil` の既定値を置く**（呼び出し元の
  修正を省ける）: 「Control API 経由で projectID が黙って nil に落ちる」＝**今回直したバグと同型の穴**を
  コンパイラから隠す。実際、独立レビューはこの既定値のせいで 8 箇所の呼び出し元が未更新のまま
  通っていることを検出した。

## 結果

- iOS で選んだプロジェクトの配下にセッションが作られ、CWD もそのプロジェクトのディレクトリになる。
  **モバイル発セッションの CWD は既定値からプロジェクトのディレクトリへ変わる**（意図した改善だが可視の変化）。
- `projectId` を送らない既存経路（CLI・loopflow・PTY spawn）は完全に無変更。
- **新 iOS ＋ 旧 macOS の組み合わせでは、旧 macOS が未知フィールドを無視して従来どおり「その他」に作る**
  （サイレント劣化）。能力ネゴシエーション API は追加しないと決めた（両アプリを同じリポジトリから
  並行リリースするため）。
- iOS 側は「本物の `projectId` を持つグループ」からの作成でのみ送る。`ProjectGroup.id` は
  `projectId ?? projectName` のフォールバックを含むため、無検査で送るとプロジェクト名を UUID として
  送ってしまう（→ 400）。`ProjectGroup.projectID` を別に持たせて区別する。
- 未解決（別 issue 候補）: 起動直後、`ControlActionHandler.dashboard` の結線が
  `DashboardViewModel.start()`（projects のロード）より先に走るため、その窓に届いた正しい projectId が
  一時的に 422 になりうる（未実測）。本変更前は同じ窓で「黙って未所属セッションが作られる」＝
  今回直したバグそのものが起きていたので、退行ではない。
