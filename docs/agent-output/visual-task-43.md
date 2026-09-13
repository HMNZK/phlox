---
task: task-43
status: partial
---

# UX-03（task-43）PM 目視ゲート — 入力先ラベル実画面観測

製品コード・テスト・契約・台帳は未変更。成果は PNG・AX ログ・本報告。合否は PM が判定する。隔離 Debug のみ操作。System Events は `first process whose unix id is <自PID>`。key code / keystroke 未使用。送信・再試行・セッション作成・討論開始なし。Release Phlox（PID 61465、`/Applications/Phlox.app`）未接触。

PM 目視ゲートは PM が PNG を確認して判定する。

## 環境

- 観測時 HEAD: `e893b7b`（`台帳: task-43 統合待ち`）。グリッド通常幅 PNG（`grid-tiles-phlox-light.png`）のみ起動時 HEAD `6850384`。いずれも指示どおり製品変更はコミット済みの Debug バイナリ `/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app`。
- ハーネス: `/tmp/phlox-t13-visual.SPfR9c/shoot-t43.sh` / `shoot-t43c.sh` / `continue-t43.sh` / `shoot-t43-dracula.sh`、`dest-t43.py`、`ax-t2735.py`、`axclick.py`、`agents-t2735.json`。データは `data-t33-v4` をコピーし sessions/projects を置換。
- 起動 env: `PHLOX_DATA_DIR` / `PHLOX_DEFAULTS_SUITE` / `PHLOX_AGENTS_JSON` / `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`
- 起動 args: `-AppleLanguages "(ja)" -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme <theme>`
- プレースホルダ: `PHLOX_AGENTS_JSON` の custom kind `ui-chat-probe`（`binaryName=phlox-chat-probe-nonexistent-binary`、PATH 不在）。descriptor は `kind {type: custom, id: ui-chat-probe}`、`backend: appServer`、`pid` キー無し。

## データ構成（sessions.json の要点）

隔離データ（phlox-light 本番観測: `/tmp/phlox-t13-visual.SPfR9c/data-t43c-phlox-light/`）:

プロジェクト 2 件:

- `Phlox` id `6DAD6CF8-DAEA-43E0-B8BF-8AD51F8D22AD`、wd `workspace-phlox`
- `Garden-with-a-very-long-project-name-to-observe-label-ellipsis` id `F947E9CE-F25E-43F9-AAD6-6B9A266EA1F7`、wd `workspace-garden`

プレースホルダ 3 体（すべて `ui-chat-probe` / `appServer` / pid 無し）:

- 親 `全体作業` id `6AE8CBAA-F2F6-4C4B-86D8-2BD785B1F355`、projectID=Phlox、`parentSessionID` 無し
- 子 A `入力欄改善` id `2C8F0CE7-C6A0-41CA-A026-81A3D169B8AC`、projectID=Garden 長名、`parentSessionID`=親
- 子 B `調査` id `E7B89EC0-45AB-4809-B448-BA31225AC20C`、projectID=Garden 長名、`parentSessionID`=親

dracula は同型の別 UUID（`data-t43d-dracula`）。

## 隔離

| 時点 | `com.phlox.Phlox` md5 | Release `phlox.theme` | Release PID |
|---|---|---|---|
| 観測前 | `68c936d91bd3069fa4b52fe61e19c690` | dracula | 61465 残存 |
| 各テーマ終了 / 最終 | 同左（不変） | dracula | 61465 残存 |

指示文の期待値 `abe1760b9e29c4afc58e8860ac27845f` とは観測開始時点で既に不一致。本観測中は Release defaults に書いておらず、上記 md5 は終了まで不変。Debug suite は `defaults delete`。

## PID と子プロセス

起動直後の `pgrep -P <PID>` はいずれも 1 件。コマンドはモデルカタログ照会 `claude --bare -p /model --output-format json`（チャット送信ではない）。数秒で消滅。選択後・チーム切替後・終了前は 0 件。

| テーマ | Debug PID | 起動直後 `pgrep -P` | 選択後 |
|---|---|---|---|
| phlox-light（グリッド通常幅） | 1987 | 1993 上記カタログ | (none) |
| phlox-light（単一・チーム・狭幅） | 46697 | 46701 上記カタログ | (none) |
| dracula（単一） | 58235 | 58239 上記カタログ | (none) |

phlox-light 単一の起動直後原文:

```
=== descendants pgrep -P 46697 when=launch ===
46701
  PID  PPID COMMAND
46701 46697 /Users/ryosuke/.local/bin/claude --bare -p /model --output-format json
```

選択後原文:

```
=== descendants pgrep -P 46697 after-single ===
(none)
```

チーム切替後も `pgrep -P 46697` は空。討論は開始していない。Debug は各ラン `kill -TERM` 後 pgrep 不在。Release 61465 残存。

## PNG 一覧

論理窓は通常 1206×790（`screencapture -l` 2412×1580）。狭幅は 900×632（1800×1264）。

| パス | 対象 | 寸法（px） | テーマ |
|---|---|---|---|
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-A-phlox-light.png` | 単一・セッション A（入力欄改善） | 2412x1580 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-B-phlox-light.png` | 単一・セッション B（全体作業） | 2412x1580 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-A2-phlox-light.png` | 単一・A へ戻す | 2412x1580 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/grid-tiles-phlox-light.png` | グリッド・3 タイル | 2412x1580 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/grid-narrow-phlox-light.png` | グリッド・窓 900 幅 | 1800x1264 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/team-idle-phlox-light.png` | チーム・討論開始前 | 2412x1580 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-narrow-phlox-light.png` | 単一・窓 900 幅 | 1800x1264 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-nodesel-phlox-light.png` | 単一・セッション未選択 | 2412x1580 | phlox-light |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-A-dracula.png` | 単一・A | 2412x1580 | dracula |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-B-dracula.png` | 単一・B | 2412x1580 | dracula |
| `/tmp/phlox-t13-visual.SPfR9c/t43-gate/single-A2-dracula.png` | 単一・A へ戻す | 2412x1580 | dracula |

AX ログ: `/tmp/phlox-t13-visual.SPfR9c/t43-gate/phlox-light-ax.log`（グリッド通常幅）、`phlox-light-c-ax.log`（単一・チーム・狭幅）、`dracula-d-ax.log`。

## AX 原文（ラベル文言・frame・help）

ident は `ChatComposer.destination` / `GridComposer.destination` / `TeamComposer.destination`。help はいずれも AXValue と同一の全文。PNG 上の末尾 `…` は AXValue には出ない。

### 1. 単一 A→B→A（phlox-light、PID 46697）

A（入力欄改善）:

```
DEST D2 role=AXStaticText value='Garden-with-a-very-long-project-name-to-observe-label-ellipsis / 入力欄改善 — 送信不可（メッセージを入力してください）' ident=ChatComposer.destination help=Garden-with-a-very-long-project-name-to-observe-label-ellipsis / 入力欄改善 — 送信不可（メッセージを入力してください） pos=677.5, 873.0 size=563.0, 13.0
COMP ident=ChatComposer.input pos=677.5, 890.0 size=744.0, 36.0
PAIR gap_dest_to_input=4.0 dest_h=13.0 input_h=36.0 span_dest_top_to_input_bottom=53.0 overlap=NO_OVERLAP
```

B（全体作業）:

```
DEST value='Phlox / 全体作業 — 送信不可（メッセージを入力してください）' ident=ChatComposer.destination help=Phlox / 全体作業 — 送信不可（メッセージを入力してください） pos=677.5, 873.0 size=265.0, 13.0
```

A2（入力欄改善へ戻す）: A と同一の DEST value / ident / pos。前の `Phlox / 全体作業` は残らない。

### 2. グリッド（phlox-light、PID 1987、通常幅）

各タイル固有。選択カード名への置換なし。

```
DEST value='Phlox / 全体作業 — 送信不可（メッセージを入力してください）' ident=GridComposer.destination pos=637.5, 494.0 size=265.0, 13.0
COMP ident=GridComposer.input pos=637.5, 511.0 size=365.5, 36.0
DEST value='Garden-with-a-very-long-project-name-to-observe-label-ellipsis / 調査 — 送信不可（メッセージを入力してください）' ident=GridComposer.destination pos=637.5, 867.0 size=362.5, 13.0
COMP ident=GridComposer.input pos=637.5, 884.0 size=365.5, 36.0
DEST value='Garden-with-a-very-long-project-name-to-observe-label-ellipsis / 入力欄改善 — 送信不可（メッセージを入力してください）' ident=GridComposer.destination pos=1096.025, 867.0 size=361.0, 13.0
COMP ident=GridComposer.input pos=1096.0, 884.0 size=365.5, 36.0
```

いずれも gap=4.0、dest_h=13.0、input_h=36.0、NO_OVERLAP。PNG では長名タイルが視覚的に `…` 省略。

### 3. チーム・討論開始前（phlox-light、PID 46697、子 A 選択のまま切替、討論未開始）

```
DEST value='討論を開始 — 送信不可（メッセージを入力してください）' ident=TeamComposer.destination help=討論を開始 — 送信不可（メッセージを入力してください） pos=603.0, 920.0 size=239.0, 13.0
TEXT role=AXTextArea pos=603.0, 937.0 size=853.0, 33.0
```

### 4. 狭い幅（System Events `set size of window 1 to {900, 600}` → 実枠 900×632）

単一（入力欄改善、PID 46697）:

```
DEST value='Garden-with-a-very-long-project-name-to-observe-label-ellipsis / 入力欄改善 — 送信不可（メッセージを入力してください）' ident=ChatComposer.destination help=<同全文> pos=646.0, 719.0 size=493.5, 13.0
COMP ident=ChatComposer.input pos=646.0, 736.0 size=501.0, 36.0
```

PNG は末尾 `送信不可（メッセージを…`。AXValue/help は省略なし全文。

グリッド 900 幅（PID 32591）も 3 件とも全文 help、PNG は各タイルで `…`。

### 5. 宛先なし（セッション未選択、phlox-light、PID 1987）

プロジェクト行 `Phlox` をクリック。`ChatComposer.destination` / `TeamComposer.destination` は dest_count=0。画面は開始カード（「エージェントを選んでセッションを開始」）。composer ラベル行は出ない。

### 6. 入力欄への重なり・高さ

単一・グリッドとも dest と input の gap=4.0pt、OVERLAP なし。dest_h=13.0（caption 1 行）、input_h=36.0（`ComposerHeightBounds.single.min` と同じ）。dest 上端から input 下端まで 53.0pt。task-40 ゲート A の `ChatComposer.input` は `pos=677.5, 890.0 size=744.0, 36.0` で、今回の input 座標・高さは同一。その直前に dest（y=873.0, h=13.0）が載っている。送信ボタン `ChatComposer.sendButton` pos=1404.5, 939.0。

dracula 単一 A/B/A2 の DEST/input frame は phlox-light 単一と同一（value も同一切替）。

## できなかった手順と理由

- 指示の Release md5 `abe1760b9e29c4afc58e8860ac27845f`: 観測開始時すでに `68c936d91bd3069fa4b52fe61e19c690`。Release defaults は書いていない。不変確認の対象はこの実測値。
- ウィンドウを 900 未満へ: アプリ `minWidth: 900`。`set size {720, 600}` は 900×632 のまま。`AXSize` への NSValue 設定は err=-25201。
- AXValue 自体の `…`: 省略は PNG のみ。help と AXValue は常に全文一致。
- 起動直後のサイドバー: プロジェクトが折りたたみ。`help=展開` の AXPress 後にセッション行が出る。初回ランは未展開のまま単一を撮り、セッション未到達（その PNG は `single-nodesel` として残した）。
- 未送信短文の入力・削除による「本文未入力」切替: 本観測では文字入力していない（送信もしない）。空のまま「— 送信不可（メッセージを入力してください）」を記録。
- 討論進行中・結論中・終了後の GUI: 討論開始ボタンを押していない。契約どおりモデル検査の範囲。
- `set size {1440, 800}`: 実枠は 1206×790 のまま（先行ゲートと同型）。狭幅方向の 900 は入った。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定（2026-09-13、Claude=PM が PNG を目視）

閲覧: `single-A-phlox-light.png`・`single-B-phlox-light.png`・`grid-tiles-phlox-light.png`・`team-idle-phlox-light.png`・`single-narrow-phlox-light.png`。

- 単一: 入力欄枠内の最上段（編集領域の直前）にキャプション色で「Garden-with-a-very-long-project-name-to-observe-label-ellipsis / 入力欄改善 — 送信不可（メッセージを入力してください）」。B へ切替で「Phlox / 全体作業 — …」に追随し、A へ戻すと元へ戻る（AX 原文と一致）。
- グリッド: 3 タイルそれぞれに自タイルのプロジェクト／作業名（Phlox / 全体作業、Garden… / 調査、Garden… / 入力欄…）。選択カード名の混入なし。狭いタイルでは末尾 `…` で省略、help は全文（AX）。
- チーム: 討論開始前は「討論を開始 — 送信不可（メッセージを入力してください）」。討論は開始していない。
- 幅 900: 単一のラベルが末尾 `…` で省略され、入力欄・送信ボタンと重ならない。composer 高さはキャプション 1 行分増（ADR 0046 の扱いは契約どおり採択済み）。
- **PM 目視ゲート: pass**。未観測: 本文入力後の「送信不可」理由の消え方（文字入力を行わない方針）、討論進行中・終了後（モデル検査の範囲）。
- Release 設定の md5: 観測担当が測った開始時点の値は gate A 記録（13:47）と異なるが、`~/Library/Preferences/com.phlox.Phlox.plist` の mtime は 14:24（稼働中の Release Phlox 自身の書き込みと整合。本 run のハーネスは全て隔離 suite・起動引数で、Release ドメインへの書込経路は無い）。PM が `phlox.theme`／`phlox.chat.fontScale` の値を再確認し変化なし。

=== REPORT COMPLETE ===
