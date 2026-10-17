---
status: active
last-verified: 2026-10-17
---

# スキル候補のディレクトリリンク修正

## 問題と確認済みの原因

新規チャットでCodexを選び `/` を入力しても組込コマンドしか表示されず、既存スキル名を入力すると候補が消える。会話開始後のCodex `skills/list` 経路では候補が表示される。

この環境の `~/.claude/skills` は `~/.agents/skills` へのシンボリックリンク。通常候補の `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` は末尾がリンクのディレクトリURLで `NSPOSIXErrorDomain Code=20 / Not a directory` を返し、`try? ... ?? []` により候補が空になる。リンクを解決したURLでは75フォルダを取得できた（2026-10-17、修正前Debug版の画面操作とFoundationの診断で確認）。

## 修正方針

通常候補のスキル・カスタムコマンドのディレクトリを、列挙前に `resolvingSymlinksInPath()` で解決する。ホーム・プロジェクトそれぞれのルートリンクを扱い、同じ候補を複数経路で発見した場合は既存の重複排除を維持する。Codexの会話開始後のネイティブ候補経路は既存実装を使う。

## 成功基準

- ホームとプロジェクトの `.claude/skills` / `.claude/commands` がリンクの場合も、リンク先の候補と説明を取得できることを回帰テストで確認する。
- 通常ディレクトリの候補、既存の検索・重複排除・Codex候補経路を、設定済みの `macos/scripts/verify-codex-chat-parity.sh` で確認する。
- 専用保存先のDebug版の新規Codexチャットで `/accessibility` の候補表示を画面で確認する。リンク先のユーザーファイルは変更しない。

## 検証状況

実装済み。通常候補のディレクトリ列挙2か所でリンク先を解決する。作業ブランチは `feature/fix-skill-directory-symlinks`。

### 合格した確認

- `ComposerLinkedDirectoryTests` を追加。ホーム／プロジェクト × スキル／コマンドの4ケースは修正前に候補なしで失敗し、修正後と最終ソース復元後に合格（Swift Testing上は1テスト・4ケース）。説明と挿入文字列・由来も確認する。
- 正本 `macos/scripts/verify-codex-chat-parity.sh` はexit 0。CodexAppServerKit全suite 100件、SessionFeature全suite 1200件、Codex到達性の限定実行3件、DashboardのCodexルート限定実行2件が合格。限定実行の3件はSessionFeature全suiteとの重複を含む。
- `xcodebuild ... -configuration Debug ... build` はexit 0 / `BUILD SUCCEEDED`。
- 専用保存先の実Debug版（PID 97504、Codex / gpt-6.1-sol）の新規画面で、1通も送信せず `/accessibility` の候補表示とTabでの選択を確認。`/` の一覧をスクロールしてスキルが現れることも撮影した。未送信入力は消去し、専用アプリは終了。
- `git diff --check` はexit 0。本番差分はディレクトリ列挙の2行。候補の検索・順序・重複排除・会話開始後のCodex経路は既存実装を使う。

### 未通過の確認と修正前との比較

通常品質ゲート `.claude/verify.sh` は未通過。元のスクリプトを専用worktreeの同じ相対パスへそのままコピーして実行した。AgentDomainは570件合格したが、DashboardFeatureで端末・ブラウザ・ファイル・Git表示等にタイムアウトや期待値不一致が発生した。複数の失敗後に実行が進まなくなり、サンプルとログを保存して所有するテスト実行プロセスへSIGTERMを送り、exit 1で終了した。

他の検証を終了した単独の再実行でも同じ領域の失敗を観測し、比較のため途中終了（exit 1）。さらに今回変更した本番ソースだけを一時的にHEADと完全一致に戻して同じゲートを実行すると、BottomPanelTests、PresentationLockTests、WorktreeIsolationSpawnTests、GitDisplayRegressionTests、WorktreeSchemeHandlerTests等でも失敗を観測した。修正前の比較実行も途中終了しており、全数実行済みとは扱わない。`baseline-comparison.json` にソース一致と観測した30件の問題記録を保存した。

比較後に本番ソースを修正版へ復元し、Debug確認時の保存ソースとバイト単位で一致すること、および追加4ケースの再合格を確認した。これらの既存領域の問題は今回のリンク処理の修正には含めていない。全体のgreenとは扱わない。

2026-10-17、ユーザーから「マージしてよければマージして」と指示を受け、修正版のソースのSHA256と合格したテスト・ビルドの終了コードを再確認した。`dev` は検証基準の `54394e77e5dfbdaf013672d83adc3d6e59cc46ac` と同一で、追加の統合差分はない。本修正の回帰テスト・Codex関連検証・Debug画面確認が合格していること、および全体検証の失敗を修正前にも観測したことから、この修正の `dev` への反映は可能と判断した。全体検証が未通過であることは引き続き記録する。

初回の全体検証ではXCTest 4件中1件が既存の条件によりskip（`PHLOX_SCROLL_PERFORMANCE=1` のRelease実行時だけの計測）。Swift Testingにも実CLI・計測等の既存の条件付きskipがある。テスト・期待値・skip条件は変更していない。XCUITestは実行していない。

### 警告・残る制約

- Debugビルド警告は5出現・3種類：既存のnon-Sendableクロージャ、`init(cString:)`非推奨、AppIntentsメタデータ抽出のスキップ。初回テストコンパイルにも既存のActor分離・非推奨API等の警告がある。通常品質ゲートには変更不要な変数と冗長な`#require`の警告がある。原文を検証フォルダ内のログに保存。
- 新規画面は従来のローカル候補方式で、Codexのネイティブ `skills/list` は会話開始後に使われる。今回直したのは `.claude/skills` から `.agents/skills` を共有する現在の配置での読み取り失敗。
- スクロール確認中、既存の説明読み取りがYAMLの`>-`をそのまま表示するスキルを観測した。`normalizedDescription` が`|`と`>`だけを複数行として扱う既存の別問題で、今回は未修正。

詳細なログ・画面・停止時サンプル・プロセス記録は、リポジトリルートの `.verification/fix-skill-directory-symlinks/` に保持する。`ui-new-codex-skill.png` と `ui-new-codex-scroll.png` が修正版の画面。
