# 問題定義: 日本語変換中の placeholder 重複

## 解決したい問題

空の入力欄で日本語を変換している間、未確定文字列と placeholder が重なる。

## 現状（調査の根拠つき）

- `DSInputBar.inputTextField` は SwiftUI の本文 `text.isEmpty` だけで placeholder を表示する。
- `DSInputRichTextEditor.Coordinator.publishNativeState` は `markedTextRange != nil` の間、本文と選択の通知を止める。このため未確定文字列が UITextView に表示されても SwiftUI の本文は空のままになる。
- `updateUIView` の未確定文字列を保護するガードは必要であり、維持する。

## 成功基準（検証可能な形で）

- iOS のホスト付き単体テストで `setMarkedText` による未確定文字列を作り、placeholder の文言を変更しても描画が変わらないことを確認する。
- 変換中は本文 Binding が空、未確定範囲と文字列は保持される。
- 変換の取り消し・確定・全削除後の表示を確認する。
- iOS の既存 lint、PhloxKit の単体テスト、スナップショットターゲットのテスト（XCUITest ではない）を実行する。

## 仮定 / 未知

- 添付画像の下線付き入力は未確定文字列と整合する。物理端末のキーボード操作はこの調査環境では未確認。

## 制約（技術・運用・期限）

- 未コミットの写真ピッカー・フォーカス修正を保持する。
- 未確定の本文を送信可能な本文 Binding に書き込まない。表示用に変換中の状態だけを次の MainActor ターンで通知する。
- XCUITest と入力ソースの変更は禁止。専用シミュレーターと `.verification/ios-ime-placeholder-20261025/` を使用する。

## スコープ外

写真添付、送信処理、モデル設定、画面レイアウトの変更。

## 既知リスク

変換中の状態通知が古い通知で上書きされると placeholder が再表示される。既存の世代管理付き通知を利用し、取消・確定・連続編集の回帰テストで確認する。

## 検証結果

### dev 統合

dev の入力欄にあるスキル候補表示などの既存変更を保ち、今回の表示判定・ネイティブ変換状態通知・回帰テストだけを適用する。統合時点の iOS ホスト付きテストを実行し、共通マージツールの文書保守・既存品質ゲート・秘密情報検査を通して dev に反映する。

dev `a2ed7ae9` に適用した状態のホスト付きテストは23件 pass / exit 0。`ios-ime-placeholder-dev-20261025` の専用端末で実行した。ログには画面遷移の開始・終了の不整合、シミュレーターの触覚パターンファイル不在、起動計測イベント送信失敗が残り、実機入力は未検証。

同じ状態の PhloxKit 全体は XCTest 402件と Swift Testing 676件が pass / exit 0。既存 lint、iOS ビルド・リンク、静的解析も成功した。変換中の画像で placeholder の重複がないことを再確認した。

### 実装

`DSInputBar` に表示用の `hasMarkedText` を持たせ、本文が空でも未確定文字列がある間は placeholder を表示しない。本文・カーソルの通知とは別の `DSInputSelectionDelivery` を使うため、選択範囲の同期が表示用の通知を取り消すことはない。`updateUIView` とネイティブ編集通知の両方で状態を同期し、未確定本文の保護と保存タイミングは維持する。

### 実行中に修正した検証側の問題

- メソッド名での絞り込みは0件だった。成功扱いにせず、`DesignSnapshotRenderTests` 全体を対象に変更した。
- 最初の描画はウィンドウが scene に接続されておらず黒い画像だった。scene 接続と実描画の成否検査を追加した。
- `Data == Data` の失敗表示で Swift Testing の差分計算が大量のメモリを消費した。`sample` で Testing の Myers 差分処理を確認し、今回のテストホストだけを停止した。比較は同じ完全一致判定の `elementsEqual` に変更した。
- テスト用 Draft が変更を画面に通知できるよう `@Observable` にした。入れ子の private 型ではマクロ生成コードがビルドエラーになったため、テスト内の型を internal にした。
- 全画面の比較には送信ボタンのアニメーションが混じることを差分座標で確認した。検査対象の文字領域だけを描画して比較する。
- 元の作業ツリーで別の管理ビルドが稼働していたため、その処理を止めず検証用 worktree に分離した。XcodeGen は既存の `/opt/homebrew/bin/xcodegen` を使用した。

- 追加の再実行で、ビルド済みファイルとインストール済みファイルの SHA-256 が一致するのに、実行結果が以前のソースの行番号・比較式を示す状態を観測した。今回専用端末の検証アプリを削除して再インストールしたところ、現在の描画範囲・比較式で実行された。古い実行コードが選ばれた内部原因までは断定しない。

### 現在の検証結果

- iOS 26.2 / iPhone 17 専用シミュレーターで `DesignSnapshotRenderTests` **23件 pass / exit 0**（`fresh-host.log`）。新しい2テストに加え、既存の写真選択・フォーカス・画像マーカー・カーソル・未確定入力保護のテストを含む。大規模な画面カタログの書き出しは実行していない。
- `snapshots-fresh/ime-{empty,marked,cancelled,committed,deleted}.png` を出力。空欄・変換中・取り消し後・確定後の画像を目視し、変換中に placeholder と文字が重ならないことを確認した。全削除後の再表示も描画比較テストで確認した。
- 残るログ: `Unbalanced calls to begin/end appearance transitions`、シミュレーターの `hapticpatternlibrary.plist` 不在、起動計測 CA Event の送信失敗。テスト失敗とは区別する。物理端末でのキーボード入力は未検証。XCUITest は実行していない。
- PhloxKit 全体の `swift test` は XCTest **400件**と Swift Testing **668件**が pass / exit 0（`packages.log`）。iOS 専用 UIKit コードの検証は上記のホスト付きテストが担当する。
- iOS のビルド・リンク成功、`PhloxMobile` の `xcodebuild analyze` 成功 / exit 0（`analyze.log`）。独立した型チェック入口はなく、コンパイラー検査をビルドで実施した。
- 既存の `ios/scripts/lint-raw-values.sh` と `git diff --check` は exit 0。新しい検査ツールは導入していない。

検証用 worktree は `/Users/ryosuke/Projects/Phlox-oss-worktrees/ios-ime-placeholder-20261025` を使用した。元の作業ツリーと変更した3ファイルの内容一致を確認し、再現用差分・ログ・画像・最終テスト結果を元の作業ツリーの `.verification/ios-ime-placeholder-20261025/verified/` に保存した。検証端末は所有する UDID を指定して shutdown 済み。検証用 worktree の管理ビルドは finish 済み。

当初は自動承認審査の拒否と別の管理ビルドのロックにより、検証用 worktree と初回ビルド出力を保持した。ユーザーの「再開して」を受け、元の作業場所に修正3ファイルが一致して残っていることと、検証用コピーが未使用であることを再確認した。重複する検証物・ビルド・初回エラー結果はゴミ箱へ移し、公式の `gitflow-cleanup.sh` で検証用 worktree とブランチを削除した。今回作成した専用シミュレーターも削除済み。最終検証記録と元の未コミット修正は保持する。
