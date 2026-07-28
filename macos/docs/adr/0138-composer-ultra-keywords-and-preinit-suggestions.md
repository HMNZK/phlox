---
status: active
last-verified: 2026-07-29
---

# ADR-0138: 入力欄の ultra 系キーワードを CLI と同じ規則で強調し、init 到着前の補完を種一覧で埋める

## 文脈

composer-ultra-keywords run（2026-07-29）で、ユーザーから2つの欠落が報告された。

1. **キーワード型機能が入力欄で見えない。** Claude Code 本体は `ultrathink` / `ultraplan` /
   `ultrareview` / `ultracode` という「語」を入力テキストから検出して色付き表示するが、Phlox では
   素のテキストとして表示され、その語が効くのかどうか判らない。
2. **セッション開始直後にスラッシュ補完がほぼ出ない。** `/ultrareview`・`/deep-research` は CLI が
   実在のコマンドとして申告しているのに、そのセッションで最初の1通を送るまで候補に出ない。

### 実測（claude CLI v2.1.220・2026-07-28）

- `system`/`subtype=init` の `slash_commands` は **106 件**で、`ultrareview`・`deep-research` を
  **含む**が `ultraplan`・`ultrathink`・`ultracode` は**含まない**。生データは run 作業物として保全した。
  ADR-0120（2026-07-26 実測）の 104 件から2日で 2 件増えており、**一覧は日単位で動く**。
- **無送信のまま30秒 stdin を開けても init は届かない**（`hook_started` / `hook_response` の2行のみ）。
  ADR-0120 の「init は最初の送信後」を本 run で再実測して追認した。
- キーワードの検出実装は **2系統**ある。

  ```js
  // 規則X: ultrathink のみ。除外規則なし
  function wqr(e){ return e.matchAll(/\bultrathink\b/gi) }

  // 規則Y: ultraplan / ultrareview / ultracode。共通ヘルパ Rqs
  function Rqs(e,t){
    if(e.startsWith("/")) return []                     // 入力全体が "/" 始まりなら無効
    /* ` " < { [ ( ' のペアで囲まれた保護区間を収集（'・< は条件つき開始） */
    for (const m of e.matchAll(new RegExp(`\\b${t}\\b`,"gi"))) {
      if (保護区間内) continue
      if (直前が "/" "\\" "-") continue
      if (直後が "/" "\\" "-" "?") continue
      if (直後が "." かつ その次が語構成文字) continue
    }
  }
  function UFo(e){ return Rqs(e,"ultraplan")   }
  function sJd(e){ return Rqs(e,"ultrareview") }
  function kqs(e){ return Rqs(e,"ultracode")   }
  ```

  **`ultraplan` は init の一覧に無いがキーワードとしては実在する。** `ultrareview` はスラッシュ
  コマンドとキーワードの両方である。

## 決定

### 1. キーワード検出は CLI の規則を忠実に写す（規則X / 規則Y の差を含む）

`ComposerHighlight` に `.keyword` ケースと `spans(in:includingKeywords:)` を追加し、上記の
除外規則まで再現する。**語境界は ASCII 判定**（JS の `\b` と同じく `[A-Za-z0-9_]` で判定）とし、
Swift/ICU の Unicode 語境界を使わない。これを取り違えると `日本語ultrathink` が CLI では発火するのに
Phlox では光らない（逆も起きる）。オフセットは既存 span 契約と JS の string index に合わせ **UTF16 単位**。

既存の `spans(in:)` は**不変**とし、キーワードは新 API でのみ返す。

### 2. キーワード強調は Claude セッションのみ

`ultrathink` 等は Claude 固有機能で Codex / Cursor では何も起きない。効かない場所で光らせると
表示が嘘をつくため、`highlightsKeywords` を View 側が `agentRef == .builtin(.claudeCode)` で決める。

### 3. キーワードの色は専用トークンを新設する

`DSColor.composerKeyword`（light `#B45309` / dark `#FCD34D`）を追加した。既存の
`codeSyntaxNumber` を再利用すると、コードブロックの数値表示と入力欄のキーワードが意味的に結合し、
片方の配色変更が無関係な表示へ波及する。

### 4. init 到着前の補完は「静的リストの拡充」と「前回一覧の永続化」の両輪で埋める

- **静的フォールバックを 10 → 22 件へ拡充**する（実測で存在を確認した組み込み 12 件を追加）。
  初回起動＝永続値もない状態を救う。ADR-0120 が削除した 13 件は復活させない。
- **`AvailableCommandsStore`** を新設し、init で受領した一覧を
  **エージェント（`AgentRef.id`）× 正規化済み作業ディレクトリ**単位で `UserDefaults` に保存する。
  次回セッションは生成時にこれを読み、`seedCommands` として補完へ渡す。
- `ComposerSuggestionSources.slashCandidates` に `seedCommands` を足し、
  **`availableCommands` が非 nil なら seed を完全に無視**、nil かつ seed が非空なら
  **seed ∪ 静的リスト ∪ ディレクトリ走査名**の和集合を候補にする。空配列の seed は未受領と同一視する。
- 候補を積む順は **静的リスト → seed → `.claude/commands` → `.claude/skills`**。seed 由来の
  subtitle 解決（SKILL.md の description 優先）が、先勝ちの重複除去で `"Custom command"` に
  負けないようにするため。

### 5. 保存しない条件を明示する

空配列と 301 件以上の申告は**保存せず、既存値も消さない**。`[]` は非 nil 経路に入って候補 0 件に
なるため「値なし」と同一視する。同一キーへの再記録は**全量スナップショットで置き換える（後勝ち）**
——ADR-0120 の「差分マージしない」と同じ規則。

## 棄却案

- **静的リストだけを増やす**: 初回起動は救えるが CLI 更新のたびにずれる（実測で2日 104→106）。
  永続化と併用することで、2通目以降は常に実態へ追随する。
- **`codeSyntaxNumber` を第3色として使い回す**: トークン追加は不要になるが、コードブロックの数値と
  意味が結合する。ユーザー裁定で棄却。
- **キーワード検出を単純な語一致にする**: 実装は小さくなるが、`"ultracode"`（引用符内）や
  `/fix ultracode`（`/` 始まり）で「光っているのに効かない」が起きる。ユーザー裁定で棄却。
- **`/ultraplan` をスラッシュ補完に出す**: CLI が init で申告しないため、CLI 由来の候補としては
  出せない。キーワード強調で可視化する方針に切り替えた。
- **セッション開始時に init を取りに行く**（no-op 送信等）: トークンを消費するため採らない。

## 結果

- 凍結テスト: `AcceptanceComposerKeywordDetectionTests`・`AcceptanceComposerSeedCommandsTests`・
  `AcceptanceAvailableCommandsStoreTests`・`AcceptanceComposerKeywordRenderingTests`（すべて SessionFeature）。
- `ChatComposer` の色割り当てを三項演算子から**網羅 `switch`** へ変更した。`ComposerHighlightKind` に
  ケースを足すとコンパイルエラーになる（従来は黙って `@参照` の色に落ちていた）。
- 色の判別性は値で検証した: 背景とのコントラストは light 5.02:1 / dark 13.37:1（WCAG AA 4.5:1 を満たす）、
  既存2色との RGB 距離は 154〜201（最大 441）。
- **残る制約**: `Rqs` は CLI の内部実装であり、CLI 更新で変わりうる。検出規則は
  `ComposerHighlight.swift` に閉じ込め、本 ADR に実測日（2026-07-28・v2.1.220）を記録した。
- **残る制約**: 初回起動かつ永続値なしの状態では、静的 22 件＋ディレクトリ走査に留まる。
- **残る制約**: Codex / Cursor には一覧の供給源が無く、静的フォールバックのまま（ADR-0120 の既知の制約）。
- **未検証**: 実画面での見え方（キーワードが第3色で描画されるか・ライト/ダーク双方の判読性・
  エージェント種別ごとの ON/OFF）は AppKit レベルの受け入れテストと色値の計算で担保しており、
  **GUI 目視は未実施**。→ delivery/0024

## 追記（2026-07-29）: `ultraplan` が init に載らない理由の訂正

GUI 目視で「補完に `/ultraplan` が出ない」と再報告があり、CLI バイナリ（v2.1.220）を追加調査した。
**決定は変更しない**が、上の「実測」節の理解が不正確だったため訂正する。

`ultraplan` は**キーワード専用ではなく、ゲート付きのスラッシュコマンドでもある**。

```js
hJd = { type:"local-jsx", name:"ultraplan",
        description:"Draft an editable plan in Claude Code on the web (…)",
        argumentHint:"<prompt>", isEnabled:()=>uDe(), load:()=>… }

function uDe(){ return Ke("tengu_ultraplan_config",null)?.enabled===!0 && NPt() && !ba() }
function NPt(){ return MGe() && hbr() && Ke("tengu_ccr_bridge",!1) }   // Claude Code on the web 連携
function ba(){ return Mt.caps.workspace==="remote" }
```

init の一覧は `slash_commands: e.commands.filter((o)=>o.userInvocable!==!1).map((o)=>o.name)` で作られ、
`ultraplan` は `userInvocable:false` を持たない。つまり 106 件に無いのは「コマンドとして存在しない」
からではなく、**この環境で `isEnabled()` が false（Claude Code on the web 連携ゲートが未成立）だから**である。

したがって棄却案「`/ultraplan` をスラッシュ補完に出す」の理由は「キーワードだから」ではなく
**「CLI 自身が無効化しているものを Phlox が出すべきでないから」**に置き換わる。ゲートが有効化されれば
init に載り、Phlox は既存の追随経路でそのまま出す（**コード変更は不要**）。ユーザー裁定（2026-07-29）で
現状維持とした。

補足: init イベントは `slash_commands` のほかに `skills` / `agents` / `plugins` / `output_style` も
運ぶ（`skills: e.skills.filter((o)=>o.userInvocable!==!1).map((o)=>o.name)`）。ただし**ユーザー起動可能な
スキル名は `slash_commands` にも含まれている**（実測 106 件に `accessibility`・`dataviz`・`skill-creator`
等が入っている）ため、`skills` を追加で読んでも候補は増えない。Phlox が `slash_commands` だけを読む現状は
妥当である。
