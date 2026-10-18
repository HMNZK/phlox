---
status: active
last-verified: 2026-10-18
---

# 0027: iOS 再設計 段階7 — アプリ外の表示（作業記録）

> **役割**: [計画書0020](0020-ios-redesign-plan.md) 段階7の変更・テスト・見本との比較結果。
> **仕様**: [再設計仕様12章](../specs/redesign-2026-10.md)、ADR [0009](../adr/0009-widgetkit-app-group-session-status.md)・[0011](../adr/0011-session-live-activity-push-driven.md)。

## 1. 変更

- `PhloxWidget/SessionStatusWidget.swift`: 最新の1件を表示する既存方式を維持し、日本語・端末の外観・セッション別の `widgetURL` へ更新。描画を `Views/SessionStatusWidgetView.swift` に分離。
- `PhloxWidget/SessionLiveActivity.swift`・`Views/SessionLiveActivityView.swift`: 状態の記号＋語／名前／Macのsummary。Dynamic Island は expanded・compact・minimal を更新し、黒地にダークの状態色。両方に同じセッションURL。
- `Views/GlanceStyle.swift`: 端末の `colorScheme` で色を解決する。アプリの `ThemeStore` を参照しない。実行中は円弧、ほかは指定の SF Symbols。minimal の記号にも状態を読むラベルを付ける。
- `PhloxCore/Shared/SessionGlanceState.swift`: 記号・語・状態色の数値。`DesignSystemIOS/Tokens/IOSColor.swift` も同じ前景色の数値を参照する。拡張へ `DesignSystemIOS` の Markdown 等の依存を追加せず、拡張の直接依存は `PhloxCore` のまま。背景の透明度はアプリ内とアプリ外で異なるため `GlanceCatalog` の値を使う。
- `SharedSessionStore.swift`: v1キーと既存5項目を維持し、optionalな `displayState` を追加。無応答・完了の未読は解決済みの値で保存する。古い保存データと未知の将来値も読める。古い `Waiting` は保存済みの補足が承認／質問を明示する場合だけそれを復元し、情報の無い旧データに無応答や未読を推測して足さない。
- `Features/SessionList/SessionListViewModel.swift`: 空の成功応答も取得時刻を記録し、古いセッションのキャッシュを消す。タップより古い一覧をF8判定に使わず、同じ内容の再取得でも保留遷移を再評価する。
- `SharedSessionWriter.swift`・`DesignSystemIOS/Tokens/SessionGlanceProjection.swift`: 状態判定は段階2の `Session.displayState` のまま、アプリ側で最小の値へ変換して保存する。入力順を保持し、最新の1件の選択は拡張が行う。補足はプロジェクト名、エラー時はMacのエラー文。`AppRoot.writeSharedSessionState()` は未取得・通信失敗のときに保持し、取得成功の0件は空へ更新する。
- `PhloxCore/Shared/SessionURL.swift`・`Features/Push/PushCoordinator.swift`・`App/PhloxMobileApp.swift`・`App/AppRoot.swift`: `phlox://session/<id>` を通知と同じ `pendingSessionID` に渡す。ロック中・一覧取得前・通信失敗では保持し、タップ後の取得成功を `lastFetchedAt` で確認してから既存の詳細画面へ進む。承認・質問カードも既存画面を使用する。対象が無ければ一覧に戻してF8。無効なセッションURLをペアリングへ渡さない。既存の `phlox` URL scheme は `Info.plist` と `project.yml` で確認し、追加登録は不要。
- `project.yml`・`PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift`: 拡張と同じ `Views/` のソースを描画ターゲットにも含め、ライト／ダークのカタログ画像を2倍で書き出す。
- 資料: 仕様12章から「終了」の記号を外し、計画書・ADR0009/0011・`architecture/overview.md`・delivery索引を更新。

## 2. 消したもの・通知の扱い

- 固定の濃紺背景・白文字、英語の `Starting` / `Waiting` / `Finished` 表示、`View ›`、Dynamic Island の `Wait` / `Done` / `End`、旧来の塗り記号と `stop.circle` の表示分岐を削除。ファイル削除は無し。
- エージェント別の色・エージェントの略号・紫ピンクのグラデーションは拡張に無い。無応答の紫は状態色として残す。
- `session_exited` のワイヤコードは維持するが、Macの非0終了の通知なのでエラーとして描く。共有の表示状態に独立した「終了」を追加しない。
- 通常通知はOSの標準の枠・アイコンで、本文はMacの `APNsNotificationBridge.NotificationEvent.body` が生成する。質問の本文は「質問があります」であり、iOS側に「質問待ち」などの通知本文生成・着色の実装は無かった。Macの本文・Live Activity のsummary・通知の許可時期は変更していない。通常通知のSF Symbolsを独自描画する拡張は追加していない。

## 3. テスト（前 → 今）

- `SharedSessionStoreTests.testSharedSessionWriterPreservesInputOrder`: PhloxCoreTests → DesignSystemIOSTestsの `SessionGlanceProjectionTests` へ移動。変換がデザイン層の共有判定を使うため。実ストアへ2セッションを書き、IDの順序が同じことを確認するアサーションは維持。削除・skip・期待値の弱化は無し。
- `SessionListViewModelTests.testEmptyState`: 空の成功応答の状態確認 → 同じ確認に取得時刻の記録も追加。新規 `testConfirmedEmptyClearsCachedSessionForExternalNavigation` で、実際に0件になった後の古いセッション保持を防ぐ。
- 既存描画テスト: アプリ内の画面に加え、実ウィジェットView（全表示状態＋空、small／rectangular）とLive Activity View（既存6コード＋未知）のライト／ダークを追加。
- 新規 `SessionGlanceTests` 7件: 全表示状態の記号とライト／ダーク／Dynamic Islandの前景色、状態別の地、APNsコード、旧・未知形式の読み取り、旧英語ラベルの復元、実ストアの読み書き・空更新、URLの組み立て・解析と不正URL。
- 新規 `SessionGlanceProjectionTests` 2件（移動した1件とは別）: 無応答・完了の未読を含む共有状態の投影・補足、Cursorの承認抑止。
- 新規 `SessionURLNavigationTests` 3件: URLと通知が同じ保留値を使うこと、ロック解除・タップ後の取得成功後に同じセッションIDの詳細へ進むこと（古い取得時刻・取得時刻無しでは保留）（承認・質問・実行中の3入力）、対象消失時に一覧へ戻ること。ルーターのパス・モーダル解除も確認。

| 単体テスト | 前 | 後 |
|---|---:|---:|
| XCTest | 368 | 371 |
| Swift Testing | 609（101スイート） | 619（103スイート） |
| 合計 | 977 | 990 |

検証ログの保存先は worktree ルートの `.verification/ios-redesign-stage7/logs/`。コマンドは指定の `compact-test --full` 経由。初回の追加テストで `.awaitingApproval` の必須引数漏れによりコンパイル失敗（exit 1、`unit.log`）。引数を修正し再実行した。初回コンパイルには既存の `DSReasoningTextWhiteboxTests` からMainActor隔離メソッドを非隔離文脈で呼ぶ警告も出た。テストの削除・skip化はしていない。

## 4. 検証と画像

指定の2台は同時に描画せず順次実行。iOS26は `bootstatus -b` 完了後に20秒待機した。OSの版をファイル名に付け、出力先は `.verification/ios-redesign-stage7/` に固定。

| 検証 | 件数・結果 | exit | ログ |
|---|---|---:|---|
| 変更前 `swift test --package-path ios/Packages/PhloxKit` | XCTest 368 + Swift Testing 609 = 977成功 | 0 | `before.log` |
| 変更後 同コマンド | XCTest 371 + Swift Testing 619 = 990成功、失敗0・skip0 | 0 | `unit-freshness-final.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios generate` | 生成成功（テスト件数は対象外） | 0 | `generate.log` |
| 指定 `xcodebuild build` / PhloxMobile | `BUILD SUCCEEDED`（テスト件数は対象外） | 0 | `build-app-freshness-final.log` |
| 指定 `xcodebuild build` / PhloxWidget | `BUILD SUCCEEDED`（テスト件数は対象外） | 0 | `build-widget-final.log` |
| 指定 `make -C ios snapshot` / iOS26.2 | 3件成功、94画像（うち新規4） | 0 | `snapshot-ios26-final.log` |
| 指定 `make -C ios snapshot` / iOS18.3 | 3件成功、93画像（うち新規4） | 0 | `snapshot-ios18.log` |
| `PATH=/opt/homebrew/bin:$PATH make -C ios lint` | raw値lint成功（テスト件数は対象外） | 0 | `lint-complete.log` |
| `git diff --check` | 成功 | 0 | 手元で実行、テストには未登録 |

`xcodebuild -list -project ios/PhloxMobile.xcodeproj` で `PhloxMobile`・`PhloxWidget` のスキーム名を確認した。最終の単体テスト・両ビルド・iOS26描画・lintのログに警告・エラーは無い。初回のiOS26描画も3件成功（`snapshot-ios26.log`）。その画像を開いて経過時間・文字サイズ・空のrectangularの折り返しを直した後、最終のiOS26を再実行した。preflightのBusyは出ず、起動失敗の再試行は不要だった。描画後の遷移の取得時刻ガードは単体テストとアプリの再ビルドで確認している。

iOS18描画は成功したが、アプリ内の画面の描画中に `Modifying state during view update, this will cause undefined behavior.` 60件と `CGGStackRestore: CG GState restored too many times` 104件が出た。新規Glance4画像はログ521〜524行で出力され、最初の警告は530行。前段階の保存ログ `.verification/ios-redesign/logs/verify-s6-snapshot-ios18.log` にも同種が60件・103件あり、今回と同じ分類の警告が残っている。警告の内部原因は未特定で、今回の変更で解消したとは扱わない。

XCUITest・入力操作の合成は実行していない。入力ソースの設定は変更していない。追加の独立lint・型チェック・静的解析コマンドは未設定（既存設定は `ios/Makefile` とraw値lint。Swiftの型・リンクは各ビルドで検査）。通常の `make test` は指定のSwiftPMテストと同じため別実行していない。アーキテクチャ文書が参照していた `.claude/verify.sh` はこのworktreeには存在しないため使っていない。

画像の保存先（worktreeルートからの相対パス、いずれも2倍）:

- `.verification/ios-redesign-stage7/snapshots/glanceWidgets-light-ios26.png`
- `.verification/ios-redesign-stage7/snapshots/glanceWidgets-dark-ios26.png`
- `.verification/ios-redesign-stage7/snapshots/glanceLiveActivity-light-ios26.png`
- `.verification/ios-redesign-stage7/snapshots/glanceLiveActivity-dark-ios26.png`
- `.verification/ios-redesign-stage7/snapshots/glanceWidgets-light-ios18.png`
- `.verification/ios-redesign-stage7/snapshots/glanceWidgets-dark-ios18.png`
- `.verification/ios-redesign-stage7/snapshots/glanceLiveActivity-light-ios18.png`
- `.verification/ios-redesign-stage7/snapshots/glanceLiveActivity-dark-ios18.png`

## 5. 見本との比較・残差

`GlanceCatalog-2200x3900.png` と `GlanceCatalogDark-2200x3900.png` を開き、出力した上記8画像も開いて比較した。新しい状態色（完了の緑、無応答の紫、承認／質問／エラーの地）、状態→名前→補足の順、空表示、日本語の状態語を確認した。初回の「2分0秒」は相対日付の書式を変更し「2 分前」に修正。文字サイズも状態13・Live Activityの見出しと名前16・summary13へ合わせ、空のrectangularは1行にした。

残っている違いと理由:

- ウィジェットの左上は見本の「P」の角丸印ではなく「Phlox」の文字。略号のバッジを使わない指示に合わせ、アプリ名を明示した。エージェントの略号やロゴは出さない。
- 相対時刻の空白・書体とSF Symbolsの字形はOS標準。見本の手描きSVGやHTMLのフォントと画素単位では一致しない。タイトルは仕様どおり2行で省略する。
- 「終了」と非0終了専用の八角形の行は仕様U-3／AC-12-1を優先して採用していない。APNsの `session_exited` はエラーの三角。共有 `displayState` が完了なら完了のチェックにする。
- カタログ画像は実Viewに寸法・地を与えて撮ったもの。WidgetKitの実ホーム配置、ロックの単色化・壁紙との背景合成、Dynamic IslandのOS枠、通常通知のOS枠は再現・撮影していない。Dynamic Islandの状態色の固定は単体テストとコードで確認。実機のAPNs受信・タップ自体は未検証。

実装の未決事項は無し。OSが描く部分・実機配信の確認は残る検証範囲として扱う。変更は `ios/` 内、コミット無し、共有 `macos/Packages/DesignSystem`・`AgentDomain` と `.env*` は変更していない。


後片付け: 指定2台のshutdownと残存する当作業のxcodebuildが無いことを確認。専用ビルドのテスト結果3件は `.verification/ios-redesign-stage7/results/` に保存し、残りの専用buildはゴミ箱へ移動した。画像・ログは保持。既存 `.verification/ios-redesign/build` と通常のSwiftPM `.build` は既存の再利用キャッシュとして保持した。worktree・ブランチは依頼された作業場所と未コミット成果物なので保持する。

## 6. 変更ファイルの一覧

- `ios/App/AppRoot.swift`
- `ios/App/PhloxMobileApp.swift`
- `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Tokens/IOSColor.swift`
- `ios/Packages/PhloxKit/Sources/Features/Push/PushCoordinator.swift`
- `ios/Packages/PhloxKit/Sources/Features/SessionList/SessionListViewModel.swift`
- `ios/Packages/PhloxKit/Sources/PhloxCore/Shared/SharedSessionStore.swift`
- `ios/Packages/PhloxKit/Sources/PhloxCore/Shared/SharedSessionWriter.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/SessionListViewModelTests.swift`
- `ios/Packages/PhloxKit/Tests/PhloxCoreTests/SharedSessionStoreTests.swift`
- `ios/PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift`
- `ios/PhloxWidget/SessionLiveActivity.swift`
- `ios/PhloxWidget/SessionStatusWidget.swift`
- `ios/docs/adr/0009-widgetkit-app-group-session-status.md`
- `ios/docs/adr/0011-session-live-activity-push-driven.md`
- `ios/docs/architecture/overview.md`
- `ios/docs/delivery/0020-ios-redesign-plan.md`
- `ios/docs/delivery/README.md`
- `ios/docs/specs/redesign-2026-10.md`
- `ios/project.yml`
- `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Tokens/SessionGlanceProjection.swift`
- `ios/Packages/PhloxKit/Sources/PhloxCore/Shared/SessionGlanceState.swift`
- `ios/Packages/PhloxKit/Sources/PhloxCore/Shared/SessionURL.swift`
- `ios/Packages/PhloxKit/Tests/DesignSystemIOSTests/SessionGlanceProjectionTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/SessionURLNavigationTests.swift`
- `ios/Packages/PhloxKit/Tests/PhloxCoreTests/SessionGlanceTests.swift`
- `ios/PhloxWidget/Views/GlanceStyle.swift`
- `ios/PhloxWidget/Views/SessionLiveActivityView.swift`
- `ios/PhloxWidget/Views/SessionStatusWidgetView.swift`
- `ios/docs/delivery/0027-ios-redesign-stage7-worklog.md`

## 検証（段階 7 の差分全体。検証の担当 Codex gpt-6-luna high が実行。コードは変えていない）

| 検査 | 結果 |
|---|---|
| `swift test --package-path ios/Packages/PhloxKit` | XCTest 371 件・Swift Testing 619 件成功、失敗 0・skip 0、exit 0 |
| `make -C ios generate`・`xcodebuild build`（PhloxMobile・PhloxWidget） | exit 0 |
| `make -C ios snapshot`（iOS 26.2・iOS 18.3） | どちらも 3 件成功、exit 0 |
| `make -C ios lint`・`git diff --check` | exit 0 |
| `rg -ln '#available\(iOS 26' ios --type swift` | 3 ファイル（DesignSystemIOS の共通の部品だけ） |
| URL の scheme | `phlox` のまま。`phlox://pair` の経路も残っている |

警告（テストは通った）: iOS 18 の描画で `Modifying state during view update` 60 回・`CGGStackRestore` 102 回（段階 6 と同じ。段階 8 で調べる）。XCUITest は走らせていない。ログは `.verification/ios-redesign/logs/verify-s7-*.log`。実機の APNs・ウィジェットを押したときの遷移・Dynamic Island の OS の枠は確かめていない。
