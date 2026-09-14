---
status: partial
---

実行コミット: `6617556f7fab4d6a715b4b92a6b5bb6765593661`。

## ビルド・隔離

- `xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build-t45 -destination platform=macOS build` : `** BUILD SUCCEEDED **`。ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t45.log`
- Debug 実行ファイル: `/private/tmp/phlox-t13-visual.SPfR9c/Build-t45/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox`
- PID: 明色観測 `26197`、暗色観測 `33378`、明色 rename 試行 `40106`、明色再起動 `48311`。各 PID は `kill -TERM` 後に終了し、最終 `pgrep` は空。
- suite: `com.phlox.t45.phlox-light.observe.26100`、`com.phlox.t45.dracula.observe.26100`、`com.phlox.t45.phlox-light.rename.26100`、`com.phlox.t45.phlox-light.restart.26100`。すべて `defaults delete` 済み。
- DATA: `/tmp/phlox-t13-visual.SPfR9c/data-t45-{phlox-light-observe,dracula-observe,phlox-light-rename}-26100`。起動環境は `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON=/tmp/phlox-t13-visual.SPfR9c/agents-t45.json`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`。
- Release `com.phlox.Phlox` export md5 は開始・各終了・最終とも `4f3a1bf83e661df122d4d79cda27bf4d`。PID 61465 (`/Applications/Phlox.app`) は生存・未接触。
- 直後の子プロセスは `claude --bare -p /model --output-format json`（モデルカタログ照会、数秒後終了）と `/bin/cat` 7 件。以後は `/bin/cat` のみ、全チェックで `BILLING_HITS=0`。

## fixture

同一 project `UI検証A`、workspace は各 DATA 配下。task-44 の四フィールドは `name`、`titleSource`、`flowerName`、`fullDerivedTitle`。

| 名前・ID | 四フィールド | 階層 / backend |
|---|---|---|
| ログイン画面を修正 `A111…` | derived / Rose / ログイン画面を修正 | ルート、appServer、PATH 不在 `ui-chat-probe` |
| 通知の重複を修正 `A222…` | manual / Lily / nil | root の子、`ui01-probe`、`/bin/cat` |
| 長い日本語（76字）`A333…` | manual / Tulip / nil | A222 の子 |
| 長い英数字（64字）`A444…` | manual / Daisy / nil | A333 の子（深さ3） |
| 空名 `A555…` | manual / Violet / nil | root の子、表示は短縮 ID `#A55555` |
| Rose（花名と同じ手動名）`A666…` | manual / Rose / nil | root の子 |
| 文字の読みやすさ `A777…` | メタ情報なし（旧データ） | root の子 |
| 閉じる確認用 `A888…` | manual / Iris / nil | root の子 |

## 必須表示条件の観測

| 位置 | 明色 / 暗色 | 状態 | 幅 | 観測 |
|---|---|---|---|---|
| サイドバー（階層・時刻・状態） | 両方 | 通常・選択・エラー | 1440pt | PNG・AXあり。暗色では3段展開を AX click 3回で確認。長名は画面上 `…`、AXValue は全文。 |
| グリッド | 両方 | 通常 | 1440pt / 1024pt / 900pt | PNG・AXあり。1024pt 実測。720pt 要求は最小幅900ptで拒まれ、240ptペイン実測は未達。 |
| 単体 PTY topbar | 両方 | 通常 | 1440pt | PNG・AXあり。`/bin/cat` 子孫のみ。 |
| 単体チャット topbar | 両方 | エラー | 1440pt | PNG・AXあり。`customBinaryNotFound` プレースホルダ、送信なし。 |
| チーム名前領域 | 両方 | 通常 | 1440pt | PNG・AXあり。`シングルビューで開く` の AXPress は成功。 |
| 補助花名の個別 AX Text | 両方 | 上記 | 上記 | PNG 上では主名の右に表示。AX dump は主名の help 内 `花名:` を返したが、補助花名単独の Text を返さず、個別 AX / コントラストは未検証。 |

サイドバー AX 原文（暗色・`通知の重複を修正`選択）:

```
NAME role=AXStaticText title='' desc='通知の重複を修正' value='通知の重複を修正' ident= help=通知の重複を修正
花名: Lily
作業場所: /tmp/phlox-t13-visual.SPfR9c/data-t45-dracula-observe-26100/workspace focused=None selected=None pos=1297.0, 366.0 size=96.5, 16.0
NAME role=AXStaticText title='' desc='5日' value='現在の会話' ident= help=/tmp/phlox-t13-visual.SPfR9c/data-t45-dracula-observe-26100/workspace focused=None selected=None pos=1350.0, 485.5 size=16.0, 13.0
```

長い日本語の AXValue（同 run）:

```
NAME role=AXStaticText title='' desc='これは四十文字を超える長い日本語の作業名で省略と補助花名の表示を確認するための名前です' value='これは四十文字を超える長い日本語の作業名で省略と補助花名の表示を確認するための名前です' ident= help=/tmp/phlox-t13-visual.SPfR9c/data-t45-dracula-observe-26100/workspace focused=None selected=None pos=1264.0, 512.0 size=60.5, 16.0
```

チャット復元失敗 AX 原文:

```
NAME role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=1599.5, 435.0 size=414.0, 19.0
```

完全な AX 原文: `/tmp/phlox-t45-visual/run-26100/*-ax.log`。全名前の value、help、frame、選択状態は同ログに保存した。

## ピクセル実測コントラスト

PNG と AX frame から Pillow で fg/bg RGB、WCAG 相対輝度を計算した。主名は下表の実測範囲。補助花名は前節のとおり個別 AX frame が得られず未測定である。

| テーマ | 状態 | 主名 fg / bg（代表） | 主名比 | 補助花名比 |
|---|---|---|---:|---:|
| phlox-light | 通常 | `(29,29,29)` / `(246,246,246)` | 15.60–15.74 | 未測定 |
| phlox-light | 選択 | `(29,29,29)` / `(240,212,209)` | 12.08–15.74 | 未測定 |
| phlox-light | 注意 | `(29,29,29)` / `(246,246,246)` | 15.60–15.74 | 未測定 |
| dracula | 通常 | `(248,248,248)` / `(42,42,42)` | 13.52 | 未測定 |
| dracula | 選択 | `(248,248,248)` / `(83,60,58)` | 9.53–13.52 | 未測定 |
| dracula | 注意 | `(248,248,248)` / `(42,42,42)` | 13.52 | 未測定 |

実測の全 ROW（RGB、crop、AX frame、pass45）は `/tmp/phlox-t45-visual/run-26100/{phlox-light-rename,dracula-observe}-ax.log`。補助花名の実測欠落によりコントラスト条件全体は未検証。

## 操作・rename・再起動

- 選択: AX click 成功。展開: 暗色で3回の own-window AX click が成功。閉じる: `AXPress err=0`、`ident=xmark`。チーム→単体: `AXPress` 成功。
- drag: 対象名の AX action 一覧を取得したが、実 drag action は提供されず未実施。
- rename: `名前を変更` は `NOTFOUND`。続く `AX set value` は rename field ではなく `AXTextArea`（composer）を変更し、`AXConfirm err=-25206`。通常名・同花名・空欄の UI rename は未実施であり、反映・保持も未検証。
- 再起動: 同一隔離 DATA を再起動し、元の主名・花名・`#A55555` を PNG/AX で確認した。実 rename が成立していないため、rename 後の保存保持ではない。

## PNG 一覧

ルート: `/tmp/phlox-t45-visual/run-26100/`。すべて PNG 名に対象、テーマ、PID を含む。`normalw` は1440pt、`w1024` は1024pt、`w900` と `pane240-attempt` は実測900pt。

| PID / テーマ | PNG 対象 |
|---|---|
| 26197 / phlox-light | sidebar `{selected,normal,attention-selected,attention-unselected,longjp,longen,empty,sameflower}`、topbar `{pty,chat}`、grid `{normal,w1024,w900,pane240-attempt,after-close}`、team `{normal,to-single}` |
| 33378 / dracula | sidebar `{selected,normal,attention-selected,attention-unselected,longjp,longen,empty,sameflower}`、topbar `{pty,chat}`、grid `{normal,w1024,w900,pane240-attempt,after-close}`、team `{normal,to-single}` |
| 40106 / phlox-light rename run | 上記明色セット、`rename-{normal,same-flower,empty,grid-reflect,team-reflect}` |
| 48311 / phlox-light restart | `restart-{sidebar-normal,pty-topbar,empty,grid,team}` |

各実ファイル名は `t45-<theme>-<target>-pid<PID>.png`。例: `/tmp/phlox-t45-visual/run-26100/t45-dracula-sidebar-normalw-longjp-pid33378.png`（2880x1600px、1440pt）、`/tmp/phlox-t45-visual/run-26100/t45-dracula-grid-w1024-pid33378.png`（2048x1600px、1024pt）。

## 未達

- 240ptのグリッドペイン: ウィンドウ720pt指定後も実幅900pt。240ptを実測できず。
- 補助花名の独立 AX Text / AXValue・個別 pixel contrast。
- UI rename 3条件、rename 後の各表示位置反映・永続化。
- drag 実操作。


## PM 判定 r1（2026-09-14、PNG 61 枚のうち主要 7 枚を PM が閲覧）

判定: **needs_changes**（グリッド狭幅で主名が消える）。

不合格の根拠:
- `t45-phlox-light-grid-w900-pid26197.png` と `t45-dracula-grid-pane240-attempt-pid33378.png`（ウィンドウ実幅 900pt、4 列でペイン実幅およそ 150〜190pt）で、グリッドのタイル見出しに**セッション名が 1 文字も表示されない**。状態ドット・状態ラベル（入力待ち／エラー）・エージェントアイコン・閉じるボタンは残っており、主名だけが押し出されている。明色・暗色の両方で再現。
- 契約「### 4. PM の課金なし目視ゲート → 独立した合否条件」の「主名を優先して省略し、補助花名・時刻・状態・アイコンが主名や操作を押し出さない」に反する。必須の幅の軸に 240pt のグリッドペインが含まれており、狭幅は対象範囲内。
- 原因の当たり: `PaneLayoutView.swift` の `header` は `StatusLabel`・`AgentSessionIcon(size: 24)`・補助花名・`workspaceName`・閉じるボタンが固有幅を持ち、主名の `layoutPriority(1)` だけでは幅を確保できない。

合格だった観測:
- サイドバー（明暗・通常／選択／注意・ルート＋3 段の階層・時刻・状態）: 主名が作業名、補助花名が右に小さく続き、長名は末尾省略。`ログイン画面を修正` / `通知の重複を修正` / `これは四十文…` / `ABCD…` / `#A55555` / `Rose`（空名は短縮 ID）まで所定の 6 種を確認。
- 単体トップバー（PTY・チャット、明暗）: 左に作業名、中央に花名。重なり・切れなし。
- グリッド通常幅（1440pt）・1024pt: タイル見出しに作業名が主、花名が補助。
- チーム名前領域と「シングルビューで開く」到達。

未検証（再撮影で埋める）:
- 補助花名単独の AX 要素が取得できず、補助花名のコントラスト実測が未了（主名のみ実測、明色 選択で 12.08〜15.74 等）。
- UI からの rename 3 種（通常・花名と同一・空欄）が未実施（`名前を変更` の AX 要素が見つからず、`AX set value` が composer を掴んだ）。保存後の再起動保持も rename 成立を前提とするため未確認。
- 240pt ペインの実測（ウィンドウ最小幅 900pt のため未達）。

PM 目視ゲートは PM が PNG を確認して判定する。

=== REPORT COMPLETE ===
