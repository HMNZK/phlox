---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-08
---

# guides/

**役割（ここにしか書かない）**: 開発手順・オンボーディング（環境構築・新機能の足し方）

**書かないもの**: 運用 Runbook（→ operations/）

**Diátaxis**: Tutorial / How-to

**命名**: 小文字 kebab-case・ASCII・`.md`（索引のみ `README.md`）。順序ありは `NNNN-kebab.md`。

## 現在あるファイル（固定名の入口ファイルは未作成。以下が現行の入口）
- `guides/running-release-and-debug-together.md` — Release/Debug 版の同時併用手順（ADR 0034）
- `guides/vision-testing-desktop-ui.md` — デスクトップ UI の手動ビジョン検証（非侵襲キャプチャ・動的状態の再現・停止赤枠。自動テストは `specs/e2e-test-design.md`）
