---
status: partial
task: task-37
---

# UX-12b（task-37）実画面観測記録

製品コード・テスト・契約・台帳は未変更。隔離 Debug のみ操作。System Events は `first process whose unix id is <自PID>`。key code / keystroke は未使用。設定の保存・削除・CLI 実行・再読み込み・Finder は未操作（閲覧と DisclosureGroup の開閉のみ）。課金セッションは未作成。Release Phlox（PID 61465）には未接触。

PM 目視ゲートは PM が PNG を確認して判定する。

## ビルド

- コマンド: `cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build > /tmp/phlox-t13-visual.SPfR9c/build-t37b.log 2>&1`
- ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t37b.log`
- 末尾: `** BUILD SUCCEEDED **`

## PID / suite

| 実行 | Debug PID | suite | 備考 |
|---|---|---|---|
| v3（本流・SHOT/AX 完走） | 97197 | `com.phlox.t37.v3.97171` | フルパス AXPress。Release 未変化 |
| probe / probe2 | 89303 / 95128 | `com.phlox.t37.probe.*` | 構造列挙のみ |
| v1–v2 | 81882 / 87254 | `com.phlox.t37.vN.$$` | ウィンドウは開いたが AX がプロセス名 `Phlox` に解決。SHOT は初期 Claude のみ |

起動: `-AppleLanguages "(ja)"` `-AppleLocale ja` `-phlox.appLanguage ja`。データは `$B/data-t33-v4` を `$B/data-t37-v3` へコピー。`PHLOX_AGENTS_JSON=$B/agents-t30.json`。

終了: 自 PID のみ `kill -TERM`。Debug バイナリの pgrep 不在。suite は `defaults delete`。Release 61465 `/Applications/Phlox.app/Contents/MacOS/Phlox` は残存。

## ウィンドウ一覧（v3、コンソールオープン後）

AX:

```
idx=1 name=エージェント管理 pos=306, 191 size=900, 632
idx=2 name=Phlox (Debug) pos=306, 192 size=900, 632
```

Quartz: 管理 `id=43409` bounds `X=306 Y=191 Width=900 Height=632`。メイン `id=43402` 同寸法で 1pt 下。初期サイズは defaultSize 900×620 にタイトルバー分が乗った 900×632。

## 隔離確認

| 時点 | `com.phlox.Phlox` md5 |
|---|---|
| before | `abe1760b9e29c4afc58e8860ac27845f` |
| after-launch | 同左 |
| after-kill | 同左 |

Release 61465 は全実行で残存。Debug 起動前後で md5 不変。

## AX 原文（v3 PID 97197）

全文: `/tmp/phlox-t13-visual.SPfR9c/t37-v3-obs.log` `/tmp/phlox-t13-visual.SPfR9c/t37-v3-ax.log`

### 管理ウィンドウ depth 1

```
window name=エージェント管理 size=900, 632
n1=5
D1[1] role=AXGroup title=missing value value=missing value desc=グループ
D1[2] role=AXButton title=missing value value=missing value desc=閉じるボタン
D1[3] role=AXButton title=missing value value=missing value desc=拡大/縮小ボタン
D1[4] role=AXButton title=missing value value=missing value desc=しまうボタン
D1[5] role=AXStaticText title=missing value value=エージェント管理 desc=テキスト
```

group 1 の子（probe）: `AXScrollArea`（サイドバー n=29）、見出し static「状態」、toolbar ボタン 2（help=「設定ファイルを Finder で表示」「再読み込み」、未クリック）、subtitle static、`AXScrollArea`（本文）。

### サイドバー行（title）

ボタンの AX title / 子 static は空。見出し static と PNG で対応:

| AX index | グループ見出し（static value） | PNG の行 title / detail | 操作 |
|---|---|---|---|
| SB[5] | Claude Code | （グループ） | — |
| SB[6] | — | 状態 /status（初期選択） | 未クリック |
| SB[15] | Codex | （グループ） | — |
| SB[16] | — | 状態 / config.toml | AXPress |
| SB[23] | Cursor | （グループ） | — |
| SB[24] | — | 状態 / cli-config.json | スクロール後 AXPress |

SB[6]/[16]/[24] 原文: `role=AXButton value=missing value desc=ボタン kids=`（空）。

### 本文 static（初期 Claude、Disclosure 閉）

`get value of every static text` 相当（本文スクロールのネスト）:

```
CLI を検出済み
認証・通信の状態は未確認です
設定ファイルあり
```

続けてタイル（プラグイン 13 / 有効 9、マーケットプレイス 3、権限ルール 33、フック 33）と設定・メモリ。`設定ファイル未作成` と `インストール先と PATH を確認してください` と `必要な設定は左の項目から変更できます` は、本環境が検出済みかつ設定ファイルありのため未出現。

「CLI の詳細」は PNG にはあるが、AX static の value には出ない。

### DisclosureTriangle

| 時点 | AX | value |
|---|---|---|
| Claude 初期 | DT[17] `AXDisclosureTriangle` desc=開閉用三角ボタン | false |
| Claude 開 | 同 i=17 | true（AXPress before=false after=true） |
| Claude 再閉 | 同 i=17 | false（before=true after=false） |
| Codex 初期 | DT[19] | false |
| Codex 開 | i=19 | true |
| Cursor 初期 | DT[16] | false |
| Cursor 開 | i=16 | true |

開いたあとのバージョン / パス（AX static）:

| ペイン | バージョン | 実行ファイル |
|---|---|---|
| Claude | 2.1.269 | `/Users/ryosuke/.local/bin/claude` |
| Codex | 0.153.4 | `/Users/ryosuke/.local/bin/codex` |
| Cursor | 2026.09.10-fd3934a | `/Users/ryosuke/.local/bin/cursor-agent` |

Claude を閉じたあと、先頭 3 行の要約 static は残った（バージョン / 実行ファイルの static は消えた）。

## PNG 一覧

パス先頭: `/tmp/phlox-t13-visual.SPfR9c/`。論理寸法は Quartz 900×632 pt。画素は Retina 2x で 1800×1264。PID 97197（v3）。対象はいずれも管理ウィンドウ全体。

| ファイル | 対象ペイン | 寸法（論理 pt） | PID |
|---|---|---|---|
| `t37-v3-console-claude-status.png` | Claude 状態。要約 3 行、CLI の詳細は閉（`>`） | 900×632 @306,191 | 97197 |
| `t37-v3-console-claude-cli-open.png` | 同上＋ CLI の詳細開（`∨`）。バージョン 2.1.269、パス `~/.local/bin/claude` | 900×632 | 97197 |
| `t37-v3-console-claude-cli-closed.png` | 再閉。要約 3 行は残る。バージョン行は消える | 900×632 | 97197 |
| `t37-v3-console-codex-status.png` | Codex 状態（サイドバー「状態 / config.toml」選択）。要約 3 行、CLI の詳細は閉 | 900×632 | 97197 |
| `t37-v3-console-codex-cli-open.png` | Codex CLI の詳細開。バージョン 0.153.4、パス `~/.local/bin/codex` | 900×632 | 97197 |
| `t37-v3-console-cursor-status.png` | Cursor 状態（「状態 / cli-config.json」選択、サイドバーを下端までスクロール）。要約 3 行、CLI の詳細は閉 | 900×632 | 97197 |
| `t37-v3-console-cursor-cli-open.png` | Cursor CLI の詳細開。バージョン 2026.09.10-fd3934a、パス `~/.local/bin/cursor-agent` | 900×632 | 97197 |

v1 の `t37-v1-console-claude-status.png` は初期 Claude 閉の同画面（PID 81882）。v2 も同内容。

## できなかった手順と理由

- サイドバー行の AX title は missing。`状態` / `/status` / `config.toml` / `cli-config.json` は PNG とグループ見出し static で対応し、クリックはボタン index（Claude=6、Codex=16、Cursor=24）への AXPress。
- 「CLI の詳細」ラベルは AX static に出ない。開閉は `AXDisclosureTriangle`（roleDesc=開閉用三角ボタン）への AXPress。
- 初期 900×632 では Cursor グループがサイドバー下端より下。指定の「縦に並ぶ」3 グループはスクロールなしでは見切れ。Cursor の「状態」はスクロールバー value 0→1 のあと AXPress。
- 本環境は Claude / Codex / Cursor とも「CLI を検出済み」かつ「設定ファイルあり」。負例（検出できていません / 設定ファイル未作成）の実画面は未撮影（契約どおり CLI/設定は消していない）。
- `configurationDetail`（「必要な設定は左の項目から変更できます」）は設定ファイルありのとき nil のため本文に無い。
- v1 は window 参照を `my` ハンドラへ渡して System Events がプロセス名 `Phlox`（Release）を掴み、n1=0。v2 は要素を変数に入れて role が空。いずれも Release md5 は不変。v3 でフルパスに切り替えて完走。
- toolbar の Finder / 再読み込みは help が取れたが、規則により未クリック。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定（2026-09-13）

- 判定: **pass**。PM が `t37-v3-console-claude-status.png` / `-claude-cli-open.png` / `-claude-cli-closed.png` / `-codex-status.png` / `-codex-cli-open.png` / `-cursor-status.png` / `-cursor-cli-open.png` を目視。3 エージェントとも「CLI を検出済み／認証・通信の状態は未確認です／設定ファイルあり」の要約が統計カード上に表示され、「CLI の詳細」は既定で閉、開くとバージョン・実行ファイルが表示される。崩れ・切れなし。
- 未観測: 負例（「CLI を検出できていません」「設定ファイル未作成」）は本環境で CLI/設定が揃っているため実画面未撮影。凍結テスト `AcceptanceAgentConsoleStatusSummaryTests` で文言を固定している。
- Release Phlox(61465) 不変・Debug のみ操作（担当報告どおり）。

=== REPORT COMPLETE ===
