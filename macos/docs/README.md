---
status: active        # active | completed | superseded | archived
last-verified: 2026-06-10
---

# Phlox ドキュメント管理ルール

> **このファイルの役割**: docs 配下の構造と「どこに何を書くか」を定義する索引。
> **書かないもの**: 個別機能の仕様・設計・手順（各フォルダへ）。

ドキュメントは **「読み手の意図」（Diátaxis）** で分類する。迷ったら
「半年後の自分が何を知りたくて grep するか」で置き場所を決める。

## フォルダ構成と役割
| フォルダ | ここにしか書かない | 書かないもの | Diátaxis |
|---|---|---|---|
| `specs/` | 要件・仕様（FR/NFR・受け入れ基準・用語/ドメイン） | 設計の詳細・手順（→ architecture/・guides/） | Reference |
| `architecture/` | 現行アーキテクチャ（構成・データモデル・I/F・コンポーネント）＝**今こう動いている** | なぜそうしたか（→ adr/） | Explanation / Reference |
| `adr/` | 決定記録（なぜ A でなく B か・**不変・追記専用**）`NNNN-xxx.md` | 現状仕様（→ architecture/） | Explanation |
| `guides/` | 開発手順・オンボーディング（環境構築・新機能の足し方） | 運用 Runbook（→ operations/） | Tutorial / How-to |
| `operations/` | 運用 Runbook（デプロイ/マイグレーション/ロールバック/障害対応） | 開発オンボーディング（→ guides/） | How-to |
| `delivery/` | フェーズ作業ログ・引き継ぎ・変更履歴（過去の経緯・状態スナップショット） | 恒久仕様（→ specs/・architecture/） | Status |

## ファイル命名規則（統一）
- **小文字 kebab-case・ASCII・拡張子 `.md`**（例: `data-model.md`）。スペース・大文字・日本語はファイル名に使わない（リンク/URL/OS 間で壊れにくくするため）。
- 例外: 各フォルダの索引は `README.md`（大文字慣例）。
- **順序が意味を持つものは連番を前置**: `NNNN-kebab.md`（4 桁ゼロ詰め）。例: `adr/0001-choose-datastore.md`、`delivery/0001-phase1-worklog.md`。
- 1 ファイル = 1 トピック。複数語は短い名詞句で。

### 各フォルダの代表(入口)ファイル（固定名）
| フォルダ | 代表ファイル |
|---|---|
| `specs/` | `specs/requirements.md` |
| `architecture/` | `architecture/overview.md` |
| `guides/` | `guides/getting-started.md` |
| `operations/` | `operations/runbook.md` |

## 配置の決め方（クイック判定）
- 「これは何を満たすべき？」→ `specs/`
- 「今どう動いている？」→ `architecture/`
- 「なぜこの方式にした？」→ `adr/`
- 「どう環境を作る/開発する？」→ `guides/`
- 「どう運用/デプロイ/復旧する？」→ `operations/`
- 「このフェーズで何をやった？」→ `delivery/`

## 共通ルール（腐敗防止）
- 全主要ドキュメントの冒頭に **frontmatter** を付ける：
  ```yaml
  ---
  status: active        # active | completed | superseded | archived
  last-verified: YYYY-MM-DD
  ---
  ```
- 物理移動より **status 書き換え** を優先（参照リンクの腐敗を防ぐ）。
- `last-verified` が 3 ヶ月以上古いものは内容を再確認する。
- ADR は **追記専用**。決定を覆す時は新 ADR を起こし、旧 ADR を `superseded` にしてリンクする。
