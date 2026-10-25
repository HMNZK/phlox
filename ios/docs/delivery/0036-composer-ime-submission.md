# 問題定義: 変換中の本文を含めた送信

## 解決したい問題

日本語の変換を確定せず送信すると、未確定部分が送信から欠け、入力欄に全文が残る。

最新devの変換中placeholder修正と組み合わせ、表示状態の独立した通知を維持する。送信時は本文・選択の遅延通知と表示状態の遅延通知を取り消し、確定済みの状態を同期する。

## 修正前（調査の根拠つき）

- `DSInputRichTextEditor.Coordinator.publishNativeState` は変換中の本文を Binding に公開せず、確定後の通知も次の MainActor ターンへ遅延する。
- `DSInputBar.submit` は UIKit の本文を確定・同期せず `onSubmit` を呼ぶ。
- `SessionDetailViewModel.sendMessage` は送信開始時の `inputText` を使い、その後の編集を保護するため、本文が変わった場合は消さない。入力の確定が送信開始より後になると、古い本文が送られ、新しい全文が残る。
- 同じ入力欄を `NewChatView` と `SessionDetailView`（質問への自由回答を含む）が使用する。

## 成功基準（検証可能な形で）

- iOS のホスト付き単体テストで `setMarkedText` により再現し、送信ボタンの公開アクセシビリティ操作で未確定部分を含む全文が一度渡る。
- 未確定部分だけの入力も送信でき、送信受付後の本文クリアを遅延通知が戻さない。
- 送信失敗相当（呼出先が本文をクリアしない）では全文が残る。
- 確定済み文字の遅延通知も送信前に同期され、空白のみ・送信中の送信を防ぐ。
- 既存の iOS lint、PhloxKit テスト、iOS ホスト付きテスト、ビルド・静的解析を実行する。

## 仮定 / 未知

物理端末の日本語キーボード操作は未確認。UIKit の未確定文字列 API を使い、同じ送信操作をシミュレーターで検査する。

## 制約（技術・運用・期限）

- `dev` から切った専用 worktree `ios-ime-send-20261025` で作業し、元の未コミット変更（変換中の placeholder 修正を含む）を保持する。
- 変換中の通常編集では本文 Binding を公開しない。送信操作時だけ明示的に確定・同期し、キーボードのフォーカスは維持する。
- XCUITest と入力ソース変更は禁止。検証物は `.verification/ios-ime-send-20261025/` に分離する。

## スコープ外

API、送信後の編集保護、添付、キーボード設定、画面デザインの変更。

## 既知リスク

確定時に発生する delegate 通知が本文を復元する競合を防ぐため、送信前の同期で古い遅延通知を無効化する。

## 検証結果（初回）

- 元の作業場所で管理ビルドが「同じプロジェクトで別の管理ビルドが実行中です」と停止したため、専用 worktree に分離した。
- `xcodegen` は PATH に無かったため、既存の `/opt/homebrew/bin/xcodegen` でプロジェクトを生成した。
- 回帰検査の結果は以下。
- 修正前: `確定済み🙂 日本語` の表示に対して送信値は `確定済み🙂 `。未確定範囲と全文が残った。確定済み文字の遅延通知でも `前🙂後` に対して `前` が送られた。
- 新規のホスト付きテストは、SwiftUI の AX を取得するためテストプロセス内で `_AXSSetAutomationEnabled` を有効にする（XCUITest は使用しない）。利用不可ならテストは失敗する。参考: [EarlGrey の AX 初期化](https://github.com/google/EarlGrey/blob/master/EarlGrey/Core/GREYAutomationSetup.m)。
- テスト補助クラスの初回コンパイルは `Draft is inaccessible due to private protection level` で失敗し、マクロの展開先から参照できる `fileprivate` に修正した。AX 初期化前の検査は送信ボタンを取得できず失敗し、修正前の挙動の再現結果には数えていない。
- 修正: 入力欄ごとに保持する UIKit 参照と変換中の表示本文を用い、送信可否を判定する。送信操作時に [UIKit の unmarkText](https://developer.apple.com/documentation/uikit/uitextinput/unmarktext()) で確定し、古い通知を無効化して本文・カーソルを同期する。通常の編集通知は従来どおり遅延し、変換中の本文 Binding は更新しない。
- 修正後の初回検査: `ComposerIMESubmissionTests` と `DesignSnapshotRenderTests` の18テスト成功（新規5テスト、うち1テストは3入力）。新規検査は UIKit の未確定文字列 API と実際の SwiftUI 送信ボタンの AX 操作を使う。
- 上記検査の既存キャレット描画テストで `Unbalanced calls to begin/end appearance transitions` が7回出た。テストは成功したが、警告の発生自体は未解消。
- デザイン見本の HTML が参照する `support.js` は同梱されていない。見本のブラウザー描画は未確認。
- PhloxKit の macOS ホスト検査: XCTest 400件、Swift Testing 668件成功。iOS 専用の UIKit 送信処理は上記 iOS ホスト付きテストで検査している。
- 追加で試したホスト全体検査は成功扱いにしない。標準の `ios/Makefile` が別実行としている対話検査まで含めてしまい、システム文字サイズ・生体認証・対話実行フラグの前提不足で失敗した。さらに `RootFingerPanAttention` が実操作を待ち、CUA の Simulator 接続が2回 `timeoutReached` で失敗したため、所有確認した xcodebuild PID 92355 を SIGINT で停止した（終了コード75、`TEST INTERRUPTED`）。中断時に Xcode 自体も `SchemeActionResultOperation started unexpectedly` を警告した。テストや期待値の無効化は行っていない。
- 上記の広範囲検査ではシミュレーターの `hapticpatternlibrary.plist` 欠落も記録された。詳細ログは `.verification/ios-ime-send-20261025/host-full.log` に保存する。
- 送信中・画像添付時の2画面は画面外で描画し、生成した PNG を目視確認した。見本のブラウザー描画との比較は未確認。
- 最終の対象検査: 新規の送信検査と既存の描画検査の18テスト成功（`targeted.log`、終了コード0）。描画は上記2場面に限定し、全盤面の検査とは扱わない。画面遷移警告7回は継続している。
- `xcodebuild analyze` 成功（`analyze.log`、終了コード0）。iOS ホスト付きテストでアプリのコンパイル・リンクも成功。独立した型チェッカーは未設定であり、Swift コンパイラーによる型検査を実行した。
- iOS の設定済み raw-value lint、`git diff --check` 成功。対象外の macOS アプリの検査は実行していない。
- 手元の自己レビューで呼出先を再確認した。`NewChatView`・`SessionDetailView`・自由回答は同じ `DSInputBar` を使うため、呼出先と API の変更は不要。新規検査は `ios/PhloxMobileSnapshotTests/ComposerIMESubmissionTests.swift` に登録した。
- 専用端末は停止済みを確認して削除し、管理ビルドの終了を記録した。作業ブランチは未マージ。ソース、テスト、検証ログ・2枚の画像をこの worktree に保存し、使い捨ての対象外 UI 診断はゴミ箱へ移動した。

## 再開時の確認

- 実装と検証ログを保持したまま再開した。`dev` に写真選択・フォーカスの修正が入ったため、共通マージツールで作業ブランチへ取り込み、変更した入力欄とその呼出元を再検証する。
- 対話検査は `ios/Makefile` の標準スナップショット入口と分離して扱う。以前に前提不足で失敗した全体検査を、対象を絞った検査の成功で置き換えたことにはしない。
- `dev` の取り込みは共通ツールで完了した。追加されたフォーカステストの初期化引数を合わせ、既存の描画テストは有効な UIWindowScene に結び付けて画面遷移警告の解消を検査する。送信後も実際の UITextView が first responder（キーボード入力の受け取り先）を維持する回帰検査を追加する。
- 初回の統合検査は29テスト中2指摘で失敗した。追加診断では、フォーカスありの入力は送信前の80ms待機中にキーボード側から取り消されていた。未確定範囲が存在することを確認して同じMainActor処理中に送信する検査へ直す。空の本文へ戻す描画も80ms固定で判定せず、最大2秒の描画完了待ち後に同じ空文字の期待値で検査する。`resume-ios.log` と `resume-diagnosis.log` に失敗・診断を保持する。
- 画面遷移警告の検査環境側の対策として、フォーカス判断だけのSpy検査は不要なUIViewControllerの表示を除き、実描画の検査はウィンドウ表示後にイベント処理を待ってから実行する。
- 次の統合検査ではフォーカスを保持する送信は成功したが、未確定文字のみの送信後にネイティブ表示が残る検査が最大2秒の待機でも失敗した。本文が同じ描画周期で「空→確定済み全文→空」へ戻ると、UIViewRepresentableへの更新が省略される条件だった。送信確定の世代を値として渡し、本文が同じ値へ戻ってもネイティブ側へクリアを届ける。
- 上記修正後の統合検査は29テスト・3スイート成功（`resume-revision.log`、exit 0）。送信検査6件（うち1件は3入力）、既存のフォーカス・写真・描画検査、スキル候補の描画・AX操作を含む。画面遷移警告は0件。実キーボードを表示する検査では、シミュレーターの触覚素材 `hapticpatternlibrary.plist` 欠落ログが継続している。
- 統合後の PhloxKit 検査は XCTest 402件・Swift Testing 676件、計1,078件成功（`resume-package.log`、exit 0）。raw-value lint と差分の空白検査も成功。
- 統合後の `xcodebuild analyze` も成功（`resume-analyze.log`、exit 0）。呼出元2箇所と最終差分を手元で確認した。`dev` への反映は共通ツールが作る文書保守・品質・秘密情報検査の記録に従う。実機および見本のブラウザー描画との比較は引き続き未検証。
- 共通ツールでの `dev` 反映は品質検査 exit 1 で停止した（`resume-dev-merge.log`）。`dev` は入力OID `a2ed7ae9` のまま、`updated=0`。文書検査は成功し、秘密情報検査は品質失敗のため未到達。
- 失敗は Mac の SessionFeature の3指摘: `ComposerSettingPopoverTests.clickingOutsideClosesNativePopover` の legacy false/true（115行、閉じない）と、`ComposerSuggestionDescriptionTests.popupAnimatesOnlyTheSelectedDescription`（203行、アニメーションキーが期待1件に対し2件）。候補 `9f4a81f9` と入力 `dev` の間に macos/ のコード差分はない。Mac 側で失敗する根本原因は未確定で、追加の調査・修正範囲をユーザーへ確認した。スキップや期待値の変更で反映を通していない。
- 品質入口の他パッケージは継続して実行された。DashboardFeature の既存 XCTest は6件中1件がスキップされたため、そこを全数成功とは記述しない。スキップ理由はこの成功要約ログでは確定できない。

## 明示承認された例外

- ユーザーの「無視してdevにマージして」により、上記3指摘に対応する `clickingOutsideClosesNativePopover`（2条件）と `popupAnimatesOnlyTheSelectedDescription`（1条件）を今回の品質検査だけ `SWIFT_TEST_SKIP` で除外する。リポジトリのテスト・期待値・品質設定は変更しない。
- 他の設定済み品質検査、文書保守、秘密情報検査は共通マージツールで実施する。除外した3条件の不具合は未解決のままであり、検査成功とは扱わない。
- 除外後の品質検査は exit 0 だったが、DashboardFeature の `Package.resolved` が実行時に自動更新され、候補を変更しない検査に失敗して反映は停止した。SessionFeature・AppBootstrap が既に固定している `swift-argument-parser` 1.8.2 にDashboardFeatureも揃え、自動生成された originHash を含めて保存する。依存の要求範囲やテスト設定は変更しない。
- 保存した固定ファイルは検査が生成したものと同一で、`--force-resolved-versions` による解決も成功した。検証時の `--skip-update` は廃止予定との警告が出たが、この一時コマンドのみで使用し、ビルド設定には追加していない。
