---
status: active
last-verified: 2026-09-13
---

# ADR-0174: 表示切替後のターミナル空白を、接続先の所有権管理で防ぐ

## 文脈

BUG-01「表示切替後にターミナルが空白になる」は、同じ端末ビューを新旧の表示先が奪い合うことで発生した。[task-39 の契約・改訂](../../../tasks/task-39.md)に基づき、端末を作り直さず、接続と破棄の所有権を管理して修正する。

`SessionViewModel` はセッションごとの `TerminalCoordinator` を保持し、その coordinator が SwiftTerm の `terminalView` と、それを包む `hostingView` を保持する。単一表示とグリッド表示の `TerminalView` は、それぞれ軽量なコンテナを作り、同じ `hostingView` の親を付け替える。この表示先の生成から破棄までを mount と呼ぶ。

修正前の `TerminalMount.attach` は、要求されたコンテナが現在の親と異なれば無条件に載せ替えていた。しかし、SwiftUI では新 mount の接続後にも旧 mount の `updateNSView` が届く。

[実行時調査](../../../docs/agent-output/investigation-bug-01-runtime.md)では、同じ `hostingView` に対して次の順序が記録された。

| 時刻（ログ抜粋） | 事象 |
|---|---|
| `2163.005` | グリッドのコンテナに接続し、出力を表示 |
| `2165.066` | 新しい単一表示のコンテナへ接続。この時点では frame は 0×0 |
| `2165.070` | 旧グリッドの `updateNSView` が後着し、端末を奪い返す |
| `2165.080` | 旧グリッド側が `window=nil` になる。単一側への再接続は発生しない |

単一表示には端末のないコンテナが残る。選択変更のない操作でも、マウス相当の操作で選択を変更した場合でも空白になり、選択固定の3往復では単一表示が3回とも空白になった。一方、グリッドへ戻すと既存出力が再表示されたため、データ消失ではない。

[静的調査](../../../docs/agent-output/investigation-bug-01.md)では、所有権競合とサイズ確定・再描画順序が候補だった。実行時ログによって、今回の空白は旧 mount の奪い返しで説明できた。空白時に単一側の refresh が走っていないことも、端末がそこに接続されていない結果と整合する。

## 決定

### 最後に有効な接続を要求したコンテナを所有者とする

[TerminalView.swift](../../Packages/TerminalUI/Sources/TerminalUI/TerminalView.swift) の `TerminalMount` を、接続・解放の共通窓口とする。判定とビュー操作は `@MainActor` 内で行う。「最後」は単なる呼び出し時刻ではなく、失効済みの旧所有者による後着要求を除いた接続順序を指す。

端末ごとの台帳は次の構成とする。

- `records`: `hostingView` を弱参照キーとする `NSMapTable<NSView, Record>`。
- `owner`: 現在の所有者であるコンテナへの弱参照。
- `formerOwners`: 所有権を失ったコンテナを記録する弱参照の `NSHashTable`。

A から新しい B へ載せ替えたら、A を `formerOwners` に記録する。B が所有している間に届く A の再接続要求は拒否する。同じ B の連続更新も、載せ替え不要として `false` を返す。

所有権の判定は、subview の除去・追加・制約変更より先に行う。これにより、A に別端末 Y が接続されていても、旧端末 X の後着要求が Y を消すことはない。接続を受け入れた場合だけ親を付け替え、四辺の制約を張り、`true` を返す。

### 接続と解放に同じ所有権規則を適用する

`detach` は、要求元が現在の `owner` と同一の場合だけ端末を外す。旧 mount の破棄では、新 mount の接続を解放できない。

現在の所有者が解放したら `owner` と `formerOwners` を消す。所有者の弱参照が `nil` になった場合も、次回 attach 時に旧所有者の記録を消す。これにより、解放後は生存している旧 A も、新しい C も接続できる。旧 mount を永久に禁止しない。

同じコンテナで端末を X→Y に切り替える際は、X の接続と、そのコンテナが持つ X の所有権を解放して Y を接続する。X の遅れた detach は Y に影響せず、後から X を再選択できる。

### mount の破棄では、その時点の端末を解放する

mount ごとに `TerminalMountCoordinator` を1個生成し、`current` に現在の `TerminalCoordinator` を保持する。SwiftUI の struct 再評価ごとに mount の同一性を作り直さない。

`updateNSView` は attach より前に `context.coordinator.current = coordinator` を行う。`dismantleNSView` は、その mount coordinator の `current.hostingView` を所有権付きの detach へ渡す。

これは契約改訂2で確定した。`makeCoordinator()` が初期端末 X 自体を返す方式では、同じ mount が Y に切り替わっても、破棄時に渡される coordinator は X のままであり、Y を解放できなかった。現在端末を追跡する参照型を mount の寿命に結びつけ、このずれを解消する。

### 接続時の未確定レイアウトを許容する

`window == nil` や frame 0 を理由に attach を拒否しない。実行時ログでは、正当な新しい単一コンテナも接続時点でこの状態だったため、表示中かどうかの判定には使えない。

`scrollToBottom` は attach が `true` を返した場合だけ、従来どおり次の runloop に予約する。同じ mount の更新や、拒否した旧 mount の更新では予約しない。

[ADR-0010](0010-loopflow-kanban-hang-observable-mutation-during-render.md) の教訓に従い、view body から観測状態を変更せず、同期的なスクロール副作用も追加しない。[ADR-0116](0116-agent-grid-swiftui-jank-live-resize-width-freeze.md) の構造化チャット向け live resize 幅保持は別経路であり、変更しない。

### 却下した代替案

| 代替案 | 採用しない理由 |
|---|---|
| `needsDisplay` や全行 refresh の強制 | 空白の単一コンテナには端末自体がない。描画要求では正しい親へ戻せない |
| タイルの再生成や `.id` の変更 | 新旧 mount の更新順序を制御せず、共有端末の奪い返しを防ぐ規則にならない |
| 単一表示用の `hostingView` 複製 | 同じ AppKit ビューは複数の親に属せない。内側の端末も複製すれば、バッファ・入力・サイズ・スクロール状態の同期が別途必要になる |
| PTY 再起動、端末再生成、出力再投入 | 既存出力が残るという観測に反し、端末の同一性と履歴を損なう |
| `window`・frame による接続拒否 | 正当な新 mount も未接続・ゼロサイズで到着する |
| 待ち時間や再試行タイマーの追加 | メインスレッド上のイベント順序に対する所有権規則を定めず、別の順序で再発し得る |
| 初期端末をそのまま mount coordinator にする | 同一コンテナの X→Y 切替後、破棄時に現在の Y を解放できない |

## 結果

[最終差分](../../../docs/agent-output/task-39-review-input-full.diff)の製品変更は `TerminalView.swift` に限定した。端末本体の生成、PTY 入出力、サイズ通知、既存の非同期 refresh を維持し、表示先の所有権と破棄処理を追加した。

### 回帰テストと製品経路の検査

[凍結受け入れテスト](../../Packages/TerminalUI/Tests/TerminalUITests/AcceptanceTerminalMountOwnershipTests.swift)は、当初の10ケースに契約改訂で3ケースを加え、現行では13ケースである。

| 区分 | 守る不変条件 |
|---|---|
| 当初の所有権8ケース | 初回接続、新 B への移譲、旧 A の後着拒否、B の連続更新の無操作、旧 A の解放拒否、B の解放と二重解放拒否、解放後の A／新 C の再接続 |
| 当初の追加2ケース | 同一コンテナの X→Y→X 切替と遅れた解放の無害性、端末ビューの同一性と投入済み出力の保持 |
| 改訂の追加3ケース | 差し替え後の実破棄入口が Y を解放すること、旧 A の破棄が B を外さないこと、X の後着要求が A 上の別端末 Y を消さないこと |

テストは実際の `TerminalCoordinator` とゼロサイズの `NSView` を使い、superview・subview・制約・戻り値・固定文字列を直接検査する。実ウィンドウや任意の待ち時間には依存しない。

[配線検査](../../../.claude/scripts/task39-wiring.rb)は、単一・グリッドから共通の接続処理へ到達する経路、attach 前の `current` 更新、現在端末を使う破棄処理、attach 成功時だけのスクロール予約を検査する。固定した変更前基準との比較で、PTY・サイズ通知・live resize の経路と、調査用ログを追加しないことも守る。自己検査には、呼び出し欠落や初期端末を使う破棄処理などの不正例を含める。

[実装検証報告](../../../docs/agent-output/task-39.md)には、TerminalUI の79テスト成功、配線検査と自己検査の成功、指定 Debug App ビルドの成功が記録されている。ビルドには既存警告 `Metadata extraction skipped. No AppIntents.framework dependency found.` が記録されている。本 ADR の起草では再実行せず、現行コードと記録を照合した。

### 修正後の実画面再現

[実画面報告の再実施2・PM判定](../../../docs/agent-output/visual-task-39.md)は、`TerminalMountCoordinator` 導入後の製品修正 `0f93809` を対象とする。隔離 Debug で2本のシェルセッションを使用し、調査用トレースを含めず確認した。現行 `TerminalView.swift` はこのコミットと差分がない。

| 再現 | 操作と選択 | 修正後の結果 |
|---|---|---|
| A | グリッドで Freesia 見出しへ AXPress 後、単一へ。選択は Iris のまま | 単一に SUNFLOWER_OUTPUT と1〜30を表示 |
| B | マウス相当の見出し操作で Freesia を選択後、単一へ | 単一に BLUEBELL_OUTPUT と1〜30を表示 |
| C | Freesia を選択したまま、見出し操作なしで3往復 | 単一は3回とも出力あり。グリッドも両端末に出力ありとの報告 |
| D | 単一表示で Iris→Freesia と選択を切替 | 両端末の既存出力を表示 |

修正前の A/B/C では単一が空白だった。修正後は担当報告で A/B/C/D の出力表示が記録され、PM は B の単一表示と C の3回目の単一表示の画像を直接確認して pass と判定した。ただし、C の各往復のグリッド画像は3回目のみ保存されており、全往復の画像が揃った検証ではない。

### 残る制限と寿命上の注意

タイル見出しにはアクセシビリティ経由の選択操作がない。[現行の見出し](../../Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift)はマウス操作のジェスチャで選択し、見出し全体の選択用 `accessibilityAction` を持たない。修正前の AX actions は `AXShowMenu` のみで、修正後も AXPress の応答が返るだけでは選択変更を意味しなかった。この欠落は空白の原因とは分けて扱い、本修正では解消しない。

弱参照台帳は、破棄された端末や旧コンテナを台帳自身が強参照で保持し続けることを避ける。強参照や裸のアドレスを使う台帳へ置き換えない。一方、弱参照は明示的な解放処理の代わりにはならない。現在のコンテナが生存し続ける間は、`detach` または同一コンテナの端末切替による解放が必要である。

`formerOwners` は現在の所有権が続く間の履歴であり、端末を同時に複数箇所へ表示する仕組みではない。所有者の解放後は履歴を消すため、解放済みの旧コンテナも再接続できる。この寿命境界を変更する場合は、後着拒否と正当な再利用の両方を再検証する。

また、単体テストの端末差し替えは `mount.current` を直接更新し、製品側の代入は配線検査で補っている。実 SwiftUI の破棄順序を単体テストだけで観測したものではなく、弱参照台帳の長時間のメモリ推移も今回の検証記録には含まれない。