---
task: task-40
status: completed
---

## 詰まった点

- r1 の「struct 単位で描画修飾を消す」はファイル全体削除より狭いが、契約 12 の要素単位には届かない。`.foregroundStyle` と `.padding` まで消すと、215 行だけ primary、361 行だけ primary、別ブロックへの `withinAnswer` padding、`DisclosureCard` 外側 padding 復活が残余から消える。
- `strip_prefix_calls` の `index(prefix)` は文字列・コメントを見ない。AX identifier を `"FileChange.showMoreButton.font(.body)"` に変えてもマスク後に元へ戻る。接続検査の `reachable_code` も文字列を先に隠す。
- 本番残余は、履歴ボタンの `HStack { ... }.font(...)`（trailing closure のあと）と Markdown コピーボタン周りの padding トークン化を要素マスクから外すと NG になる。製品は直さず、見出し要素の walk-back に `}` と HStack／VStack／Button を足し、padding は呼び出しを消さず引数だけ正規化した。

## できた風だが実は未完

- PM 目視ゲート A/B、App xcodebuild、`.claude/verify.sh` 全量は本手順の指定外。GUI は起動していない。
- 凍結テスト・契約・台帳は未改変。他担当の `tasks/frozen/staged/`、`DashboardFeature/Tests`、`SessionFeatureTests/Harness` には触っていない。
- 検証 worktree の commit `7320a8a` は本番ブランチには載せていない。PM が修理後 rb を本ブランチへ commit し、その短い SHA を `TASK40_RB_BASELINE` に設定する必要がある。

## 置いた前提

- `TASK40_BASELINE` / `baseline_commit` は `bdbf1d9`。
- 描画修飾の削除は接続表の要素（Text／Label／titleContent／header／HStack／VStack／Button 等）に付く `.font`／`.lineSpacing`／`.markdownMargin`／FontSize／FontWeight に限定する。padding 呼び出しは消さず、DSSpacing／TranscriptTypography／`.vertical, 2` の引数だけをプレースホルダ化する。
- 文字列リテラルとコメントは修飾削除の前にプレースホルダ化し、削除後に戻してから `normalize_code` で比較する。
- transcript で新規に足してよい gap／withinAnswer／betweenAnswers padding は、`transcriptBlock`／Compacting／Thinking／loadEarlier に続く 1 箇所ずつだけ残余から除く。外側 inset のトークン化も同様。それ以外の直接 padding は数えて残す。
- 凍結 Swift 受け入れテストと `tasks/frozen/staged/` は未改変。テスト新規作成なし。

## 契約からの逸脱

なし。指摘 1・2 はハーネス欠陥として rb を修理し、製品コードは変更していない。

## レビュー重点

- struct 全体から `.padding`／`.foregroundStyle` を消していないか。215 行だけ・361 行だけ・別ブロック `withinAnswer`・`DisclosureCard` 外側 padding 4 が専用検査または残余で落ちるか。
- AX identifier／help／コピー文字列を隠す前に凍結 blob と比較しているか。identifier に `.font(.body)` を足しても検出するか。
- 履歴ボタンの HStack trailing closure 後 `.font` と Markdown 内 padding トークン化が、許可面として残余一致するか。
- 本番経路が作業ツリーの rb を `TASK40_RB_BASELINE` blob と比較しているか。

## rb 修理の内容

### r1（前回）

- ファイル全体の `strip_draw_attribute_modifiers` をやめ、接続表の View 範囲へ移した。
- `TASK40_RB_BASELINE` は作業ツリーと承認 SHA の blob 比較。未設定・HEAD・ブランチ名は拒否。
- 負例: エラー色→primary（当時は全置換）、gap padding 複製、範囲外 `.font`、rb 作業ツリー改変。

### r2（今回）

指摘 1: マスクを要素の描画修飾呼び出し単位に限定。意味色は要素対応（ErrorMessageCell 見出し 215・背景 226・枠線 229、差分見出し 361 とヘルパー内 diffAdded／diffRemoved、料金 opacity 0.7）。gap はブロックあたり 1 個、かつ `withinAnswer`／`metadataGap` 等の直接 padding が接続表以外に無いことを数え、余剰は残余から消さない。`DisclosureCard` の `.padding(4)`／`.padding(.all, 4)`／`DSSpacing.xxs` 外側を明示拒否。

指摘 2: 文字列・コメントを先に保護し、修飾削除のあと復元して比較。接続検査側は隠す前に AX identifier／help／コピー内容を凍結 blob と比較。

### 負例一覧

既存: 接続削除、誤った役割、子 View 上書き、旧直値、倍率二重適用、gap 二重加算、直前誤参照、先頭持ち越し、gap 倍率再適用、同一回答 24pt、コメントだけの参照、未使用ヘルパー、`if false`、必須ケース欠落、許可面以外の残余（コピー）、color primary 固定、差分行間 0、差分意味色、料金 opacity、エラー色、gap padding 複製、範囲外 `.font`、SHA／HEAD／祖先／凍結テスト／rb 自身、変更禁止対象。

追加: 215 行だけ primary 化、361 行だけ primary 化、withinAnswer padding を別ブロックに追加、DisclosureCard 外側 padding 復活、範囲外要素の `.font` 変更（既存維持）、identifier 文字列の改変、help 文字列の改変、コメント内の偽装。

## 製品変更

なし。`TASK40_BASELINE=bdbf1d9` と修理後 rb の SHA `7320a8a` で本番検査は製品側 NG なし。

## 検証原文

### `ruby .claude/scripts/task40-wiring.rb --selftest`

```
task40-wiring --selftest: OK
```

exit 0。

### 本番 rb GREEN（worktree SHA `7320a8a`）

```
task40-wiring: OK
```

exit 0。コマンド: `env TASK40_BASELINE=bdbf1d9 TASK40_RB_BASELINE=7320a8a ruby .claude/scripts/task40-wiring.rb`

worktree は `git worktree add --detach /tmp/t40rb-wt HEAD` → 修理後 rb をコピーして commit → 検査後 `git worktree remove --force /tmp/t40rb-wt`。

### `git diff --check`

出力なし、exit 0。

GUI は未起動。本ブランチへはコミットしていない。

=== REPORT COMPLETE ===
