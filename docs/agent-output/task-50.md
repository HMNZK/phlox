---
task: task-50
status: completed
---

## 詰まった点

- `composerModeOptions` 内で選択肢生成をヘルパにまとめると、配線検査の `ComposerModeOption(value: "…" | nil)` 走査が項目集合・順序の変化と判定した。リテラル付きの `ComposerModeOption` 初期化へ戻して解消した。
- クロージャ内に `let` があると Swift が暗黙 return をやめるため、Codex プロフィール map は明示 `return` が必要だった。
- `UIWording.launchPermission` の `custom` 枝で `let` を挟むと `return switch` の式にならずコンパイル RED になった。説明文をインラインした。
- Codex プロフィール未選択の選択中ラベルから `UIWording.text(.approvalLabel)` を外すと、task-48 配線が `ComposerSettingsControlsView が UIWording.Key.approvalLabel を参照していない` で落ちた。未選択時だけ task-48 のキーを残し、値があるときは `.codexProfile` 正本へ接続した。

## できた風だが実は未完

- 契約の PM 目視ゲート（設定 520×640、エージェント管理 4 画面、日英、閲覧前後の非変更）は実装担当の範囲外。自動検査と App ビルドまで。
- 実エージェント起動・実効権限の確認は契約どおり未実施。説明は Phlox が指定する起動条件であり、バックエンド適用結果までは確認していない。
- Codex の `personality` 等、権限以外の列挙キーの選択肢表示は原文のまま（未知値フォールバック）。権限 2 キーだけを対応表へ接続している。

## 置いた前提・仮定

- `UIWording.isEnglish` / `primaryLanguage` は `UIWording.swift` 側で private のため、同じ規則（`-` / `_` の前を大小無視、`en` のみ英語、他は日本語）を `UIWording+Permissions.swift` に複製した。`UIWording.swift` は変更していない。
- Claude 権限モードの `nil` は未知値（title は空文字、説明は未確認文）とし、unset にも bypass にも倒していない。
- Codex 設定画面の権限以外の Picker は、配線が `Text(option)` を拒否するため、`.codexApprovalPolicy` の未知値経路で原文 title を出している。保存値・tag・options(current:) は変えていない。
- 内部構造用の新規テストは置いていない。受け入れは凍結 Swift Testing と Ruby 配線に任せた。

## 契約からの逸脱

なし。許可パス外・凍結テスト・配線検査・台帳・契約ファイルは変更していない。task-48 の一般文言接続（`UIWording.text` と locale 伝播）は共有ファイル上で維持した。

## レビュー重点

- Claude 権限モード、Codex 承認方針／実行制限／プロフィール、Cursor 承認方式／サンドボックス／動作モードが、同じ raw value でも kind で分かれているか。
- 通常・省略メニューと選択中ラベル、設定 Toggle の ON/OFF 同時描画、管理画面の対象行だけが正本へ接続しているか。
- `BypassToggleRow` の `AppStorage(wrappedValue: true, descriptor.bypassKey)`、tag、Plan 末尾・排他、成功通知経路が基準 blob から変わっていないか。
- `never` / `dontAsk` / bypass を「すべて許可」やサンドボックス解除と書いていないか。カスタム行が「フルアクセス」になっていないか。

## 検証原文

```
$ ruby .claude/scripts/task50-wiring.rb --selftest
task50-wiring --selftest: OK

$ env TASK50_BASELINE=e3dd2fb ruby .claude/scripts/task50-wiring.rb
task50-wiring: OK

$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK

$ env TASK48_BASELINE=91cdbe9 ruby .claude/scripts/task48-wiring.rb
task48-wiring: OK

$ (cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t50-ds swift test)
✔ Test run with 187 tests in 32 suites passed after 0.097 seconds.

$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t50-sf swift build)
t50-sf: OK（要約未対応）

$ cd macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t50-build -destination platform=macOS build 2>&1 | tail -3
note: Run script build phase 'Re-register Debug app with LaunchServices (Dock display name)' will be run during every build because the option to run the script phase "Based on dependency analysis" is unchecked. (in target 'Phlox' from project 'Phlox')
** BUILD SUCCEEDED **

$ git diff --check
```

=== REPORT COMPLETE ===
