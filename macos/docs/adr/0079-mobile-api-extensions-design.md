---
status: active
last-verified: 2026-07-11
---

# ADR 0079: モバイル向け Control API 拡張（interrupt/subagents/usage/images/差分取得）の設計判断

> **役割**: 凍結契約 [`docs/specs/mobile-api-extensions-contract.md`](../specs/mobile-api-extensions-contract.md) v1（1〜6）の**サーバー側実装で採った非自明な設計決定**を記録する。
> **書かないもの**: エンドポイントの現行 wire 仕様（→ [`docs/architecture/mobile-proxy.md`](../architecture/mobile-proxy.md)）／モバイル遠隔操作の土台判断（→ ADR 0074）。

## 文脈

Phlox-mobile のチャットパリティ（ターン停止・サブエージェント閲覧・コスト表示・画像添付送信・効率ポーリング）に必要な内部データ・機構はサーバー側に既存で、**wire 露出だけ**が欠けていた。両側は凍結契約 v1 を共有フィクスチャに並行開発した。実装中に非自明な判断が3点生じた。

## 決定

### 1. `/messages` 差分カーソルは「変更経路に非依存の内容ハッシュ再計算」で健全性を担保する

transcript は append 専用ではなく `appendOrReplace`（ストリーミング追記・置換）で既存項目が in-place 編集される。差分の健全性（＝クライアントが持つ prefix が変化していない保証）を、増分追跡の内部状態で持つのではなく、**カーソルに `(count, 先頭 count 項目の内容ハッシュ)` を埋め、差分要求のたびに現在の先頭 count 項目のハッシュをライブ再計算して照合**する方式にした（`Packages/SessionFeature/…/TranscriptDelta.swift`）。一致＝append のみ＝差分安全、不一致・縮小・不正カーソルは全量スナップショット（`snapshot: true`）へ倒す。

- **なぜ増分追跡（epoch カウンタ等）にしなかったか**: transcript の変更経路は6箇所以上（appendDelta/appendCommandExecution/appendOrReplace/setTranscript/restore/clear）あり、どれか1つで epoch 更新を取りこぼすと「編集を append と誤認して古い差分を配信」＝silent corruption を起こす。ライブ再計算は現在の実データだけを見るため、この失敗様式が構造的に存在しない。既存の変更経路には一切手を入れていない（外科的）。
- **代償**: 各ポーリングで O(n)（n=メッセージ数、実際は数百以下）のハッシュ計算。long-poll でも許容範囲。

### 2. 内容ハッシュは長さプレフィックス枠取り（区切り文字連結を採らない）

各フィールドを「8バイトのリトルエンディアン長＋本体」で枠取りして FNV-1a に混ぜる。区切り文字連結方式は、フィールド値自体が区切り文字を含むとバイト列がフィールド境界を跨いで同一化しうる（例: `command="a", output="b|c"` と `command="a|b", output="c"` が衝突）。これは独立レビュー（Codex ステージ2）が MUST として検出した実バグで、長さ枠取りは境界を長さで固定するため内容によらず衝突不可能。可変長配列は要素数もフィールド化、Optional は存在フラグで nil と空文字を弁別する。

### 3. transport body 上限は ControlServer だけ 16MiB へ拡張（HookServer は 256KiB 維持）

契約5 の画像添付は合計 8MiB、base64 で約 11MB の HTTP body になる。既定の `HTTPMessageParser.maxBodyLength`（256KiB）では受信できないため、`LocalHTTPConnection.receiveRequest` に `maxBodyLength` 注入口を追加し、**ControlServer の呼び出しだけ 16MiB**（`ControlServer.maxRequestBodyLength`）を渡す。`HTTPMessageParser` の既定値・HookServer 側は変更しない（Hook 経路の DoS 面を広げない）。

### 4. サブエージェント status の wire 値は `failed → "unknown"` 写像

契約 v1 の `status` は `running|completed|unknown` の3値で、domain の `SubAgentStatus.failed` に対応する wire 値が無い。4値化は wire 変更（両 run PM 合意が必要）のため、**契約適合の保守写像**（failed→unknown）を採った。v2 での `"failed"` 追加をモバイル側 PM へ提案する（未対応）。

## 結果

- 契約1〜6 を wire 変更・エスカレーションなしで実装。受け入れテスト＋統合 E2E green。
- 独立レビューが差分カーソルの MUST を捕捉し、根本修正（長さ枠取り）に到達（generator-verifier ギャップの実例）。
- 未解決: 契約 v2 での `SubAgentStatus.failed` 追加提案、モバイル送信経路の composer 添付分離（別 run 推奨）。
