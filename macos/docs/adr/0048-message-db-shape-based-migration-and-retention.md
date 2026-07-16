---
status: active
last-verified: 2026-07-08
---

# ADR 0048: メッセージ DB の migration はスキーマ形状で判定し、30 日保持ポリシーを導入する

> **このファイルの役割**: 2026-07 監査対応で SQLiteMessageStore の migration 判定基準と保持ポリシーを決めた理由・棄却案・帰結。
> **書かないもの**: 現行のスキーマ・開店手順（→ `architecture/app-data-storage-and-flavor.md` とコード）、run の経緯（→ `delivery/0025-...-worklog.md`）。

## 文脈

- 監査所見: ① `thread()` の `in_reply_to` に索引がなく全表スキャン、②【推測・狭窓】`user_version=0` かつ
  旧テーブル既存の DB で migration が永久スキップされ `record()` が黙って失敗し続ける、③ 保持ポリシーが
  皆無で DB が無制限に肥大する。②は受け入れテストで再現に成功し「推測」を事実へ昇格した。
- 差し戻しレビュー（ステージ2）が**第4の事前状態**を検出: 旧実装の狭窓バグを一度踏んだ DB は
  「v1 形テーブル（in_reply_to 列なし）のまま user_version=2 確定」で実在しうる。version 条件だけで
  migration を判定すると、この DB では列補修がスキップされ、索引作成が "no such column" で throw
  → init 失敗 → アプリ起動不能という**旧バグより悪い回帰**になる。

## 決定

1. **migration の実行判定は `user_version`（独立して壊れうる代理指標）ではなく、スキーマ形状
   （列の有無・`PRAGMA table_info`）で行う**。冪等な `migrateToSchemaVersion2` を version 条件の外で
   常時実行し、開店手順を「列補修 → 索引作成（IF NOT EXISTS）→ user_version 確定（version<2 時のみ・
   移行完了後）→ 保持削除」の固定順にする。途中クラッシュしても次回開店の冪等再走で自己修復する。
2. **保持ポリシー: `created_at` が 30 日超の行を開店時に DELETE**（ちょうど 30 日は残す・strict `<`）。
   削除は best-effort（失敗はログのみで開店を妨げない）。保持日数は `init(databaseURL:retentionDays:)` の
   デフォルト付き引数（既定 30）。
3. `PRAGMA synchronous=NORMAL` を WAL 設定直後に追加（WAL 前提で安全な fsync 削減）。

## 棄却案

- **version ベース判定の維持**（初回実装）: 第4状態で起動不能の回帰を生むためレビューで棄却。
- **prepared statement キャッシュ**: record 頻度に対して効果が小さく複雑化に見合わないため見送り。
- **VACUUM / 件数上限**: 30 日 TTL で肥大は抑止できるため今回は導入しない。
- **保持 90 日 / 無期限**: ユーザー裁定で 30 日を採用（ゲート①）。

## 結果

- 4 つの事前状態（新規 / v1 / 狭窓 v0 / 旧狭窓後の v2）すべてで開店後に列と
  `idx_messages_in_reply_to` が存在し、record→thread が機能する（受け入れテスト
  `SQLiteMessageStoreAuditAcceptanceTests` の 5 本で固定）。
- 開店ごとに `PRAGMA table_info` が 1 回余分に走るが、コストは無視できる。
- `synchronous=NORMAL` の値自体は接続ローカルで外部観測不可のため自動アサートなし（コード検査で担保）。
