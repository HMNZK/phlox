# 画像添付の受付・送信上限の分離

## 依頼

1枚20MB・最大4枚を受け付け、必要な画像だけ送信前に調整する。macOS・iOS・ControlServer・日英表示を揃え、画質・通信・再送を検証する。

## 計画

1. ADR 0182と契約資料を更新する。
2. 共通の容量規則とImageIO処理を実装する。
3. デスクトップとiOSの送信処理へ接続し、ControlServerの検証を揃える。
4. 境界・実画像・失敗時の保持をテストし、設定済み検査・ビルド・UI撮影・実CLI送信を行う。
5. 差分をまとめてレビューし、検証結果と未検証範囲を記録する。

## 作業環境

feature/image-attachment-limits、専用worktree。元ディレクトリの未コミットiOS資料・Designには触れない。

## 品質設定

- `.claude/verify.sh`はKeychain作業用ゲート。AgentDomain/DashboardFeatureを実行するが、今回のSessionFeature・ControlServer・CLIアダプター・iOSは別途必要。
- macOSは`macos/scripts/run-swift-tests.sh`がパッケージテストの正本。iOSはMakefileにtest/lint/build/UI testを設定。
- XcodeGen設定は`macos/project.yml`・`ios/project.yml`。独立したSwift lint/型チェック設定はmacOS側には見つからず、Swiftコンパイルで型検査する。
- テストは`~/.agents/scripts/compact-test`を経由する。

## 結果

### 実装

- 元画像は各20MB・最大4枚・合計80MB。共有ImageAttachmentKitで送信前に各3.5MB以下へ調整する。PNGの透明部分と小さいPNG/JPEGを保持し、HEICは送信用形式へ変換する。
- macOS・iOSは元画像を保持し、送信準備の失敗時も本文・添付を残す。送信前のモデル・画像変更を検出する。プレビューもImageIOで小さく生成し、画面のメインスレッドで巨大画像を展開しない。
- ControlServerは旧iOSとの互換性のため各4MiBを受信できる。合計14MB、HTTP body24MiB。受信後もmacOSの共通処理で各3.5MB以下にする。HookServerの上限は変更していない。
- 日英の通知と契約資料・デザイン見本を更新した。既存iOS lintの直接指定フォント2箇所は同じ値の共通定義へ移し、表示寸法を維持した。

### テスト・検査

2026-10-08、専用worktreeで実行。以下は対象パッケージの件数であり、リポジトリ全体の全テストを意味しない。

| 対象 | 結果 |
|---|---|
| AgentDomain（ImageAttachmentKit 7件を含む） | 586件成功 |
| SessionFeature | 1,134件成功 |
| ControlServer | 152件成功 |
| ClaudeAgentKit / CodexAppServerKit | 188件 / 100件成功 |
| AppBootstrap | 161件成功 |
| DashboardFeature | 本体1,984件・別実行の実git26件成功 |
| DashboardFeatureのXCTest | 4件中、既存の1件がスキップ、失敗0件 |
| DesignSystem | 193件成功 |
| iOS PhloxKit | 619件成功 |
| iOS raw-value lint | 成功 |
| macOS Debugビルド | 成功 |
| iOS Simulator Debugビルド | 成功 |
| iOS SessionInputBarRunningUITests | 1件成功（入力後の送信ボタン・停止ボタン） |
| 添付欄の画面外描画 | 1テスト成功、4画像を目視比較 |
| git diff --check | 成功 |

macOSに独立したlint・静的解析・型チェックの設定は見つからず、Swiftのコンパイルによる型検査を実行した。物理iPhoneの実機検証は未実施。

初回の失敗と修正:

- 新たな画像実体検査により、旧テストの1～8バイトの疑似PNGが送信できなくなった。実際に読めるPNG/JPEGへ置き換え、送信・再送・番号の期待値は維持した。
- ControlServerの境界テストがHTTP body上限を先に超えていたため、JSONエラーを検査できなかった。14MBの画像合計境界を超え、24MiBのbody内に収まるデータへ直した。
- 拒否時の本文復元テストはUIと同じ本文消費手順に直した。
- 一度、コンパイル中のファイル編集で「input file modified during build」が発生。編集完了後に再実行した。
- iOS lintは既存の直接フォント指定2箇所で失敗。同じ20pt・46ptを共通定義へ移して解消した。
- iOS UIテストは日本語キー入力後も本文が空で、送信ボタンの検査が失敗。再試行時にはSimulatorのテストアプリ起動拒否も記録された。確定する英字入力と本文値の検査へ直し、再実行で1件成功した。期待するボタンの挙動は変更していない。結果は`.build/ios-ui-final.log`。

残っている既存警告:

- DashboardViewの明示的returnによるViewBuilder無効化。
- AppIntents.frameworkなしによるメタデータ抽出スキップ。
- iOSのDSCampAgentBadge・DSColorの到達しないdefault、SessionDetailMetricsのMainActor呼び出し。
- 初回コンパイルではTerminalUIの非Sendableコールバック、PTYKitの非推奨init(cString:)、既存テストのMainActor format呼び出し、MarkdownBlockEditorTestsの非推奨accessibilitySetValueも出力された。

### 実送信・画質・負荷（手元で実行、リポジトリのテストには未登録）

- Claude Code 2.1.294 / Codex 0.161.0へ調整後の画像4枚を送信した。両方とも`images=4`、文字`PHLOX IMAGE TEST`、図形の色`red`を正しく回答した。小さい文字や写真の細部の画質全般を証明する検査ではない。
- ノイズを含む1,800×1,400 PNGを各6,331,070 → 3,179,642バイトへ調整。4枚の準備は1.557秒。
- 計測プロセスの最大RSSは188,317,696バイト。画像生成も含む値で、アプリ全体の使用量ではない。80MB入力時の最大メモリと物理iPhone上の性能は未検証。
- アーティファクトはworktreeの`.build/image-fixtures/`、`.build/image-fixture-runner.swift`、`.build/live-image-check.py`。実送信ログは`.build/claude-live-image.log`・`.build/codex-live-image.log`。

### 表示確認

`PHLOX_DESIGN_SNAPSHOTS=1`で添付4枚と上限通知を画面外描画した。暗色・320pt/820pt・日本語/英語の4枚を見本`PhloxReply.dc.html`と比較し、通知の折り返し・サムネイル・削除ボタンを確認した。狭い幅では既存どおり画像チップを横スクロールする。画面全体の見本一致やライト表示、物理デバイスの表示は未検証。

撮影結果は`.build/design-snapshots/attachment-*.png`。Macの稼働中Releaseアプリは終了・再起動していない。

### レビューと保留

まとまった差分について、容量規則・await前後の入力・透明PNG・原本保持・受信互換性・ローカライズを自己レビューした。独立エージェントによるレビューは実施していない。40,000,000画素・各辺32,768を超える画像は、容量が20MB以内でも拒否する。

ユーザーからdevへのマージ指示を受けた。元ディレクトリの未コミット変更は保持する。

### 第一原理からの再点検で残った課題（未修正）

1. **容量内に収まることと読めることは別。** 現在の処理は3.5MB以下になるまで各辺を0.85倍にし、最小256pxまで縮小する。文字の可読性の下限を検査していない。JPEG品質0.9も文字や細部の保持を保証しない。「画質を保ったまま」というエラー文言は現状の保証範囲を超える。
2. **元の形式だけで送信形式を決めている。** 不透明なPNGもPNGのまま縮小する。内容に応じてJPEGと比較すれば、同じ通信量でより高い解像度を残せる場合がある。透明画像と文字主体の画像には別の判断が必要。
3. **数値は運用上の暫定値。** 20MB・4枚・3.5MB・4000万画素・8000pxは、接続先の必須条件や端末の実測上限から導いた値ではない。4000万画素制限は容量内の4800万画素画像も拒否する。ImageIOの縮小読み込みを使うため、元画像の画素数×4だけで実際のピークメモリは決まらない。80MB入力の負荷と画像内容別の読み取り精度の検証が必要。
4. **iOSの送信失敗時に新しい入力を上書きし得る。** 送信中も本文欄を編集できるが、ネットワーク送信のcatchは無条件に古い本文・添付を復元する。送信準備中の変更検出だけでは防げない。これは既存の失敗復元処理にもある問題で、入力世代ごとの保持が必要。この競合は実機・UIテストでは未再現。

以上を未修正として残した状態で、ユーザーの「とりあえずdevにはマージしておいて」に従う。
