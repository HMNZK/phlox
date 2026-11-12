---
status: completed
last-verified: 2026-11-12
---

# iOS エージェント状態カードの実装計画

読者は既存チャット実装を知る開発者。以下を実装とレビューの契約として使う。
中核は「Mac の組み立て結果を共有」「本文・操作を保持」「旧サーバーへ互換」の 3 点。

## 確定する範囲と設計

最新 dev `4b0b6f7d` の Mac 状態カードを、Claude/Codex の iOS 会話にも表示する。
入力ごとのカード、タスクへの作業の帰属、実行中・完了・中断・エラー・無応答、経過時間、
タスクと作業詳細の開閉、最終返答のカード外への配置を対象とする。
承認・未回答の質問は既存の入力欄上の操作を使う。Cursor/PTY と旧 Mac は既存表示を使う。

Mac の `AgentStatusCardBuilder` をコピー・再実装しない。
既存 messages レスポンスに省略可能な `statusTranscript` を追加し、
Mac と同じ builder の結果を、Foundation だけの共有値型へ写す。
生の `messages`、cursor、snapshot は保持するため旧 iOS の受信を壊さない。
本文・差分・出力を共有値型へ複製せず、メッセージ ID で参照する。
iOS の `MessagesDelta` に同じ省略可能フィールドを追加し、初回・更新とも既存 delta 入口を使う。
取得エラーでは表示中のデータを保持し、成功した snapshot/差分では投影を置き換える。
投影なしでは従来表示へ戻す。保存形式と実行状態機械は変更しない。

共有契約は `AgentDomain/MobileStatusTranscript.swift` に置く。
`MobileStatusTranscript.blocks` は順序付きで、通常メッセージ ID 群かカード。
カードは ID、状態、見出し文言、開始/終了時刻、活動状態、行を持つ。
行はタスク/タスク外、ID、見出し、状態、自動展開の既定、時刻、entry を持つ。
entry はメッセージ ID か作業（ID、見出し、状態、所要時間、元 message ID 群）。
正確な public 宣言はタスク1で先に確定し、後続へ通知する。文字列の再解析による帰属推測はしない。

YAGNI: 新 API、永続ストア、依存ライブラリ、子エージェントの内部表示、設定追加は作らない。
KISS: 既存 delta 取得とカード部品を使い、薄い変換と表示に限定する。
DRY: ターン区切り・タスク帰属・作業集約・最終返答配置の正本は Mac builder のまま。

## タスクと契約

全実装担当は Codex 6.1 sol / medium。各担当はテストを先に書き、狙った red を記録してから実装する。
ユーザー指定の通常の TDD と費用最適化を採用し、独立した受け入れテスト基盤は増設しない。

| タスク | 担当領域・出力 | 事前条件 | 完了条件・レビュー観点 |
|---|---|---|---|
| 1: 共有契約と Mac 配信 | AgentDomain の共有値型、SessionFeature の投影変換、Dashboard の読取、AppBootstrap の messages DTO と関連テスト | 本計画確定 | 既存 builder と順序・状態・帰属・ID が一致。通常/常駐実行の現行 messages 経路双方を確認。旧レスポンスを保持。製品の送信/停止状態機械へ触れない |
| 2: iOS 受信と更新 | PhloxCore `MessagesDelta`、PhloxNetworking DTO、SessionDetailViewModel と関連テスト | タスク1の public 型確定 | 初回/差分/snapshot/再接続の投影を保持。旧サーバーと取得失敗に互換。空 snapshot による巻き戻しも古いカードを残さない |
| 3: iOS カード表示 | SessionDetail の transcript ブロック/表示、新カードと開閉、既存 snapshot fixture/テスト | タスク1の型・タスク2のVMプロパティ確定 | 44pt操作領域、Dynamic Type、明暗、動きを減らす設定、既存出力/差分/質問操作を保持。カード内外で本文を重複させない。表示窓・ジャンプIDを壊さない |

依存は `1の型確定 → 2`、`1+2 → 3`。型確定後は配信と受信を並行できる（最大幅2）。
UI は受信との接続が契約化されてから開始する。クリティカルパスは型確定→受信→UI。
共有設定の変更は各担当から親へ通知し、他担当の編集を巻き戻さない。
まとまった最終差分を1回独立レビューし、指摘のある最小範囲だけ修正する。

## 検証範囲と判定根拠

`verification-methodology` と `testing-methodology` に従い、正解は既存 Mac builder と既存仕様・見本から取る。

| 要件・壊れ方 | 最小の確認と根拠 | 時点 |
|---|---|---|
| 配信の脱落・旧クライアント破損 | Mac 投影と messages HTTPレスポンスの実物テスト。タスクあり/なし・完了返答・旧形式 | タスク1 red/green |
| 初回や差分で消える/古いカードが残る | DTO の明示 JSON、VM の初回/差分/空snapshot/失敗・旧サーバーの振る舞いテスト | タスク2 red/green |
| 本文重複・タスク外の作業が消える・開閉不能 | iOS 実表示ブロックと開閉のテスト。進行中/完了/手動操作を区別 | タスク3 red/green |
| 見た目・狭幅で欠ける | 既存 `DesignSnapshotRenderTests` に状態カードfixtureを追加。明暗・狭幅・文字拡大の代表画像を Mac の `ClaudeDesign/agent-status-card/boards/` と比較 | 最終候補 |
| 既存機能への影響 | `python3 -B macos/scripts/verification-gate.py quality` を正本として1回。既存パッケージ/結合/必須fake E2E・iOS lint/buildを含む | 最終候補 |

Swift コンパイルの型検査とリンク、lint、テスト、画像観察は別の結果として記録する。
単独の追加静的解析設定は調査範囲で未設定。新規 E2E や全組合せ画像は追加しない。
ビルドは managed-build、テストは compact-test 経由。検証物は当 worktree の
`.verification/ios-agent-status-card-20261112/` 配下へ置く。
実機・VoiceOver実操作・公開/配布は今回の完了条件に含めず、未確認として報告する。

## 作業記録

- 計画確定: 2026-11-12。元チェックアウトと未追跡の Mac 計画書を保持し、dev から専用 worktree を作成。
- ドキュメント差異: Mac 設計 §6 は iOS が組み立て規則を持つ案だったが、本作業では Mac の投影配信へ確定。既存の共有 ChatRenderKit はあるが Mac builder は SessionFeature へ依存しており、そのままの移動は不適切。
- 調査で見つけた既存資料の古い記述: `ios/Makefile` は存在しない `.github/workflows/ci.yml` と sibling `../Phlox` を前提としているが、実コードは同一リポジトリの `macos/Packages` に依存する。`PhloxKit/Package.swift` の sibling という説明も同様。今回の製品差分に無関係なコメントは変更しない。標準品質入口は実在する `verification-gate.py quality` を使う。
- ローカルスキル: dev の追跡ファイルには `verify-phlox` が無い。元チェックアウトのスキルを読み、同 worktree を検証対象にできるよう ignored `.agents/skills/verify-phlox/` へ一時コピーし、所有を検証記録へ記載した。

### 実装と確認済みの結果

- タスク1: 局所165件成功。タスク2: 72件成功。タスク3: 64件成功。各担当の red/green は検証フォルダの task1-*、task2-records/、task3/ に記録。
- `verify-phlox` 段1: send/stop/resume/restore の全35パターン一致、対象60件成功（パターンごとの合計）。実アプリを起動する段2は実行サービス・起動構成を変えていないため対象外。
- 独立レビュー1回: 作業詳細から元コマンドが抜ける指摘1件を修正。既存コマンドカードを固定展開で再利用し、終了コードも保持。
- iOS SDK のビルド・リンク成功。既存描画 suite は26件成功、状態カード8場面を書き出した。Mac見本と実画像を比較し、タスク階層・完了の取り消し線・時間・詳細・明暗・幅375pt・文字拡大を確認。`StatusStalledSE` というfixture名の画像は375×926ptで、実SEの縦寸法の確認とは区別する。
- 作業の実ボタン1回の操作で、元コマンド・出力・差分が同時に公開AXへ現れることを確認。外部AX証拠は当該実行のnonce・PID・端末ID・時刻に結び付け、実観測の該当行を無改変で抜粋した。
- 最初の内部AX検査は、SwiftUIの仮想AXをホスト内から列挙できず失敗。既存の外部AX受入経路を明示選択の `StatusWorkOpen` に接続し、通常の自動描画には外部操作を要求しない。外部初回は確認期限超過で失敗。次の実観測で重複ラベルを発見・共通ヘッダーで修正した後、固定見出しの静的テキストtraitを明示し、同じ完全一致条件で成功した。期待値は緩めていない。
- 描画の検証コピーでは標準 Makefile の derivedDataPath だけを既存変数へ接続し、画像を managed-build のビルド出力と分離した。製品側の Makefile は変更しない。
- Macアプリのコンパイル・リンク成功（`macos-app.exit=0`）。標準 `quality` も成功（`quality.exit=0`）。Swift Testing の一意な成功IDは Mac 6,076件、iOS 705件、必須 fake E2E は13件。XCTestの集計・補助検査・ビルド結果も正本のゲートが確認した。
- Mac の通常検査には既定除外25件と既知問題1件がある。既知問題は `GitHistoryWorkflowTests/GTWRegression_改名前の名前を再利用しても利用順を混同しない`（ADR 0209の既存制限）で、今回の差分による新規失敗ではない。期待値・除外設定は変更していない。すべてのテストが無条件に成功したという意味ではない。
- 最終証拠: `.verification/ios-agent-status-card-20261112/quality-20261111T170548321193/result.json`、`snapshot-final2.log`、`visual/snapshots/`、`verify-phlox-unit/result.json`。ゲート実行は1回、約15分31秒。反復は局所テストと失敗した描画ケースに限定し、同一管理ビルド出力を再利用した。LLM利用トークン・金額は未計測。
- 実機でのカード画面・VoiceOver音声の実操作、全既存画面の画像生成、一般配布・push・dev/main統合は未実施。実機への直接導入は下記。新カードの表示には今回の Mac 側API更新も必要で、旧 Mac 接続時は従来表示となる。

### 後片付けと保持

- 元チェックアウトと未追跡の Mac 計画書は変更していない。成果のある作業 worktree とブランチ、検証ログ・画像・入力指紋はレビューと統合前の再検証用に保持する。
- 比較用HTTPサーバーは終了。専用Macアプリは起動せず、固有bundle IDのLaunchServices登録を解除。検証コピー、一時スキルコピー、ブラウザー画像の中継用フォルダはゴミ箱へ移動した。
- 管理ビルド3件は `managed-build.py finish` で終了記録済み。通常の開発キャッシュは変更せず、専用出力は共通ツールの保持規則に従う。
- 専用シミュレータ `7C5453E6-9C93-4154-8954-ADC9D5D0FEF4` は電源停止を確認。端末定義の削除は自動承認レビューに高リスクとして拒否されたため保持した。詳細は `simulator.json`。

### 実機への直接導入（2026-11-12）

- ユーザーの追加指示により、既存ペアリング済みの iPhone 14 Plus「stultus」（iOS 27.2）へ無線で導入した。既存の Bundle ID `com.phlox.mobile.PhloxMobile` のまま、1.0/build 23 から 1.0/build 24 へ更新。アプリ削除やデータ初期化は行っていない。
- 標準品質ゲートが成功したコピーと現作業ツリーの Swift 入力517件の一致を確認し、実機用コピーで署名設定だけ調整。既存の Apple Development/Distribution 証明書と、本体・Widgetの登録済みプロファイルを使用した。証明書作成・端末登録・署名資材の更新は行っていない。
- Xcode管理のAd Hocプロファイルは手動署名の直接buildで拒否されたため、標準のautomatic archive→Ad Hoc exportへ切替。archive/exportは成功。本体・Widgetの版/ビルド、署名、同一Team、対象端末、有効期限、App Groups、本体のproduction Push entitlementを検査した。
- `devicectl device install app` は成功。別の `device info apps` で実機の1.0/build 24を照合し、`device process launch` も成功（PID 57717）。画面の見た目やMac側対応APIとの実接続は、この導入操作だけでは確認していない。
- 証拠は `.verification/ios-cards-device-20261112/` の `source-provenance.json`、`signature-report.json`、`install.json`、`apps-after.json`、`launch.json`。署名済みIPAとarchiveは再導入・障害解析用に保持する。
