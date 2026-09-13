---
status: partial
---

# UI-07（task-27）/ UI-06（task-35）チャット入力欄（composer）実画面観測

製品コード・テスト・契約・台帳は未変更。成果は PNG・AX ログ・本報告。合否は PM が判定する。隔離 Debug のみ操作。System Events は `first process whose unix id is <自PID>`。key code / keystroke 未使用。課金 CLI（claude / codex / cursor）未起動。「新しいチャット」等の作成メニューは未操作。Release Phlox（PID 61465）未接触。設定内でテーマ・トグル・値は変更していない。

PM 目視ゲートは PM が PNG を確認して判定する。

## ビルド

- コマンド: `cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build > /tmp/phlox-t13-visual.SPfR9c/build-t2735.log 2>&1`
- ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t2735.log`
- 末尾: `** BUILD SUCCEEDED **`
- 指示時点の作業ツリー HEAD: `3921d9c`。再ビルド後・本報告 PNG を撮ったラン実行時 HEAD: `35ec6b5`（途中で `ba06a36` task-34 行余白、台帳コミットが載った）。バイナリは撮影前の 1 回の xcodebuild 成果。
- ハーネス: `/tmp/phlox-t13-visual.SPfR9c/shoot-t2735.sh`、`/tmp/phlox-t13-visual.SPfR9c/ax-t2735.py`、`$B/axclick.py`、`$B/axwalk.py`、`$B/dump-t38.applescript`、`$B/dump-t38-toolbar.applescript`
- 起動 env: `PHLOX_DATA_DIR` / `PHLOX_DEFAULTS_SUITE` / `PHLOX_AGENTS_JSON=$B/agents-t2735.json` / `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`（Keychain ダイアログ回避。t38/t39 流儀）
- 起動 args: `-AppleLanguages "(ja)"` `-AppleLocale ja` `-phlox.appLanguage ja` `-ApplePersistenceIgnoreState YES` `-phlox.theme <theme>`
- データ: `$B/data-t33-v4` を `$B/data-t2735-<theme>` へコピー。`ports.json`・`messages.sqlite*` 削除。全 session から `pid` 削除。`ui-chat-probe`（`binaryName=phlox-chat-probe-nonexistent-binary`、PATH 不在）の appServer descriptor「入力欄の確認」を追加。

## 隔離

| 時点 | `com.phlox.Phlox` md5 | Release `phlox.theme` | Release PID |
|---|---|---|---|
| 撮影前 | `abe1760b9e29c4afc58e8860ac27845f` | dracula | 61465 残存 |
| 各テーマ起動時 / 終了後 / 最終 | 同左（不変） | dracula | 61465 残存 |

Debug バイナリは各テーマ終了時 `kill -TERM` → pgrep 不在。suite は `defaults delete`。

## テーマごとの観測（本報告 PNG のラン）

入力欄 AX は 4 テーマとも同一論理 frame（ウィンドウ位置が同じため）: `ChatComposer.input`（AXScrollArea）`pos=677.5, 890.0 size=744.0, 36.0`。子 AXTextArea も同 frame。crop +24pt: `653.5,866.0,792.0,84.0`。グリッド時 `GridComposer.input` `pos=637.5, 884.0 size=365.5, 36.0`。

フォーカス: 親 ScrollArea の `AXFocused` は False のまま。子 AXTextArea へ `AXUIElementSetAttributeValue(AXFocused, true)` → `set-focused-err=0` `after_focused=True` `focus-result=ok`。System Events の `set focused of text area 1 of group 1 of window 1` は「正しくないインデックス」で失敗。文字入力はしていない。

「chat restore failed」AX 原文は 4 テーマとも:

```
MATCH role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 269.0 size=366.5, 16.0
```

### phlox-light

- Debug PID: 88457 / suite: `com.phlox.t2735.phlox-light.88353`
- 子孫プロセス列挙原文:

```
=== descendants pgrep -P 88457 ===
(none)
=== descendants process group pgid=88457 ===
  PID  PPID COMMAND
88457     1 /private/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox -AppleLanguages (ja) -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme phlox-light
BILLING_HITS=0
```

- 入力欄 AX frame: `677.5,890.0,744.0,36.0` ident=`ChatComposer.input`
- focused: 子 AXTextArea `after_focused=True`。親 ScrollArea 再取得 `focused=False`
- PNG: 下表

### github-light

- Debug PID: 89626 / suite: `com.phlox.t2735.github-light.88353`
- 子孫プロセス列挙原文:

```
=== descendants pgrep -P 89626 ===
(none)
=== descendants process group pgid=89626 ===
  PID  PPID COMMAND
89626     1 /private/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox -AppleLanguages (ja) -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme github-light
BILLING_HITS=0
```

- 入力欄 AX frame: 同上
- focused: 子 AXTextArea `after_focused=True`。親 ScrollArea 再取得 `focused=False`
- 設定: help「設定」click → タブ title「外観」AXPress（ident `settings-group-appearance` は NOTFOUND）。GitHub Light 行 `desc='GitHub Light' selected=True pos=672.0, 594.5 size=460.0, 102.0`（スクロール後）。値は変更していない。

### solarized-light

- Debug PID: 91662 / suite: `com.phlox.t2735.solarized-light.88353`
- 子孫プロセス列挙原文:

```
=== descendants pgrep -P 91662 ===
(none)
=== descendants process group pgid=91662 ===
  PID  PPID COMMAND
91662     1 /private/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox -AppleLanguages (ja) -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme solarized-light
BILLING_HITS=0
```

- 入力欄 AX frame: 同上
- focused: 子 AXTextArea `after_focused=True`。親 ScrollArea 再取得 `focused=False`

### dracula

- Debug PID: 92799 / suite: `com.phlox.t2735.dracula.88353`
- 子孫プロセス列挙原文:

```
=== descendants pgrep -P 92799 ===
(none)
=== descendants process group pgid=92799 ===
  PID  PPID COMMAND
92799     1 /private/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox -AppleLanguages (ja) -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme dracula
BILLING_HITS=0
```

- 入力欄 AX frame: 同上
- focused: 子 AXTextArea `after_focused=True`。親 ScrollArea 再取得 `focused=False`
- 設定: 外観タブへ title click。Dracula 行 `desc='Dracula' selected=True pos=672.0, 626.0 size=460.0, 102.0`。値は変更していない。

## PNG 一覧

| 対象 | ファイル | 寸法（px） | PID |
|---|---|---|---|
| 単体・窓全体 | `/tmp/phlox-t13-visual.SPfR9c/t2735-phlox-light-single.png` | 2412x1580 | 88457 |
| 入力欄 crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-phlox-light-composer.png` | 1586x168 | 88457 |
| 入力欄 focused crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-phlox-light-composer-focused.png` | 1586x168 | 88457 |
| グリッド | `/tmp/phlox-t13-visual.SPfR9c/t2735-phlox-light-grid.png` | 2412x1580 | 88457 |
| 単体・窓全体 | `/tmp/phlox-t13-visual.SPfR9c/t2735-github-light-single.png` | 2412x1580 | 89626 |
| 入力欄 crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-github-light-composer.png` | 1586x168 | 89626 |
| 入力欄 focused crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-github-light-composer-focused.png` | 1586x168 | 89626 |
| グリッド | `/tmp/phlox-t13-visual.SPfR9c/t2735-github-light-grid.png` | 2412x1580 | 89626 |
| 設定・アプリ外観入力欄見本 | `/tmp/phlox-t13-visual.SPfR9c/t2735-github-light-settings-preview.png` | 416x222 | 89626 |
| 単体・窓全体 | `/tmp/phlox-t13-visual.SPfR9c/t2735-solarized-light-single.png` | 2412x1580 | 91662 |
| 入力欄 crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-solarized-light-composer.png` | 1586x168 | 91662 |
| 入力欄 focused crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-solarized-light-composer-focused.png` | 1586x168 | 91662 |
| グリッド | `/tmp/phlox-t13-visual.SPfR9c/t2735-solarized-light-grid.png` | 2412x1580 | 91662 |
| 単体・窓全体 | `/tmp/phlox-t13-visual.SPfR9c/t2735-dracula-single.png` | 2412x1580 | 92799 |
| 入力欄 crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-dracula-composer.png` | 1586x168 | 92799 |
| 入力欄 focused crop | `/tmp/phlox-t13-visual.SPfR9c/t2735-dracula-composer-focused.png` | 1586x168 | 92799 |
| グリッド | `/tmp/phlox-t13-visual.SPfR9c/t2735-dracula-grid.png` | 2412x1580 | 92799 |
| 設定・アプリ外観入力欄見本 | `/tmp/phlox-t13-visual.SPfR9c/t2735-dracula-settings-preview.png` | 416x220 | 92799 |

AX ログ: `/tmp/phlox-t13-visual.SPfR9c/t2735-<theme>-ax.log` / `t2735-<theme>-obs.log`

スクショ上の入力欄（crop）はプレースホルダ「Ask Phlox anything...」と枠が見える。グリッドでは「入力欄の確認」タイル下部に「メッセージを入力」。設定見本は「メッセージを入力」行。caret の有無は crop からは判別しにくい。合否は PNG の目視。

## できなかった手順と理由

- System Events `set focused of text area 1 of group 1 of window 1`（および text field 1）: 直下に該当要素がなく「正しくないインデックス」。代替として同一 PID の AX `AXFocused=true` を子 AXTextArea に設定し `after_focused=True` を記録した。親 `ChatComposer.input`（AXScrollArea）の AXFocused 再取得は False。
- 設定タブ ident `settings-group-appearance`: NOTFOUND。title「外観」の AXPress で外観タブへ到達した。
- 設定見本の AX ラベル「アプリ外観」「メッセージを入力」等: ThemeAppPreview が `accessibilityHidden` のため ABSENT。見本はテーマ行ボタン frame の左（アプリ外観）を `-R` で切った。
- 作業ツリー HEAD は指示の `3921d9c` から撮影ラン時 `35ec6b5` へ進んだ（本エージェントは製品コードを変更していない）。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定（2026-09-13、PNG を目視）

- 課金セッションは起動していない（子孫プロセス 0 件・BILLING_HITS=0 を 4 テーマで確認）。ユーザー承認の課金枠は未使用。
- **UI-07（task-27）枠の可視性: pass。** phlox-light / github-light / solarized-light の単体入力欄 crop で、明色の面に対し暗いグレーの 1px 枠が明瞭。dracula も暗色面に対して枠が判別できる。グリッド（GridChatColumn）の入力欄も枠が見える（github-light）。
- **UI-07 フォーカスの可視性: この観測では判別不能。** `composer-focused` crop は非フォーカス crop と見分けがつかない（TextEditor の caret は点滅位相により未捕捉、フォーカスリングは描かれない）。AXFocused=true は記録されたが画像上の根拠がないため「未検証」とし、caret を捕らえる連写（0.2s 間隔 ×6）の再観測を task-34 実装完了後に行う。
- **UI-06（task-35）見本と実画面の対応: pass。** GitHub Light の見本（アプリ外観: 本文の見本／現在の会話／メッセージを入力）は実画面の明色面＋暗い枠の入力欄と対応し、Dracula の見本は暗色面＋控えめな枠の入力欄と対応する。ターミナル配色の色帯は別枠で用途が区別されている。
- 副次観測（新規指摘ではなく既知）: 単体の入力欄プレースホルダは英語「Ask Phlox anything...」、グリッドは日本語「メッセージを入力」で不一致（UX-10 の対象）。

=== REPORT COMPLETE ===
