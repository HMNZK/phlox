---
status: partial
---

実行コミット: `94da1af18d0054631d2b0a49800cd23130d73414`。

## ビルド・隔離

- `xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build-t45b -destination platform=macOS build`: `** BUILD SUCCEEDED **`。ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t45b.log`。
- Debug PID: 明色 `31047`、暗色 `38294`、rename `54241`、rename 再起動 `57629`。すべて `kill -TERM` 後に終了し、最終 Debug PID は空。
- suite: `com.phlox.t45.phlox-light.observe.30945`、`com.phlox.t45.dracula.observe.30945`、`com.phlox.t45.phlox-light.rename.30945`、`com.phlox.t45.rename2.30945`、`com.phlox.t45.rename2restart.30945`。終了後に削除済み。
- DATA: `/tmp/phlox-t13-visual.SPfR9c/data-t45-{phlox-light,dracula,rename2-30945}`。すべて `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON=/tmp/phlox-t13-visual.SPfR9c/agents-t45.json`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` で起動。
- Release PID `61465`（`/Applications/Phlox.app`）には非接触。`com.phlox.Phlox` md5 は開始・各終了・最終で `4f3a1bf83e661df122d4d79cda27bf4d`。
- 起動直後の `claude --bare -p /model --output-format json` はモデルカタログ照会として終了。以後の子プロセスは `/bin/cat` 7 件のみ。実エージェント、課金セッション、キー入力は使用していない。

## 必須表示条件の観測

| 条件 | 観測 | 結果 |
|---|---|---|
| 900pt・8 セッション・4 列、明色 | `grid-w900` と `grid-pane240-attempt` PNG、AX | 主名の先頭＋`…` が全タイルに残る。状態ドット、状態ラベル、閉じるボタンも残る。 |
| 900pt・8 セッション・4 列、暗色 | 同上 | 同結果。 |
| 240pt ペイン | AX | 未達。ウィンドウは 720pt 指定後も最小 900pt、グリッドの AXScrollArea 実幅は 145pt。 |
| サイドバー階層・状態・長名 | 明色 1 セット PNG/AX | 回帰なし。 |
| 単体 PTY／チャット topbar | 明色 1 セット PNG/AX | 回帰なし。チャットは既定 fixture の `customBinaryNotFound`。 |
| チーム名前領域 | 明色 1 セット PNG/AX | 回帰なし。`シングルビューで開く` は `AXPress err=0`。 |

## 狭幅グリッドの AX 実測

対象 PNG は明色 `t45-phlox-light-grid-w900-pid31047.png`、`t45-phlox-light-grid-pane240-attempt-pid31047.png`、暗色 `t45-dracula-grid-w900-pid38294.png`、`t45-dracula-grid-pane240-attempt-pid38294.png`。いずれもウィンドウ実幅 900pt、4 列。

| テーマ | grid AXScrollArea 実幅×高 | タイル主名 Text AX 幅 | AX value | 描画文字列 | 末尾省略 |
|---|---:|---:|---|---|---|
| phlox-light | 145×338pt | 31.5pt（`Rose` は36pt） | 全文 | `ロ…` / `#…` / `通…` / `文…` / `こ…` / `Ro…` / `A…` / `閉…` | あり |
| dracula | 145×338pt | 31.5pt（`Rose` は36pt） | 全文 | `ロ…` / `#…` / `通…` / `文…` / `こ…` / `Ro…` / `A…` / `閉…` | あり |

主名 Text の AXValue は元の完全な作業名で、描画は読める先頭文字を優先した末尾省略である。例えば明色 900pt の AX 原文:

```
NAME role=AXStaticText title='' desc='ログイン画面を修正' value='ログイン画面を修正' ... pos=1460.0, 407.75 size=31.5, 20.5
NAME role=AXStaticText title='' desc='通知の重複を修正' value='通知の重複を修正' ... pos=1765.5, 407.75 size=31.5, 20.5
NAME role=AXStaticText title='' desc='Rose' value='Rose' ... pos=1612.75, 785.75 size=36.0, 20.5
```

操作到達性:

```
pressed-AXPress err=0 role=AXButton ident=xmark ... desc='閉じる'
clicked                         # 自 PID の axclick.py でサイドバー行を選択
pressed-AXPress err=0 role=AXButton ident=view-mode-grid ...
```

## 補助花名のコントラスト実測

補助花名は単独 AX Text ではない。主名 AX の `help` にのみ `花名:` が入る。PNG のトップバー中央に描画された花名グリフ成分を Pillow で抽出し、最頻の非アンチエイリアス文字色と周囲の実背景色を使い WCAG 相対輝度比を計算した。主名 frame の右隣には補助花名が描画されないレイアウトだったため、花名が実際に描画されるトップバー中央を測定した。

| テーマ | 状態 | 花名 | fg RGB | bg RGB | 比 | 4.5:1 |
|---|---|---|---|---|---:|---|
| phlox-light | 通常 | Iris | `(29,29,29)` | `(247,247,247)` | 15.74 | pass |
| phlox-light | 選択 | Iris | `(29,29,29)` | `(247,247,247)` | 15.74 | pass |
| phlox-light | 注意 | Rose | `(29,29,29)` | `(247,247,247)` | 15.74 | pass |
| dracula | 通常 | Iris | `(248,248,248)` | `(42,42,42)` | 13.52 | pass |
| dracula | 選択 | Iris | `(248,248,248)` | `(42,42,42)` | 13.52 | pass |
| dracula | 注意 | Rose | `(248,248,248)` | `(42,42,42)` | 13.52 | pass |

計算式は `(lighter + 0.05) / (darker + 0.05)`。補助花名の単独 AX value は依然取得できない。

## rename

通常名 `通常リネーム後` は UI 経路で成功し、サイドバー、トップバー、グリッド、チームに反映された。終了・同一 DATA 再起動後もグリッドで `通常リネーム後` と花名 `Lily` を確認した。

AX 原文:

```
actions value='通知の重複を修正' role=AXStaticText names=( AXShowMenu )
AXShowMenu err=-25204 role=AXStaticText value='通知の重複を修正' pos=1248.0, 484.0
pressed-AXPress err=0 role=AXMenuItem ident=menuAction: title='名前を変更' ...
set-value err=0 role=AXTextField before='通知の重複を修正' after='通常リネーム後' wanted='通常リネーム後'
AXConfirm err=0 role=AXTextField
pressed-AXPress err=0 role=AXButton ident=action-button-1 desc='変更' ...
NAME role=AXStaticText ... desc='通常リネーム後' value='通常リネーム後' ...
花名: Lily
```

同花名 `Lily` と空欄は未実施。通常名を選んだ後の同じ sidebar AXStaticText は `AXShowMenu` action を報告したが、`AXShowMenu 0` 後に AXMenu が出ず、`名前を変更` は `NOTFOUND`、rename TextField は `NOTFOUND` だった。トップバー同名 Text の `AXShowMenu` もメニューを出さなかった。右クリック CGEvent・key code・keystroke は規則により使用しなかった。

再起動後の AX 原文（チーム）:

```
NAME role=AXStaticText ... desc='通常リネーム後' value='通常リネーム後' ...
花名: Lily
NAME role=AXStaticText ... desc='#A55555' value='#A55555' ...
花名: Violet
```

## PNG 一覧

ルート: `/tmp/phlox-t45-visual/run2-30945/`。PNG 66 枚の完全な一覧は同ディレクトリの `png-list.txt`。

- 狭幅: `t45-{phlox-light,dracula}-grid-{w900,pane240-attempt}-pid{31047,38294}.png`
- 明色回帰: `t45-phlox-light-{sidebar-*,topbar-*,team-*,grid-normalw,grid-w1024}-pid31047.png`
- 暗色回帰: `t45-dracula-{sidebar-*,topbar-*,team-*,grid-normalw,grid-w1024}-pid38294.png`
- 成功した rename: `t45-phlox-light-rename-normal-{sidebar-topbar,grid,team}-pid54241.png`
- rename 再起動: `t45-phlox-light-rename-restart-{grid,team,sidebar-topbar-front}-pid57629.png`

`rename-same-flower-*` と `rename-empty-*`（PID 54241／旧 PID 44418）は UI rename が成立しない時点の撮影であり、同花名・空欄の反映証拠ではない。

## 未達手順と理由

- 同花名・空欄 rename、ならびにそれらの反映／永続化: 再度の AXShowMenu が menu を出さず、キー入力・CGEvent 右クリックは許可外のため停止。
- 240pt ペイン: アプリ最小ウィンドウ幅 900pt により実現不可。実測は 145pt。

PM 目視ゲートは PM が PNG を確認して判定する。

## PM 判定 r2（2026-09-14、再撮影 66 枚のうち主要 4 枚を PM が閲覧）

判定: **pass**。

- 差し戻しの指摘は解消: ウィンドウ実幅 900pt・8 セッション・4 列（グリッドの実幅 145pt）で、全タイルの見出しに主名の先頭＋`…` が残る（`t45-phlox-light-grid-w900-pid31047.png`・`t45-dracula-grid-w900-pid38294.png`）。状態ドットと閉じるボタンは残り、押し出されていたのは補助花名・状態ラベル・作業場所の側になった。通常幅 1440pt・1024pt の見え方は従前どおり（主名＋補助花名＋作業場所）。
- コントラスト: 主名・補助花名とも明色 15.74、暗色 13.52 で、通常・選択・注意の 6 条件すべて 4.5:1 を満たす。
- rename: 通常名の UI 経路が成功し、サイドバー・トップバー・グリッド・チームへ反映、終了と同一データでの再起動後も主名と花名 `Lily` を保持。

未検証として残し、フォローアップに送る 2 点:
1. **240pt ペインの実測は不可**。アプリの最小ウィンドウ幅が 900pt のため、グリッドの実幅は 145pt までしか作れない。ただし 145pt は契約が要求する 240pt より狭く、そこで主名が残ることを確認したので、240pt の条件はより厳しい側で満たされていると PM は判定する。
2. **花名と同じ文字列への rename・空欄 rename は UI 経路で未実施**。`AXShowMenu` 後にメニューが出ず、`名前を変更` の AX 要素に到達できなかった（原文は本書の rename 節）。両状態の**表示**（補助花名を出さない／短縮 ID にフォールバック）は fixture で作った `sameflower`・`empty` の PNG と凍結受け入れテストで確認済みで、未検証なのは UI から当該状態へ遷移させる操作のみ。

=== REPORT COMPLETE ===
