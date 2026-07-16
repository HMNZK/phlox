---
status: superseded
superseded-by: 0072
last-verified: 2026-07-11
supersedes: 0043
---

> 2026-07-11: 決定2（ツリー埋め込み）はユーザー指示により ADR 0072（アゴラ＝フラットグループチャット）で廃止・置換。決定1/3/4/5（グループチャット行スタイル・composer 根宛て・性能設計・readiness 独立チャネル）は 0072 が継承する。

# ADR 0070: エージェントビュー（チーム表示）をグループチャット＋ツリー埋め込みへ再設計する

> **このファイルの役割**: なぜフラット統合タイムライン（ADR 0043）を廃し、「メインセッションを幹・サブセッションを spawn 位置へ埋め込むグループチャット」を選んだかの決定・文脈・結果。
> **書かないもの**: 現行のコンポーネント構造・型（→ `architecture/team-timeline-view.md`）。

## 文脈

ADR 0043 のチーム表示は全セッションの発言を timestamp で1本にフラットマージしていた。ユーザー要望（2026-07-10）で次の欠落が明確になった:

1. 自分（ユーザー）とエージェントの発言が同じ左寄せで、グループチャットとして読めない。
2. 発言者の識別（アイコン＋セッション名）が弱い。
3. 入力欄がなく、このビューから会話を続けられない。
4. メイン→サブの spawn 構造（ロジックツリー）がフラット化で消える。

## 決定

1. **グループチャット化**: ユーザー発言（`ChatItem.userMessage`）は右寄せ吹き出し、エージェント発言は左寄せ＋「アイコン＋セッション名」の発言者ヘッダ。セルはシングルビューの `ChatItemView` を read-only 再利用する。
2. **ツリー埋め込み**: フラットマージ（`TeamTimelineModel.merge`）に代え、`AgentChatTimelineBuilder.build` がメインセッションの transcript を幹に、サブセッションを **spawn 位置（anchor）へ埋め込みカード**として再帰挿入した木を返す。anchor＝（間引き前の）子自身の transcript 順で最初の非 nil timestamp、無ければ子 sources 順で最初の anchor、無ければ親末尾。同位置兄弟は anchor 昇順・同値は sources 出現順で決定的。カードは折りたたみ可・ヘッダクリックで `router.openSingle` によりシングルビューへドリルダウン。
3. **入力欄（TeamComposer）**: 宛先は**常にツリーの根**（`TeamComposerTarget.resolveRootSessionID` が親ポインタを循環安全に遡上）。appServer/pty とも `ControllableSession.sendText(_:submit:)` で送信。送信失敗時は下書きを復元する（握りつぶさない）。
4. **性能設計は ADR 0043/0045 を継承**: 遅延配置（LazyVStack 等）禁止・350ms tick＋シグネチャ差分ゲートでの再構築・表示上限（200 msg/セッション、anchor は間引き前に算出）。builder は全反復化（明示スタック）で深い木（2000 ノード鎖で 0.02s・stack safe）。
5. **composer 活性の独立 publish**: pty の `isReadyForInput` は時刻経過（settle 0.4s）だけで true になり、シグネチャは変化しない。このため readiness は毎 tick 算出し**値が変わった時だけ** store の独立プロパティへ publish する（タイムライン全量再構築とは独立のチャネル。body から高頻度 observable を読まない原則を維持）。

## 棄却案

- **サブセッションを会話末尾へまとめてツリー表示**: spawn の時系列文脈が失われる。ユーザーがインライン埋め込みを選択。
- **4番目の新ビューモード追加**: 旧チーム表示と役割が重複する。既存 `.team` の全面改修を選択。
- **composer の宛先切替／サブ別 composer**: 初期実装の複雑度が上がる。「常にメイン宛て」を選択。
- **anchor＝子ツリー内の最小 timestamp**: transcript 順を無視し、時計逆行データで埋め込み位置が乱れる（ステージ2レビューが検出）。「transcript 順で最初の非 nil」に確定。

## 結果

- 受け入れテスト: `AcceptanceAgentChatTimelineTests`（木構築 8 件）・`AcceptanceAgentViewRowsTests`（行ヘッダ／composer 宛先 7 件）を凍結。DashboardFeature 1147 テスト green・E2E 15 green。
- 実 Debug で CPU 収束（0〜1.3%）を確認（ADR 0045 の 100% 固着は再発せず）。
- ADR 0043 の「1本のフラットタイムライン」という表示決定は本 ADR で置き換え（superseded）。tick＋シグネチャゲートの性能決定は継承する。
