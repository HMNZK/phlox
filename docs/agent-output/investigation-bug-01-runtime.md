---
status: partial
task: BUG-01
date: 2026-09-13
pid: 80633
suite: com.phlox.bug01.80626
---

# BUG-01 実行時トレース再現

調査のみ。製品恒久修正・コミット・push はしていない。作業ツリーは `spike/bug01-repro`（`/Users/ryosuke/Projects/Phlox-oss-worktrees/bug01-repro`）。Release Phlox（PID 61465）には未接触。

## ビルド結果

- 事前: worktree に `Phlox.xcodeproj` が無いため `macos/` で `xcodegen generate`（生成物）。
- コマンド: `cd .../bug01-repro/macos && xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-bug01-repro/Build -destination platform=macOS build`
- ログ: `/tmp/phlox-bug01-repro/build.log`
- 末尾: `** BUILD SUCCEEDED **` / EXIT:0
- 成果物: `/tmp/phlox-bug01-repro/Build/Build/Products/Debug/Phlox.app`

## PID / 隔離

| 項目 | 値 |
|---|---|
| Debug PID | 80633（自プロセスのみ AX / axclick / TERM） |
| 先行失敗起動 | 77849（エージェント管理だけ復元。TERM 済み） |
| suite | `com.phlox.bug01.80626`（終了後 `defaults delete`） |
| PHLOX_DATA_DIR | `/tmp/phlox-bug01-repro/data` |
| PHLOX_AGENTS_JSON | `/tmp/phlox-bug01-repro/agents.json`（custom `sh -c` のみ。課金 CLI は未 click） |
| Release PID 61465 | 起動中のまま。`com.phlox.Phlox` md5 `abe1760b9e29c4afc58e8860ac27845f` 不変 |
| トレース | `/tmp/phlox-bug01-repro/trace.log`（アプリがファイル追記 + `print` + `os_log`、接頭辞 `[BUG01]`） |

起動は `open -n` + `PHLOX_DATA_DIR` / `PHLOX_DEFAULTS_SUITE` / `PHLOX_AGENTS_JSON` / `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1`、`-AppleLanguages "(ja)"`。System Events は `first process whose unix id is 80633`。key code / keystroke 未使用。

追加した起動引数: `-ApplePersistenceIgnoreState YES`。無しだと WindowGroup 本窓が出ず「エージェント管理」だけが復元された（PID 77849）。利用者の Release 設定は変更していない。

## トレース点一覧（file:line、spike ツリー相対）

| 事象 | 場所 |
|---|---|
| ファイル/`print`/`os_log` 出力 | `macos/Packages/TerminalUI/Sources/TerminalUI/Bug01Trace.swift:11` |
| `TerminalMount.attach` enter / other-subview detach / skip / detach / done | `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift:49,54,60,64,73` |
| `updateNSView`（session / hosting / container / PTY / frame） | `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift:29` |
| `setFrameSize` / refresh | `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalHostingView.swift:63,74` |
| `viewDidMoveToWindow` | `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalHostingView.swift:46` |
| SwiftTerm `sizeChanged` | `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalCoordinator.swift:317` |
| PTY resize | `macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift:650` |
| session id を coordinator へ | `macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift:24,234` / `TerminalCoordinator.swift:59` |
| 選択 old→new | `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift:460` |
| 表示モード grid↔single | `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardView.swift:453` |
| spawn 時花名 | `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift:1045` |

## セッション対応

custom agent 2 本（`seq 1 30; exec cat`）。花名は生成値。

| 役割 | agent id / 表示名 | 花名 | session id |
|---|---|---|---|
| Sunflower 相当（1本目） | `bug01-sunflower` / Sunflower | **Camellia** | `3862AAB8-B366-4616-A59C-2ED2F782F9C6` hosting=`32777439104` |
| Bluebell 相当（2本目） | `bug01-bluebell` / Bluebell | **Gardenia** | `4928D7AF-A335-497E-8C72-6786A04D2D89` hosting=`32784156544` |

作成はプロジェクト行＋メニュー `click menu item "Sunflower"` / `"Bluebell"`（Claude/Codex/Cursor/新しいチャットは未 click）。

## 再現 A/B/C 結果表

操作の目視根拠は PNG。AX 列挙は描画の代替にしない。

| 再現 | 操作 | 選択 | 表示モード | ターミナル空白か | PNG |
|---|---|---|---|---|---|
| 事前（誤って先に 1 回 grid→single） | モードボタン AXPress のみ | Gardenia のまま | single | **空白**（データは残存。後で切替で復帰） | `/tmp/phlox-bug01-repro/single-before.png` |
| 復帰確認 | サイドバー Camellia を axclick.py | Gardenia→Camellia | single | 出力あり（SUNFLOWER_OUTPUT 1–30） | `single-camellia-click.png` / `c-camellia-restored.png` |
| **A** | グリッド AXPress → タイル見出し「Gardenia」に `AXPress` → 単一 AXPress | **Camellia のまま**（選択ログ増なし） | grid→single | グリッドは両タイル出力あり。**単一は空白** | `a-grid.png` / `a-single.png` |
| **B** | グリッドで Gardenia 見出しを axclick.py（1158,241 付近、遮蔽確認付き）→ 単一 | Camellia→**Gardenia**（選択成功） | grid→single | グリッドは出力あり。**単一は空白** | `b-grid.png` / `b-single.png` |
| **C** | Camellia のまま grid→single を 3 往復（見出しクリックなし） | **Camellia のまま** | 3 往復 | グリッドは毎回出力あり。**単一は 3 回とも空白** | `c-grid-1.png` … `c-single-3.png` |

タイル見出し AX: `get name of actions` は **`AXShowMenu` のみ**。`AXPress` は actions に無い。System Events の `perform action "AXPress"` はエラーにならず実行結果文字列は返るが、`router.selectedSession` は変わらない。マウス相当（axclick.py）は `DragGesture` / `NSEvent.leftMouseDown` 経路で選択が変わる。

単一空白時の AX: `group 1 of window 1` の子 12 件は role/value/size が空。ターミナル領域の AX 子で内容有無は判定不能。空白判定は PNG。

## ログ時系列抜粋（C 往復 1 回目、空白直前）

Camellia hosting=`32777439104`。時刻は unix 秒（trace.log）。

1. `2163.005` attach **done** owner=`32784159104`（グリッドタイル、のち size 450.5×706、window=set）→ グリッドに描画される。
2. `2163.011` `viewMode single->grid selected=Camellia`
3. `2165.066` 単一用の新コンテナ `32777439744`（frame 0×0）へ attach done。直後 `viewDidMoveToWindow window=nil`。
4. `2165.070` **グリッド側コンテナ `32784159104` の `updateNSView` が後着**し、hostingView を新コンテナから **奪い返して** attach done owner=`32784159104`。
5. `2165.072` `viewMode grid->single selected=Camellia`
6. `2165.080` `viewDidMoveToWindow window=nil superview=32784159104`（**最終所有者は破棄されるグリッドタイル**）。このあと単一コンテナへの再 attach は無い。

`setFrameSize refresh` は単一側では走っていない（載せ替え先がグリッド残骸のまま window=nil）。PTY `cols/rows` とバッファは残る（次のグリッドで 1–30 が再描画される）。

A（選択不変）と B（Gardenia に選択成功）も、単一 PNG は空白・グリッド PNG は出力あり、で同じ型。

## 判定

**再現する。** 空白は「ヘッダー AX で選択が変わらなかった」ことだけでは起きない。選択が変わっても（B）、選択が Camellia のままでも（A/C）、**grid→single のたびに単一が空白**になる。復帰は別セッションをマウスで選ぶ（仕様の観察と一致）。データ消失ではない。

候補の絞り込み:

- **所有権競合（候補 1）に合致。** 新単一コンテナへ attach した直後に、まだ生きているグリッドタイルの `updateNSView` が同じ `hostingView` を奪い返し、その superview が `window=nil` で破棄される。単一側コンテナは空のまま残る。
- **再描画順序 / `sizeChanged` 偽（候補 2）は、この空白の一次原因としては弱い。** 空白時は単一コンテナ上で `setFrameSize refresh` が走っていない。グリッドでは refresh と出力描画が成立する。
- タイル見出しに AX 選択経路が無いことは静的解析どおり追加確認（actions=`AXShowMenu`）。BUG-01 の空白そのものの因果ではない。

修正済みにはしない。スパイクのトレースは調査用のまま残す。

## できなかった手順と理由

- 指定の `xcodebuild` だけでは worktree に `Phlox.xcodeproj` が無く失敗（exit 66）。`xcodegen generate` が必要だった。
- `set size of window 1 to {1440, 800}` は Quartz 実寸 1206×790 に留まった（既存ハーネスと同じ）。
- `single-before.png` は「初回 grid 前の単一で両セッション出力」になっていない。2 本作成直後に誤って grid へ入れ、戻した単一（Gardenia）が既に空白だった。両セッションに出力があることは直後の `a-grid.png` で確認。
- `entire contents` での Gardenia 列挙は空。group 1 の `every static text` でタイル見出し座標は取れた。
- 単一空白面のターミナル AX 子は属性が空で、AX だけでは空白判定不能（PNG で判定）。
- 初回起動は本窓が出ずエージェント管理のみ。`-ApplePersistenceIgnoreState YES` で再起動した。

## spike ツリー `git diff --stat`

```
 .../DashboardFeature/Dashboard/DashboardView.swift | 14 +++++++++++-
 .../Dashboard/DashboardViewModel.swift             |  3 +++
 .../Sources/SessionFeature/SessionViewModel.swift  | 10 ++++++++-
 .../Sources/TerminalUI/TerminalCoordinator.swift   |  8 +++++++
 .../Sources/TerminalUI/TerminalHostingView.swift   | 14 ++++++++++++
 .../Sources/TerminalUI/TerminalView.swift          | 25 +++++++++++++++++++++-
 6 files changed, 71 insertions(+), 3 deletions(-)
```

未追跡: `macos/Packages/TerminalUI/Sources/TerminalUI/Bug01Trace.swift`。`git stash` していない。

終了: PID 80633 に `kill -TERM`、Debug バイナリ `pgrep` 不在、suite 削除、Release 61465 残存。

=== REPORT COMPLETE ===
