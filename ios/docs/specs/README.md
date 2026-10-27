---
status: active        # active | completed | superseded | archived
last-verified: 2026-10-17
---

# specs/

**役割（ここにしか書かない）**: 要件・仕様（FR/NFR・受け入れ基準・用語/ドメイン）

**書かないもの**: 設計の詳細・手順（→ architecture/・guides/）

**Diátaxis**: Reference

**代表(入口)ファイル**: `specs/requirements.md`（固定名）

**命名**: 小文字 kebab-case・ASCII・`.md`（索引のみ `README.md`）。順序ありは `NNNN-kebab.md`。

## 配置例
- `specs/requirements.md`
- `specs/glossary.md`
- `specs/acceptance-criteria.md`

## 現在あるファイル
- `specs/session-activity-parity.md` … Macと統一する状態表示・履歴操作・使用量・新規チャットの承認仕様
- `specs/mobile-api-extensions-contract.md` … Phlox ⇔ Phlox-mobile の Control API 拡張契約（凍結版 v1）
- `specs/redesign-2026-10.md` … iOS アプリ再設計（2026-10）の画面ごとの要件・受け入れ基準・見本の食い違いの決定・未決の論点（正本）
- `specs/ui-feature-inventory.md` … 再設計前の UI 機能の棚卸し（superseded。見本が節番号で引く）
- `specs/ClaudeDesign/` … 再設計の見本（Claude Design の盤面 248 枚。外枠の盤面は親を props で呼ぶ）
