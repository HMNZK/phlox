---
status: active
last-verified: 2026-10-25
---

# スマホのスキル候補

恒久仕様は [スマホのスキル候補](../../../macos/docs/specs/mobile-skill-suggestions.md) を参照。

## 解決したい問題
スマホでも `/` を入力して、接続先Macのエージェントとプロジェクトに合うスキルを選べるようにする。

## 現状（調査の根拠つき）
`DSInputBar` はカーソル位置をUTF16で保持するが候補表示はない。Macの `ComposerSuggestionSources` に候補生成があり、既存APIにはスキル取得がない。

## 成功基準（検証可能な形で）
新規・既存チャットで `/` と部分入力から候補を表示する。選択時は対象トークンのみ置換し、Codexは `$name` と識別情報、他は `/name` を送る。Unicode・本文保持・候補の取得失敗・プロジェクト切り替えを単体テストで確認し、iOSビルドと画面外描画で候補UIを検証する。

## 仮定 / 未知
`/poteto-mode` は入力例と解釈する。該当するローカルスキルは見つからない。

## 制約（技術・運用・期限）
既存の未コミット変更を分離したworktreeで作業する。XCUITestは実行しない。古いMacの404は候補非対応として扱う。

## スコープ外
ファイル候補、組み込みコマンド候補、実機配布。

## 既知リスク
機能の利用にはMac側の更新も必要。Codexの新規チャットは起動後に候補を再取得して現在の識別情報を送る。

## 実行記録
- iOSパッケージ: XCTest 402件、Swift Testing 676件が成功。
- iOSシミュレータ: `SkillSuggestionRenderTests` 2件が成功。375pt幅でライト／ダークと文字サイズ最大を描画し、AXの候補選択で本文・カーソル・スキル識別情報の反映を確認した。XCUITestは使用していない。
- Mac関連5パッケージ: AgentDomain 577件、ControlServer 172件、DashboardFeature 2,209件＋実Git検査41件、AppBootstrap 211件が成功。DashboardFeatureには既存の既知問題1件が含まれる。
- SessionFeature 1,298件の検査では、変更対象外の `ComposerSettingPopoverTests.clickingOutsideClosesNativePopover(legacy:)` の2ケースが失敗。単独実行でも同じ失敗を確認した。期待値・テスト・プロダクトのポップアップ実装は変更していない。イベント配送の試行は完走を確認できず、変更を戻した。
- 旧常駐プロセスへの能力確認追加後、SessionRuntime関連32件が成功。
- Macアプリ: Debugのarm64/x86_64ビルドが成功。標準ad-hoc署名を維持し、起動はしていない。既存のSendable・actor isolation・非推奨API等の警告が残る。
- 実機間の通信は未検証。

検証ログと画面は、このworktreeの `.verification/mobile-skills-20261025/` および `.verification/mobile-skill-suggestions-macos/` に保存した。
