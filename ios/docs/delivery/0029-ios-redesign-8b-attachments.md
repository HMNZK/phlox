# 段階8b 添付処理

## 計画と範囲

- 所有: 新規チャット・詳細の添付受理、画像準備のエラー、対応テスト、必要な共有 ImageAttachmentKit 入力検証。
- AC-6-17/18（specs/redesign-2026-10.md:205–206）を根拠に、不正な画像だけを拒否し、有効画像・既存画像・本文を保持する。現コードはバッチ全拒否であり、旧テスト期待からの仕様変更を明示して修正する。
- 選択順に検査し最初の失敗を表示する。20MB・80MB・4枚・各辺8000を維持し、入力時の寸法・読込検証と送信時の型別文言を揃える。元画像とプレビューのキャッシュ、本準備のスレッド分離は維持する。
- NewChatView/DSInputBar、詳細の承認・404・次へ、共通0020/0028は編集しない。コミット・マージ・pushしない。
- Makefile、project.yml、生値lint、現存CI（pagesのみ）を確認済み。担当指示によりビルド・テスト・シミュレーターは専任担当の統合後検証に委ね、ここではコード確認と git diff --check のみ行う。

## 所有と検証物

- セッション: ios-redesign-stage8b attachments / feature/ios-redesign-attachments。
- 一時検証物の出力先: 自worktree `.verification/ios-redesign-stage8b/`。本担当は検証プロセスを起動しない。

## 根拠・変更結果

- 修正: `NewChatViewModel.swift:360` と `SessionDetailViewModel.swift:293`。選択順で枚数・個別サイズ・合計サイズ・画像検査を行い、通った画像だけを採番する。拒否分は番号を消費せず、最初のエラーを後の成功や失敗で消さない。既存添付のID・元データ・キャッシュと本文を保持し、新規受理分のプレースホルダだけを追記する。
- 修正: `ImageAttachmentPreparer.swift:108`。既存の `checkedSource`（ImageIOメタデータ検査、キャッシュ無効）と112pxサムネイル生成をまとめたthrowing APIを公開。サイズ・寸法・破損を型で区別し、失敗を空プレビューへ変えて受理する経路を除いた。元のoptional `preview` APIは維持。フル解像度の追加デコードや送信用変換は入れていない。
- 修正: 新規 `NewChatViewModel.swift:470` と詳細 `SessionDetailViewModel.swift:1043` の送信準備catchで、型付きエラーの既存文言（A2/A4等）を保持し、未知のエラーだけA5へ落とす。本準備のdetached処理、詳細の送信前スナップショット照合、送信中の多重実行ガードは変更していない。
- 仕様根拠: AC-6-17/18、`ClaudeDesign/Errors.dc.html:176–184`、共有 `ImageAttachmentLimits.swift:5–8`（4枚、10進20MB/80MB）、共有 `ImageAttachmentPreparer.swift:30–32`（各辺8000）。旧task-10のバッチ全拒否テストコメントは存在したが、最新ACに対し「入っている画像＝既存画像だけ」とする明示決定は見つからなかった。承認済みのAC-6-18へ適合させる変更として、旧全拒否アサーションを個別拒否・本文/既存添付保持を検査するものへ更新した。
- 実画像確認（今回の再描画ではない）: 正本 `design-boards/ReplyAttachErrDim-428x926.png` と8a `snapshots/ReplyAttachErrSize-428x926-light-ios18.png` を開き、A4/A2の文言とエラー時の添付・本文表示を確認。静止画像はバッチ受理規則の根拠にはしていない。

## 回帰テスト（追加・更新、未実走）

- 新規 `AttachmentIntakeTests.swift`: 新規・詳細同期・詳細Pickerの3経路で、20MB超混在、破損混在、既存添付、選択順と最初の失敗、残枠超過、全不正、空選択、20MB/80MBちょうど、80MB超の選択、幅・高さ8000/8001を検査する。7関数×3経路。
- 詳細の復元入力では、合計超過分だけを除外して後続の小画像を受理する検査と、送信準備のA4・本文/添付保持・API未送信の検査を追加（2関数）。通常の新規入力は「4枚×各20MB」で80MB以内になるため、80MB超の4枚選択はA2、80MBちょうどからの5枚目はA1が先に成立する。A3の分岐は過大な元添付を復元した防御経路で検査する。
- 既存の全拒否テストを仕様に沿って更新し、既存添付ID・元データ・本文の保持を強化。ゼロ埋めだけの偽画像を使っていた採番・キャッシュのハーネスは有効PNGに置換。破損添付の送信防止テストは復元経路へ移して維持した。skip・テスト削除なし。

## 担当外の連携事項（未編集）

- `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Molecules/DSInputBar.swift:1210–1223`。`loadTransferable`失敗をboolへ集約し、`onAttachmentLoadFailure`→`onAddAttachments`の順で通知している。この後の非同期追加でA5がクリアされ、失敗位置も失われる。実際のPickerで「読込失敗＋読める画像」の最初の失敗を保持するには、composer担当で選択順の失敗情報を添付受理へ渡す連携が必要。担当ViewModelへ壊れたDataが渡る混在は今回対応済みだが、転送段階の失敗は別経路である。

追記（統合担当による解消）: 上の転送段階の問題は、Pickerの選択順の `Result<SendAttachment, Error>` を両画面の受理へ渡す接続に変更した。成功・失敗を別通知せず、最初の失敗と有効画像を保持する。変更根拠と追加回帰テスト・未実走範囲は `0029-ios-redesign-8b-integration.md` の「追加結果」を参照。

## 検証範囲

- コード・呼び出し元・差分を確認し、`git diff --check`はexit 0。新規追加2ファイルも`git diff --no-index --check`で空白警告なし（追加差分があるため各exit 1、出力なし）。
- ユーザー指定どおり、ビルド・型チェック・lint・テスト・シミュレーター再描画は未実走。追加テストのコンパイルと実行結果は専任検証担当による統合後確認が必要。
- コミット・マージ・pushなし。生成プロジェクト、`.env*`、別担当の所有ファイルは変更していない。一時検証プロセス・使い捨て成果物は作っていない。

## 変更ファイル

- `ios/Packages/PhloxKit/Sources/Features/NewChat/NewChatViewModel.swift`
- `ios/Packages/PhloxKit/Sources/Features/SessionDetail/SessionDetailViewModel.swift`
- `macos/Packages/AgentDomain/Sources/ImageAttachmentKit/ImageAttachmentPreparer.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/AttachmentIntakeTests.swift`（追加）
- `ios/Packages/PhloxKit/Tests/FeaturesTests/NewChatViewModelTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/SessionAttachmentNumberingWhiteboxTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/SessionAttachmentPreviewTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/SessionDetailViewModelTests.swift`
- `ios/Packages/PhloxKit/Tests/FeaturesTests/SubAgentAndAttachmentAcceptanceTests.swift`
- 本作業記録（追加）
