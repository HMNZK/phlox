---
task: task-50
status: completed
---

## 詰まった点

- `composerModeOptions` 内で選択肢生成をヘルパにまとめると、配線検査の `ComposerModeOption(value: "…" | nil)` 走査が項目集合・順序の変化と判定した。リテラル付きの `ComposerModeOption` 初期化へ戻して解消した。
- クロージャ内に `let` があると Swift が暗黙 return をやめるため、Codex プロフィール map は明示 `return` が必要だった。
- `UIWording.launchPermission` の `custom` 枝で `let` を挟むと `return switch` の式にならずコンパイル RED になった。説明文をインラインした。
- Codex プロフィール未選択の選択中ラベルから `UIWording.text(.approvalLabel)` を外すと、task-48 配線が `ComposerSettingsControlsView が UIWording.Key.approvalLabel を参照していない` で落ちた。未選択時だけ task-48 のキーを残し、値があるときは `.codexProfile` 正本へ接続した。
- 差し戻し r1: 権限以外の列挙 Picker を別関数に分けると `setValue` 呼び出しが基準より増えて setter 比較が NG になる。同じ `choiceControl` の `kind == nil` 枝で `Text(option)` を出す形にまとめた。

## できた風だが実は未完

- 契約の PM 目視ゲート（設定 520×640、エージェント管理 4 画面、日英、閲覧前後の非変更）は実装担当の範囲外。自動検査と App ビルドまで。
- 実エージェント起動・実効権限の確認は契約どおり未実施。説明は Phlox が指定する起動条件であり、バックエンド適用結果までは確認していない。
- `TASK50_BASELINE` の rb 自身不一致は再凍結前の想定内。製品配線の NG は無い。

## 置いた前提・仮定

- `UIWording.isEnglish` / `primaryLanguage` は `UIWording.swift` 側で private のため、同じ規則（`-` / `_` の前を大小無視、`en` のみ英語、他は日本語）を `UIWording+Permissions.swift` に複製した。`UIWording.swift` は変更していない。
- Claude 権限モードの `nil` は未知値（title は空文字、説明は未確認文）とし、unset にも bypass にも倒していない。
- 起動 Toggle の OFF/ON 識別は View 側の `OFF:` / `ON:` 見出しで付けた。正本の説明文は凍結テストのリテラルのまま。
- 権限ペインの subtitle は導入説明の先頭一文（`。` または `. ` まで）。全文はスクロール本文先頭の `Text(intro.explanation)`。
- 内部構造用の新規テストは置いていない。受け入れは凍結 Swift Testing と Ruby 配線に任せた。

## 契約からの逸脱

なし。許可パス外・凍結テスト・台帳・契約ファイルは変更していない。配線検査の修理は PM 承認のハーネス範囲。task-48 の一般文言接続は共有ファイル上で維持した。

## レビュー重点

- Codex の personality 等、権限以外の列挙キーが承認方針正本へ流れず、原文 `Text(option)` になっているか。
- 設定 Toggle で OFF 説明と ON 説明が状態名付きで同時に読めるか。凍結テストの説明リテラルは壊していないか。
- Claude / Cursor 権限ペインの subtitle が短い一文で、導入説明の全文が本文先頭にあるか（`AgentConsoleWindowView` は未変更）。
- `BypassToggleRow` の `AppStorage(wrappedValue: true, descriptor.bypassKey)`、tag、Plan 末尾・排他、成功通知経路と `setValue(newValue, …)` が基準 blob から変わっていないか。

## 検証原文

```
$ ruby .claude/scripts/task50-wiring.rb --selftest
task50-wiring --selftest: OK

$ env TASK50_BASELINE=e3dd2fb ruby .claude/scripts/task50-wiring.rb
task50-wiring: NG 基準時点のrb 自身が現在と同一ではない

$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK

$ env TASK48_BASELINE=91cdbe9 ruby .claude/scripts/task48-wiring.rb
task48-wiring: OK

$ (cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t50-ds swift test)
✔ Test run with 187 tests in 32 suites passed after 0.226 seconds.

$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t50-sf swift build)
t50-sf: OK（要約未対応）

$ cd macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t50-build -destination platform=macOS build 2>&1 | tail -3
** BUILD SUCCEEDED **

$ git diff --check
```

=== REPORT COMPLETE ===
