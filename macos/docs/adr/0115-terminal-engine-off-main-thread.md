---
status: active
last-verified: 2026-07-23
---

# ADR-0115: 端末エンジンをメインスレッドから分離する（SwiftTerm fork による TerminalCore 切り出し）

## ステータス

提案中（設計レビュー反映済み・v2）。独立レビュー2件（所有者基準レビュー + 外部技術レビュー）の指摘を反映し、**段階順序を「seam 分離を先、off-main feed を後」に修正**した。実装は段階0から着手予定。段階1（または段階3）で成功基準を満たせば以降は保留してよい＝この ADR は「全部やる」決定ではなく「この方向に、止められる段階で進む」決定である。

**スコープ（2026-07-24 追記）**: 本 ADR は **`.pty` 端末セッション**（シェル・Claude Code / Cursor CLI = SwiftTerm 描画）のカクつき向けである。本番 Release ビルド・実 9 セッションの Instruments 実測により、**グリッドで多いのは `.appServer` 構造化チャットセッション**であり、それらは SwiftTerm を通らずネイティブ SwiftUI（`ChatTranscriptView`）で描画されるため、本 ADR の off-main feed/draw では直らないことが判明した。`.appServer` グリッド（およびリサイズ時の 470〜643ms ハング）の対処は **ADR 0116** で扱う。段階0 の計測は 0116 の実測（`.appServer` 系）で一部先行済みだが、`.pty` 系の feed/shaping/draw 分解は未取得のまま残る。

## コンテキスト

### 解決したい問題

グリッドビューで複数セッションを同時表示し、その複数が活発に出力しているときにアプリがカクつく（フレーム落ち・入力のもたつき・スクロールの引っかかり）。これは平均 CPU% の高さそのものではなく、**メインスレッドが 1 フレーム予算（60fps なら 16.7ms）を超えてブロックされ、フォーカス中タイルの描画・入力処理が締め切りに間に合わない**というスケジューリング問題である。

### 成功基準（非機能要件・計測可能に）

計測条件は固定機種・固定リフレッシュレート・**Release ビルド**・実 PTY と実 TUI を含む再現シナリオで統一する。

- **フォーカスタイルは、背景タイルの出力量に関係なく実質 60fps を維持**: display-link ごとの missed deadline 数 ≈ 0、連続 missed frame の最大値 ≤ 1。
- **入力遅延**: `NSEvent` 受信 → フォーカスタイルの GPU 提出・表示までの p95 / **p99**（目標値は段階0で実測して確定）。p95 単独では短い大停止を隠すため p99 と missed-frame を併記する。
- **出力を 1 バイトも捨てない**: 過負荷は破棄でなく backpressure で吸収し、ランダムな chunk 境界でのバイト列ハッシュ検証で欠損ゼロを担保する。背景 backlog の上限と、フォーカス切替後の追従（収束）時間も測る。
- **idle**: CPU% だけでなく、MTKView の draw 回数・wakeups・cursor blink の有無を分離して測る。

### 根本原因の仮説（段階0 のプロファイルで確定する）

以下は「構造上の最有力仮説」であり、`feed` の parse コストが draw / shaping を上回り締め切り超過の主因である、という**切り分けそのものはまだ計測していない**（段階0 で feed / shaping / draw の占有時間を p50/p95/p99 に分解して確定する）。

1. **描画ではなく ANSI 解析（feed）がメインスレッド直列である**ことが最有力の主因候補。PTY 出力購読タスクが `@MainActor` で、各 chunk ごとに `feed` を呼ぶため、背景の全セッション分の parser・buffer 更新・状態観測がメインのキューを埋め、入力より先に積み上がる。
   - `macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift:382`（`outputTask = Task { @MainActor ... }`）, `:385`（`for await data in outputStream`）, `:391`（`coordinator.feed(data)`）
   - `macos/Packages/TerminalUI/Sources/TerminalUI/TerminalCoordinator.swift:41`（`@MainActor`）, `:42`（`final class TerminalCoordinator`）, `:175`（`feed`）→ `:176`（`terminalView.feed`）
   - 注: これは「feed がメイン直列である」というコード事実であって、「feed が締め切り超過の最大要因である」証明ではない。後者は段階0 で確定する。
2. **描画の GPU 化（Metal）は解決にならなかった**。隔離計測（Debug・12 タイル・合成負荷）で Metal は 3 条件すべてで悪化した（連続 約56%→約115%、バースト 約13.2%→約16.9%、静止 約0.0%→約2.8%）。
   - `buildDrawData` は `draw(in:)` ごとに呼ばれるが（`macos/Vendor/SwiftTerm/Sources/SwiftTerm/Apple/Metal/MetalTerminalRenderer.swift:546`）、行の再構築 `buildRowDrawData`（`:800`）は**行キャッシュ miss / dirty 時のみ**（キャッシュ判定は `:607` 近辺、参照は `:645`–`670`）。ただしキャッシュ署名に `yDisp`（スクロール位置）を含み、変化で `rowCache.removeAll()` するため（`:595`, `:609`）、**スクロールでは全行再構築になり得る**。これが今回の負荷で効いた。
   - カーソル点滅 Timer は「点滅対象カーソルを持つ renderer のみ」0.7 秒ごとに生成され、各 Timer は**自分の view** に `setNeedsDisplay` する（`:2617`–`2622`, `:2622` `view.setNeedsDisplay`）。集計効果として複数タイルが再描画されるが、1 つの Timer が全タイルを叩くわけではない。
   - 決定的なのは、GPU 化は「描く」しか肩代わりできず、**もし主因が feed on MainActor ならそれは残る**点。だから設計は feed も draw も両方メインから外す（下記）ことで、この仮説の当否に頑健にする。
3. **限定事項（未検証）**: 上記計測はすべて Debug ビルドの合成負荷（`yes` 相当の連続出力 / 140行・2秒のバースト）。Release では Swift の配列・頂点生成コストが変わる。静止時 2.8% の主因（カーソル Timer か）は未確定（MTKView は `isPaused=true, enableSetNeedsDisplay=true` で作られ常時 60fps ではない: `macos/Vendor/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift:282`–`283`）。→ 段階0 で確定する。

### 現状の結合（作り替えの障壁）

- `Terminal` は `open class` で、lock も actor も持たず、可変の `buffer` を直接共有し、parser 処理中に UI delegate を同期呼び出しする。→ メインスレッド以外から `feed` すると即データ競合。これが「メインから分離」する際の最大の障壁。
  - `macos/Vendor/SwiftTerm/Sources/SwiftTerm/Terminal.swift:288`（`open class Terminal`）, `:322`/`:326`（`buffer` var）, `:407`（`weak var tdel: TerminalDelegate?`。parse 中に多数箇所から同期呼び）, `:5505`（`DispatchQueue.main.asyncAfter` 内部使用）
- **delegate は「UI へ一方向に通知するだけ」ではなく、同期の戻り値を要求する問い合わせを含む**。これらを背景 executor からメインへ同期待ちにすると、逆方向のデッドロックやフレーム停止を再導入する。→ seam 設計で分離が必要（後述）。
  - `Terminal.swift:58`（`windowCommand(...) -> [UInt8]?` 戻り値あり）, `:122`（`cellSizeInPixels(...) -> (Int,Int)?` 同期問い合わせ）, `:183`（`getColors(...) -> (Color,Color)` 同期問い合わせ）, `:235`（`createImageFromBitmap(..., bytes: inout [UInt8], ...)` ホストへ inout 受け渡し）
- **描画・検索・選択が同じ可変 buffer を直接読む**。よって feed（buffer を破壊的更新）を別スレッドに移すと、メインの読み取りとデータ競合する。
  - 描画: `MacTerminalView.swift:674`（`terminal.displayBuffer.yDisp`）, Metal: `MetalTerminalRenderer.swift:560`（`let buffer = terminalView.terminal.displayBuffer`）
  - 検索: `SearchLineCache.swift:27`（`terminal.displayBuffer.lines.count`）, 選択: `MacTerminalView.swift:1657`–`1659`（`terminal.displayBuffer` を座標変換で直読）
- **公開されている dirty 情報は「行ごとのバージョン」ではなく「更新範囲（updateRange）」**であり、行データ自体が mutable reference。単純な「dirty row の最新値」だけでは resize/reflow・scrollback trim・alt buffer 切替・`yDisp` 変更・clear/erase を復元できない。
  - `Terminal.swift` の `updateRange(...)`（例 `:1178`, `:1190`, `:1372`）, `BufferLine.swift:13`（`public final class BufferLine` = 可変参照型）, `Buffer.swift:47`–`57`（`yDisp` セッタ）, reflow（`Buffer.swift:229` 近辺）
- `TerminalView` が `NSView, NSTextInputClient, TerminalDelegate` を**同一インスタンスで兼ねる**（頭脳と手足が癒着）。描画・入力はメイン固定: `draw(_:)`（`MacTerminalView.swift:665`）, `keyDown`（`:957`）, `interpretKeyEvents`（`:1003`）, `insertText`/IME（`:1230`）。クラス宣言 `:41`。
- 60fps の**表示更新予約**（16.67ms スロットル）は `queuePendingDisplay()`（`AppleTerminalView.swift:1703`, `fps60 = 16670000` `:1707`）と `queueMetalDisplay()`（`:1725`）にある。`updateDisplay(notifyAccessibility:)`（`:1568`）はその予約で走る**コールバック側**で、dirty range 計算とアクセシビリティ通知（`:1651`–`1656`）を行う。
- CTLine/グリフ生成は `AppleTerminalView.swift:1270`（`Pre-create CTLines` → `:1274` `CTLineCreateWithAttributedString`）。glyph atlas は renderer インスタンスごと（`MetalTerminalRenderer.swift:196`–`197`, `:238`–`241`）＝タイル数分だけ重複。
- PTY は 4KB 単位で `AsyncStream<Data>` に供給し、`bufferingNewest(2048)` で過負荷時に**古い chunk を破棄**する（`macos/Packages/PTYKit/Sources/PTYKit/PTYManager.swift:17`, `:24`, `:59`–`61`, 読み取りは専用 GCD キュー `:169`–`184`）。破棄は escape sequence を壊すため、backpressure（read 停止）で置き換える。
- SwiftTerm はローカル fork（`macos/Vendor/SwiftTerm`）で、参照するのは **`TerminalUI` パッケージのみ**（`macos/Packages/TerminalUI/Package.swift` が `path: "../../Vendor/SwiftTerm"` 参照）。→ fork 改造の影響範囲は `TerminalUI` に閉じている。

## 決定

SwiftTerm の fork を進め、端末の「頭脳（ANSI 解析・画面状態）」を **AppKit 非依存の `TerminalCore`** として切り出し、**メインスレッドから外す**。描画は各 `TerminalView` に 1 個の構造をやめ、**単一の Metal compositor** に集約する。背景タイルには**資源予算（QoS・worker 上限・PTY backpressure）**を課し、フォーカスタイルのフレーム予算から隔離する。

ただし全面移行を一括で行わず、**止められる段階**に分割する。**最重要の修正点（レビュー反映）**: 「feed を off-main にする」施策は、単一 writer の core・renderer 用の immutable snapshot 境界・同期 delegate の排除（＝ seam）が**先行実装されていない限り安全に実施できない**（さもなくば描画/検索/選択とのデータ競合、および parse 中の delegate がメイン外で AppKit を叩くクラッシュを踏む）。よって seam を先、off-main feed を後に置く。

### 目標 / 非目標

**目標**
- フォーカスタイルのフレーム予算を、背景タイルの出力量から構造的に隔離する。
- ANSI 解析・グリフ整形・描画をメインスレッドから外し、メインは入力・IME・合成トリガーだけにする。

**非目標**
- 現行の単体（非グリッド）表示の見た目・機能・操作性を変えること（回帰させない）。
- SwiftTerm upstream への追従維持（fork 改造を選ぶ以上、追従は切る前提でコストとして受容する）。
- 平均 CPU% の最小化そのもの（指標はカクつき＝締め切り遵守）。

### 目標アーキテクチャ（3層 + 資源制御）

```text
PTY I/O（専用 GCD キュー・actor 外）
  ↓ backpressure（過負荷は read を suspend、データは捨てない）
TerminalCore 群（非 MainActor・session 固有 executor・単一 writer）
  … ANSI parser + 画面 buffer の唯一の書き手
  … UI を呼ばず即答する immutable TerminalEnvironment（cell size / palette / trust）
  … 画像・通知・clipboard は「順序付き副作用イベント」として外へ発行
  ↓ immutable / versioned RenderDelta（BufferLine は渡さない）
Render Scheduler（deadline・予算配分：フォーカス最優先 → 残予算で背景）
  ↓
Metal Compositor（単一 MTKView・1 render pass）
  … 共有 glyph atlas／terminal ごと永続 row buffer／scissor rect で 12 タイル
  ↓
Main Thread: NSEvent / IME / first responder / 最小の view 操作 / coalesced signal
```

要点:
- **renderer・検索・選択が可変 terminal buffer を直接読む構造を廃止**する。TerminalCore は変更行の immutable snapshot / copy-on-write row page を渡す。
- **同期戻り値の delegate は分離する**: cell size・palette・trust 状態など UI を介さず即答できるものは immutable `TerminalEnvironment` として core が持つ。画像・通知・clipboard・ベル等の副作用は「順序付き副作用イベント」として core の外へ出し、メイン側が順序どおり適用する（背景 executor からメイン同期待ちにしない）。
- 同じ行が 100 回更新されても GPU 更新は最新 1 回。「**背景の状態更新はいつか必ず追いつく／背景フレームは捨ててよい**」を分離原則にする。
- スクロールは `yDisp` 変更で全行再生成しない。visible row をリングバッファで保持し、新規露出行だけ再整形・再アップロード。vertex に絶対ピクセルを焼かず `terminalID / row / column` を持ち、vertex shader が tile 原点・セルサイズ・スクロール原点を uniform から計算する。
- タイルごとの 16.67ms 予約（`queuePendingDisplay`/`queueMetalDisplay`）による thundering herd をやめ、中央 frame scheduler に一本化する。
- 資源制御: 背景 parse worker の QoS を `.utility` 以下、worker 数を上限（メイン/render 用コアを残す）、frame 締切前は背景 GPU 仕事を出さない、背景は前フレーム texture を使い回す、過負荷は PTY read の suspend/resume で backpressure。

### 切り出す境界（seam）

fork では「既存 `TerminalView` を actor で包む」のではなく、以下を分離する:
- `TerminalCore`（AppKit 非依存・単一 writer の状態機械 = 既存 parser の大半を再利用）
- immutable `TerminalEnvironment`（同期問い合わせ delegate = `cellSizeInPixels`/`getColors`/`windowCommand`/trust を UI を呼ばず core 内で即答）
- 「順序付き副作用イベント」チャネル（画像 `createImageFromBitmap`・通知・clipboard・ベル）
- immutable `TerminalRenderSnapshot` / `RenderDelta`（最低限: `terminalEpoch`・`layoutEpoch`・`bufferKind`（normal/alt）・構造変更イベント（resize/reflow/clear/scrollback trim/yDisp）・全量 snapshot へのフォールバックを持つ。renderer に既存 `BufferLine` を渡さない）
- AppKit 用 **input adapter**（keyDown/IME をメインで受け、engine executor へ渡す）
- Metal compositor 用 **render adapter**
- `Terminal.swift:5505` の `DispatchQueue.main.asyncAfter`（synchronized output タイムアウト）は engine executor へ移す。

### 段階計画（各段階で止められる／捨て仕事にならない・seam を先に）

- **段階0: 計測基盤と前提確定**（前提の地固め）
  - Release ビルドで測り直す。**feed / shaping / draw の占有時間を p50/p95/p99 に分解**し、締め切り超過の主因を確定する（＝根本原因仮説の検証）。タイル別 fps・dirty 行数・入力→反映 p95/p99 の計器を入れる。静止時 2.8% を CPU・draw 回数・wakeups・cursor blink 有無に分離して主因を確定する。成功基準の目標値を確定する。
- **段階1: 背景タイルのスナップショット + 中央 frame scheduler**（安価・seam 不要・単独リリース可）
  - 画面内の非フォーカスタイルを静止画表示にし、フォーカス/クリック/IME 開始で即 live へ戻す。タイルごとの表示更新予約を中央 scheduler に統一。これは**描画側**のカクつきに効く（feed はメインに残るため入力もたつきは残りうる）。**段階0 で draw が主因なら、ここで成功基準を満たし以降を保留できる。**
- **段階2: seam の確立**（off-main feed の前提・ここが hard part）
  - 単一 writer の `TerminalCore` executor、renderer/検索/選択が可変 buffer を直読しない immutable snapshot / delta 境界、同期戻り値 delegate の `TerminalEnvironment` 化と副作用イベント化。まだ feed はメインで回してよい（境界だけ先に作る）。
  - **受け入れ基準に ThreadSanitizer クリーンを必須で含める。**
- **段階3: feed / PTY read を core executor へ移す + PTY backpressure**（入力もたつきの根治）
  - 段階2 の境界が入って初めて安全。メインへは coalesced な「最新 generation あり」信号だけを送る。backpressure は high/low watermark・最大保留バイト数・停止中の状態機械・終了時 drain・再開時の公平性を定義し、破棄はしない。**受け入れ基準に ThreadSanitizer クリーン + バイト欠損ゼロ検証を含める。**
- **段階4: 単一 compositor（共有 atlas・1 surface）最小版**（ASCII/ANSI・背景色・通常カーソル・固定セル幅の垂直スライスで性能検証）
- **段階5: 端末完全性**（Unicode 幅・結合文字・絵文字・画像・選択・コピー・検索・IME・アクセシビリティ・mouse reporting・resize・scrollback）

各段階の停止条件（成功基準の全項目で判定。フォーカス 60fps 単独では不足）: フォーカス 60fps 維持・入力 p95/p99 目標・**出力欠損ゼロ**・**背景 backlog 上限**・**フォーカス切替後の収束時間**・**IME/選択/検索/resize の回帰なし**を実測で満たしたら、以降の段階を保留し再評価する。

## 結果

**ポジティブ**
- 背景セッションの出力量からフォーカスタイルのフレーム予算を構造的に隔離でき、カクつきの根本に到達する。
- 段階1（描画側）は seam 不要で単独リリース可能。段階0 で draw 主因と分かればこれだけで足りる可能性がある。
- 描画・状態・入力の関心が分離され、以後の保守・拡張が容易になる。

**ネガティブ / 受容するコスト**
- fork の保守コスト（upstream SwiftTerm 追従を切る）。改造は「状態通知 API」と「Phlox renderer」に分離し、既存 renderer の直接大改造を避けて競合面を最小化する。
- 端末完全性の回帰リスク（段階5）。**最大のリスクは性能ではなく完全性**（TUI・IME・コピー・選択・リサイズのどれかを壊すと CPU 改善の価値を相殺する）。
- 並行化の正しさ検証コスト（段階2・3 の ThreadSanitizer クリーン維持、境界の同期戻り値・副作用順序の検証）。
- backpressure で子プロセスが block されるため、極端な高出力時は「出力が詰まる」体感が出る。データ破損よりは望ましいが、許容範囲は要検証。backpressure 状態機械（watermark・drain・公平性）自体の複雑性も負債。
- 複雑性の増加（executor・scheduler・compositor の新規機構）。

## 代替案

1. **Metal 有効化のみ（描画だけ GPU 化）** — 却下。隔離計測で 3 条件すべて悪化。主因が feed on MainActor なら残り、入力もたつきを解けない。
2. **スナップショット + 描画レート制限だけ（エンジン分離しない）** — 段階1 に相当。段階0 で draw が主因と分かればこれで足りる。だから段階1 を明示的な判定点に置く。ただし feed が主因なら入力もたつきは残る。
3. **別の端末ライブラリへ移行** — 却下。移行コストが大きく、現 fork に当てている bug fix（alt buffer の column shrink 時の cell trim: `TerminalUI/Package.swift` コメント参照）等の資産を失う。
4. **既存 `TerminalView` を actor で包む／feed だけ background Task に移す** — 却下。`Terminal` が lock なしの可変 class で buffer/parser/delegate を直接共有し（`Terminal.swift:288`, `:407`）、描画/検索/選択が同じ buffer を直読する（`MetalTerminalRenderer.swift:560` ほか）ため、境界（段階2）なしに executor だけ移すと即データ競合。この却下理由は「段階1 で feed off-main」案（v1 の誤り）にもそのまま当てはまるため、段階順序を修正した。

## オープン課題

- 入力→反映 p95 **/ p99** の目標値（段階0 で確定）。
- 締め切り超過の主因が feed か draw か shaping か（段階0 のプロファイル分解で確定）。
- 静止時 2.8% の主因確定（未検証。段階0）。
- Release ビルドでの再計測値（未取得）。
- `RenderDelta` の詳細形状（`terminalEpoch`/`layoutEpoch`/`bufferKind`/構造変更イベントの粒度、copy-on-write row page の単位、全量 snapshot フォールバックの発火条件）。
- 同期戻り値 delegate を `TerminalEnvironment` として core 内で即答する対象の網羅（`cellSizeInPixels`/`getColors`/`windowCommand`/trust ほか）と、副作用イベント（画像/通知/clipboard/ベル）の順序保証。
- backpressure の状態機械（high/low watermark・最大保留バイト数・停止中の挙動・終了時 drain・再開時の公平性）と、バイト欠損ゼロの検証手段（ランダム chunk 境界のハッシュ照合）。
- 段階2・3 の受け入れ基準としての ThreadSanitizer クリーンを CI にどう組み込むか。
- top-level `docs/` と `macos/docs/` の ADR 番号系列が別立てである点（本 ADR は macOS アプリ個別として `macos/docs/adr/` に採番）。
