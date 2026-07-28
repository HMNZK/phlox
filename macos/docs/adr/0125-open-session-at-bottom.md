---
status: accepted
last-verified: 2026-07-27
---

# ADR 0125: セッションを開いたら最下部から表示する（チャット・ターミナル共通）

> **このファイルの役割**: デスクトップでセッションを開く／切り替えたときに最新の位置から見えるようにした決定と、その過程で見つかった「セッション再起動後にターミナルが出力へ追従しなくなる」不具合の原因。
> **書かないもの**: チャットの追従（auto-follow）そのものの方針（→ [architecture/chat-orchestration.md](../architecture/chat-orchestration.md)）、レイアウト性能の凍結機構（→ [ADR 0116](0116-agent-grid-swiftui-jank-live-resize-width-freeze.md)）。

## 文脈

セッションを開いても、直前に見ていた位置や上へ読み戻した位置が残り、最新の発言・出力が画面外にあることがあった。

- **チャット**: `.onAppear` から `proxy.scrollTo` を即時に呼んでいた。レイアウトが確定する前の `scrollTo` は no-op になり得る（同じファイルの別経路だけが次の MainActor ターンへ遅延していた）。
- **ターミナル**: `TerminalCoordinator` はセッションの寿命を通じて同じ `SwiftTerm.TerminalView` を保持するため、表示位置がそのまま残る。そもそも最下部へ戻す API が無かった。

「読み戻し中はユーザーを引き戻さない」という既存の追従方針は壊してはいけない。最下部へ寄せてよいのは「セッションを開いた」という明示イベントだけである。

## 決定

1. **チャットの appear スクロールはレイアウト確定後（次の MainActor ターン）に行い、既存の世代トークンで stale を無効化する**（ADR 0030 の規約）。
2. **「最下部へ寄せるか」の判定を、きっかけと追従状態だけから決める純関数へ切り出す**。View はその判定を呼ぶだけにする。読み戻し中は、新着イベント自体は届いていても寄せない。
3. **セッション切替時に追従状態を初期化する**（`sessionDidChange()`）。
4. **ターミナルに最下部へ戻す API を追加し、terminal を新しいコンテナへ載せ替えたときだけ呼ぶ**。載せ替えの判定も純関数へ切り出し、`updateNSView` の中では同期的にスクロール状態を変えない（ADR 0010）。

## 途中で見つかった不具合: 位置が動かないと追従フラグが落ちない

最下部へ戻す実装を `terminalView.scroll(toPosition: 1)` の1行にしたところ、**セッション再起動（バッファ初期化）後にターミナルが先頭へ貼りついたまま、以後の出力へ一切追従しなくなる**状態が実測された（`userScrolling` が true のまま、200行 feed しても `scrollPosition` は 0.0）。

原因は Vendor 側 `scroll(toPosition:)` が「位置が動かないなら `scrollTo(row:)` を呼ばない」という早期 skip を持つこと。このリポジトリは `scrollTo(row:)` を**意図的にパッチして「早期 return より前に追従フラグを再評価する」**ようにしてあるので、`scroll(toPosition:)` 経由にするとそのパッチを迂回してしまう。

対処として、位置が動かなかったケースでも `scrollTo(row:)` を必ず一度通す。追従の唯一のスイッチが `terminal.userScrolling` であり、Vendor パッチはそれを早期 return より前で再評価する設計になっている、という機序に正面から合わせている。

## 棄却案

- **`macos/Vendor/SwiftTerm` の `scroll(toPosition:)` 側を直す**: Vendor の変更はこの作業のスコープ外。呼び出し側で設計意図に合わせられる。
- **出力が来るたびに最下部へ寄せる**: 読み戻し中のユーザーを引き戻す。既存の追従契約を骨抜きにする。
- **`updateNSView` の中で同期的にスクロールする**: レイアウトフェーズでの副作用になる（ADR 0010）。

## 訂正: `viewModel.id` の変化は本番では起きない

この作業の問題定義には「`ChatTranscriptView` は view identity を保ったまま viewModel だけ差し替わるため、前のセッションの読み戻し状態が持ち越される」と書いたが、**これは誤り**だった。実ファイルで確認した根拠:

- `ChatSessionView` の唯一のマウント（`DashboardDetailView.swift:83`）に `.id(session.id)` がある。
- グリッド側も `SessionGridView.swift:114` / `:167` の両方に `.id(session.id)` がある。
- `ChatSessionViewModel.id` は `let`（不変）。

したがって `viewModel.id` が変わる状況では必ず祖先の `.id()` も変わり、SwiftUI が subtree を破棄・再生成する（`@State` は初期化され `.onChange` は発火しない）。macOS チャットで実効的に効いているのは **appear 経路の1本だけ**である。`sessionDidChange()` の配線は、到達すれば正しく動きコストも無いので保険として残している。

## 結果

- `SessionFeature` 407 tests / `TerminalUI` 50 tests が green。既存の追従契約テスト（`TerminalFollowOnOutputTests` / `TerminalCoordinatorScrollbackTests`）は無改変で green。
- 「すでに最下部なら位置を変えない」は `yDisp` レベルで不変であることを直接観測して確認した。
- 判定を純関数へ切り出しても、**View がその判定を呼び、結果に従うこと自体は別に凍結しないと守られない**（切り出し前に生きていた変異が、切り出し後は呼び出し側へ移動しただけだった）。`ScrollViewProxy` / `Context` を要求する箇所は in-process では振る舞い検証ができないため、ソース一致で pin している。より構造的に縮めるなら、判定関数の戻り値を Bool ではなく「何もしない / 即時 / 遅延」の列挙にすると、分岐の入れ替えや否定の挿入が振る舞いテストの圏内へ移る（未実施）。
