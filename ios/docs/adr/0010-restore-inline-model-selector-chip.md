---
status: active
last-verified: 2026-07-15
---

# ADR 0010: 入力欄内モデルセレクタチップを復活させ、右上メニューと併存させる

> **このファイルの役割**: wave-3（コミット `380a14d`）で入力欄からモデル選択チップを撤去し右上メニューへ集約した判断を、wave-4 で一部見直し、入力欄内チップを再導入した判断を記録する。wave-3 のこの決定は `ios/docs/adr/` に ADR として残されていなかったため、本 ADR が唯一の記録になる。
> **書かないもの**: モデル選択 API のワイヤ形状（→ [specs/mobile-api-extensions-contract.md](../specs/mobile-api-extensions-contract.md) §6/§7.3）。現行の入力バー構成（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

wave-2（task-6、コミット `cecc2b8`）でセッション詳細の入力バー付近にモデル選択チップ（`providesModelSelectorChip = true`）を追加した。wave-3（task-2、コミット `380a14d`「セッション詳細の半透明トップバー・右上メニュー・入力欄をタブバー上へ・チップ撤去」）でこのチップを撤去し `providesModelSelectorChip = false` へ反転、モデル変更は右上メニューの1導線に一本化した。

wave-4 でユーザーから「入力欄内にモデルセレクタチップを戻す」要望があった。単純に wave-3 の反転を取り消すのではなく、`DSInputBar` 自体の構造（キーボード上「完了」ツールバー撤去、`.scrollDismissesKeyboard` への置き換え。詳細は本 run の別変更）と合わせて実装する必要があった。

## 決定

- `SessionDetailView.providesModelSelectorChip` を `false → true` に反転（コミット `da0104d`/`671db07` task-4）。
- `DSInputBar` に **`modelSelector: () -> some View` という差し込みスロット**（`@ViewBuilder` 引数、既定 `EmptyView()`）を新設し、`inputFieldColumn`（テキストフィールドの下）に配置。旧チップ実装（wave-2）は `SessionDetailView` 側に直接ハードコードされていたが、`DSInputBar` の再利用性を保つため汎用スロットとして切り出した。
- チップの表示条件・表示名解決は `SessionDetailViewModel`（`showsModelSelectorChip`/`selectedModelDisplayName`）が担い、タップで開くシート（`isModelSheetPresented` → `ModelPickerSheet`）は **右上メニューの「モデルを変更」と共有**する。入力欄チップと右上メニューは同じ状態・同じシートへの**2つの入口**として併存させ、どちらか一方に一本化しない。
- 旧凍結テスト `Wave3SessionDetailChromeAcceptanceTests.modelSelectorChipRemovedFromInputBar`（`== false` 主張）・`Wave3SessionDetailChromeWhiteboxTests.inputBarNoLongerDrawsModelSelectorChip`（チップ不在ソース主張）は wave-4 と直接矛盾するため、`modelSelectorChipRestoredInInputBar`（`== true`）・`inputBarDrawsModelSelectorChipAndScrollDismissesKeyboard`（`providesModelSelectorChip = true` かつ `private func modelSelectorChip` かつ `.scrollDismissesKeyboard` の存在を主張）へ反転した（PM 裁定、decision-log.md task-4 波及テスト処理）。wave-3 が同時に導入したトップバー／メニュー／rename／タブバー契約は無改変で維持。

## 結果

- モデル変更の導線が「入力欄チップ」「右上メニュー」の2箇所になった（wave-3 は右上メニュー1箇所への統合を意図していたが、その意図は本 ADR により明示的に上書きされる）。
- `DSInputBar` の `modelSelector` スロットは `SessionDetailView` 以外の呼び出し元（既定 `EmptyView()`）には影響しない後方互換な拡張。

## 却下した代替案

- **wave-3 のチップ撤去をそのまま取り消す（右上メニューを廃止し入力欄チップのみに戻す）**: wave-3 で右上メニューへ集約した設計（rename・タブバー等の他クローム要素との統一 UI）を壊すため却下。2導線併存を選んだ。
- **`DSInputBar` にモデルセレクタ専用の型を直接持たせる**（`SessionDetailViewModel.ModelPickerEntry` 依存）: `DesignSystemIOS` パッケージが `Features` 層のドメイン型に依存することになり層構造（`DesignSystemIOS` は UI 部品のみ・`Features` 非依存）が崩れるため、汎用 `@ViewBuilder` スロットで呼び出し元に組み立てを委ねる形にした。
