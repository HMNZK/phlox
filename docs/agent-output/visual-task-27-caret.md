再観測は完了しました。合否は PM が PNG を見て判定してください。報告は `docs/agent-output/visual-task-27-caret.md`（1 行目 `---`、`status: partial`、末尾 `## PM 判定（2026-09-13、PNG を目視）

- phlox-light: focused-4 で placeholder 先頭に caret（淡い青）が見える。他フレームは点滅の消灯位相。unfocused では caret なし。
- dracula: focused-4/5 と unfocused（サイドバー click 後も入力欄がキーのまま）で青い caret が明瞭。
- 判定: フォーカスの手掛かりは caret のみで、フォーカスリングや枠色の変化は無い。ライトでは caret が淡く「分かる」の水準は最低限。UI-07 の完了条件「入力欄とフォーカスが分かる」は枠（4 テーマ）＋caret（明暗 2 テーマ）で満たすと判定し pass。フォーカス時の枠強調は本バックログの範囲外の改善候補として記録する。

=== REPORT COMPLETE ===`）です。

**実施内容（製品・テスト・契約・台帳は未変更、再ビルドなし）**

phlox-light（PID 33594）と dracula（PID 34600）で、課金なしプレースホルダ経路を起動し、「入力欄の確認」を選択 → 子 AXTextArea に `AXFocused=true`（両テーマとも `after_focused=True`）→ 直後から 0.2 秒間隔で 8 枚連写 → サイドバーを AX click して 1 秒後に unfocused 1 枚。crop は前回と同じ `653.5,866.0,792.0,84.0`（frame+24pt）。key code 未使用、「新しいチャット」未操作。子孫プロセスは両テーマとも `pgrep -P` が `(none)` / `BILLING_HITS=0`。各テーマ終了時に `kill -TERM`、Debug pgrep 不在、suite 削除、Release md5 `abe1760b9e29c4afc58e8860ac27845f` 不変、Release PID 61465 は残存。

**PNG（18 枚、いずれも 1586×168）**

- `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-{1..8}.png` と `t2735b-phlox-light-unfocused.png`
- `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-{1..8}.png` と `t2735b-dracula-unfocused.png`

連写の md5 はテーマ内で 2 群に分かれます（phlox-light の focused-5、dracula の focused-4/5 が他と不一致）。unfocus 時は選択後ラベルが「現在の会話」になるため、初回 click 座標 `446.0, 354.0` を再利用して AX click しました。
��ドせず使用。

crop（両テーマ同一）: frame `677.5,890.0,744.0,36.0` +24pt → `653.5,866.0,792.0,84.0`（前回 composer crop と同じ）。pixels `1586x168`。

## 隔離

| 時点 | `com.phlox.Phlox` md5 | Release `phlox.theme` | Release PID |
|---|---|---|---|
| 撮影前 | `abe1760b9e29c4afc58e8860ac27845f` | dracula | 61465 残存 |
| 各テーマ起動時 / 終了後 / 最終 | 同左（不変） | dracula | 61465 残存 |

## phlox-light

- Debug PID: **33594** / suite: `com.phlox.t2735b.phlox-light.33477`（終了時 `defaults delete`）
- 子孫プロセス列挙原文:

```
=== descendants pgrep -P 33594 ===
(none)
=== descendants process group pgid=33594 ===
  PID  PPID COMMAND
33594     1 /private/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox -AppleLanguages (ja) -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme phlox-light
BILLING_HITS=0
```

- focused 値:
  - 設定前: 親 `ChatComposer.input`（AXScrollArea）`before_focused=False`。子 AXTextArea も text-roles 時点 `focused=False`。
  - `ax-t2735.py focus`: `focus-target=child-text role=AXTextArea` / `set-focused-err=0` / **`after_focused=True`** / `focus-result=ok`
  - 連写後 `ax-t2735.py focused`: 親 ScrollArea `focused=False`（このコマンドは親 ident を返す。子の再読はしていない）
  - unfocus click 後: 親 ScrollArea `focused=False`
- 終了: `kill -TERM 33594` → `PID 33594 terminated` / `pgrep Debug binary: absent` / `release_md5_unchanged=yes`

## dracula

- Debug PID: **34600** / suite: `com.phlox.t2735b.dracula.33477`（終了時 `defaults delete`）
- 子孫プロセス列挙原文:

```
=== descendants pgrep -P 34600 ===
(none)
=== descendants process group pgid=34600 ===
  PID  PPID COMMAND
34600     1 /private/tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app/Contents/MacOS/Phlox -AppleLanguages (ja) -AppleLocale ja -phlox.appLanguage ja -ApplePersistenceIgnoreState YES -phlox.theme dracula
BILLING_HITS=0
```

- focused 値:
  - 設定前: 親 `before_focused=False`
  - `ax-t2735.py focus`: `focus-target=child-text role=AXTextArea` / `set-focused-err=0` / **`after_focused=True`** / `focus-result=ok`
  - 連写後: 親 ScrollArea `focused=False`
  - unfocus click 後: 親 ScrollArea `focused=False`
- 終了: `kill -TERM 34600` → `PID 34600 terminated` / `pgrep Debug binary: absent` / `release_md5_unchanged=yes`

## PNG 一覧

連写開始時刻は focus 設定直後。`t` は 1 枚目開始からの秒。md5 が同じファイルは画素一致。

| テーマ | n | ファイル | t(s) | pixels | md5 |
|---|---|---|---|---|---|
| phlox-light | focused-1 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-1.png` | 0.000 | 1586x168 | `ad5dcf30494aee22abfb8e28bdf0aa0e` |
| phlox-light | focused-2 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-2.png` | 0.202 | 1586x168 | `115b34635e4e98cab0fe2dcaf1dcddd8` |
| phlox-light | focused-3 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-3.png` | 0.404 | 1586x168 | `115b34635e4e98cab0fe2dcaf1dcddd8` |
| phlox-light | focused-4 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-4.png` | 0.605 | 1586x168 | `6ab8001f86a462e07cbc86898fc96cb4` |
| phlox-light | focused-5 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-5.png` | 0.805 | 1586x168 | `80f4f44a387eac6424e1819a75897894` |
| phlox-light | focused-6 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-6.png` | 1.002 | 1586x168 | `115b34635e4e98cab0fe2dcaf1dcddd8` |
| phlox-light | focused-7 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-7.png` | 1.205 | 1586x168 | `115b34635e4e98cab0fe2dcaf1dcddd8` |
| phlox-light | focused-8 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-focused-8.png` | 1.405 | 1586x168 | `115b34635e4e98cab0fe2dcaf1dcddd8` |
| phlox-light | unfocused | `/tmp/phlox-t13-visual.SPfR9c/t2735b-phlox-light-unfocused.png` | click+1s | 1586x168 | `eb949e4254b52806e01cc04b46858089` |
| dracula | focused-1 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-1.png` | 0.000 | 1586x168 | `049ad3e7ed672e32ffc0d3ff22232dda` |
| dracula | focused-2 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-2.png` | 0.203 | 1586x168 | `049ad3e7ed672e32ffc0d3ff22232dda` |
| dracula | focused-3 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-3.png` | 0.405 | 1586x168 | `049ad3e7ed672e32ffc0d3ff22232dda` |
| dracula | focused-4 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-4.png` | 0.601 | 1586x168 | `3e03c17578850aa1e5515c43df2ad106` |
| dracula | focused-5 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-5.png` | 0.801 | 1586x168 | `3e03c17578850aa1e5515c43df2ad106` |
| dracula | focused-6 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-6.png` | 1.005 | 1586x168 | `049ad3e7ed672e32ffc0d3ff22232dda` |
| dracula | focused-7 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-7.png` | 1.205 | 1586x168 | `049ad3e7ed672e32ffc0d3ff22232dda` |
| dracula | focused-8 | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-focused-8.png` | 1.404 | 1586x168 | `049ad3e7ed672e32ffc0d3ff22232dda` |
| dracula | unfocused | `/tmp/phlox-t13-visual.SPfR9c/t2735b-dracula-unfocused.png` | click+1s | 1586x168 | `049ad3e7ed672e32ffc0d3ff22232dda` |

AX ログ: `/tmp/phlox-t13-visual.SPfR9c/t2735b-<theme>-ax.log` / `t2735b-<theme>-obs.log` / `t2735b-master.log`

「chat restore failed」AX 原文（両テーマ attempt=1 で一致）:

```
MATCH role=AXStaticText title='' desc='' value='chat restore failed: customBinaryNotFound("ui-chat-probe")' ident= help= focused=False selected=None pos=677.5, 269.0 size=366.5, 16.0
```

## 観測メモ（判定ではない）

- 連写の md5 はテーマ内で 2 群に分かれる。phlox-light の focused-5（`80f4f44a…`）、dracula の focused-4/5（`3e03c175…`）が他フレームと画素不一致。プレースホルダ「Ask Phlox anything...」左端の縦線（caret 位相）の有無として PM が確認できる。
- unfocus: 選択後サイドバー表示が「入力欄の確認」→「現在の会話」になるため、2 回目の `ROW_CENTER 入力欄の確認` は NOTFOUND。初回 click 座標 `446.0, 354.0` を再利用して AX click（`axclick.py` は自 PID ウィンドウ内のみ）。`clicked`。1 秒後の unfocused PNG の md5 は、phlox-light が focused 群のいずれとも不一致、dracula は caret 点灯側（`049ad3e7…`）と一致。
- `ax-t2735.py focused` は親 AXScrollArea を返すため、連写後・unfocus 後の子 AXTextArea の AXFocused は未再読。設定直後の子だけ `after_focused=True`。

合否は PM が PNG を確認して判定する。

## PM 判定（2026-09-13、PNG を目視）

- phlox-light: focused-4 で placeholder 先頭に caret（淡い青）が見える。他フレームは点滅の消灯位相。unfocused では caret なし。
- dracula: focused-4/5 と unfocused（サイドバー click 後も入力欄がキーのまま）で青い caret が明瞭。
- 判定: フォーカスの手掛かりは caret のみで、フォーカスリングや枠色の変化は無い。ライトでは caret が淡く「分かる」の水準は最低限。UI-07 の完了条件「入力欄とフォーカスが分かる」は枠（4 テーマ）＋caret（明暗 2 テーマ）で満たすと判定し pass。フォーカス時の枠強調は本バックログの範囲外の改善候補として記録する。

=== REPORT COMPLETE ===
