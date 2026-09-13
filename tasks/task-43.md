---
id: task-43
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceComposerDestinationLabelTests.swift
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/AcceptanceTeamComposerDestinationLabelTests.swift
  - .claude/scripts/task43-wiring.rb
baseline_commit: "026ed2d"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/ComposerDestinationLabel.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/SessionGridView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/ComposerDestinationLabel+Agora.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardDetailView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamComposer.swift
  - docs/agent-output/task-43.md
---

## 目的

UX-03 / P1「入力先のプロジェクトと作業名を入力欄の近くに表示する」。単一・グリッドでは入力欄自身の送信先を、チームでは既存の送信操作を表示する。表示追加によって送信先・送信条件・選択状態を変更しない。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md` の UX-03 節。草案の保存先は `docs/agent-output/contract-draft-task-43.md`、凍結契約の配置先は `tasks/task-43.md` とする。本契約は Codex 草案を PM が 2026-09-13 に採択したもの。

調査時 HEAD は `35ec6b54c0eadac45082f9c4b7bd86e3984bae89`。以下の新規公開面・テスト名は提案であり、未実装・未凍結。テスト、配線検査、App ビルド、GUI 検証は実行していない。

## 入出力契約

### 事前条件

- 実装担当は Cursor。受け入れテストと rb は PM が作成し、未実装による red を確認して凍結する。Cursor はテストを作成・変更しない。
- レビューは実装者と別モデルで行い、本契約と凍結テストを渡す。
- `baseline_commit` と `TASK43_BASELINE` は同じ凍結コミットを指す。調査時 HEAD を自動採用しない。
- 新規パッケージ・依存追加・App 内のテスト配置は不要。既存の SessionFeature と、それに依存する DashboardFeature を使う。
- `depends_on: []` は既存コード上で単独実装できるという意味である。同じ View を変更する他タスクとの並列実行を保証しない。PM が凍結前に `allowed_paths` の交差を確認する。

### 確認した既存経路

| 対象 | 実コードで確認した状態・送信経路 |
|---|---|
| 単一 | `DashboardDetailView.singleDetail` が `router.selectedSession` からノードを取得し、`.appServer` の VM を `ChatSessionView` に渡す。`ChatSessionView.sendDraft()` はその VM の `consumeDraftForSend()`、`sendText(_:submit:)` を使う |
| グリッド | `DashboardDetailView` → `SessionGridView` → `PaneLayoutView` → `PaneTileView.tileContent` → `GridChatColumn` → `GridComposerBar`。`GridChatColumn.sendDraft()` はタイル自身の VM に送る |
| 作業名 | `ChatSessionViewModel.displayName`。未命名時の短い ID へのフォールバックも既存実装に含まれる。表示用に名前を生成し直さない |
| プロジェクト名 | `DashboardViewModel.projects` の `Project.name` を、宛先セッションの `projectID` で取得する。選択プロジェクトや作業ディレクトリの末尾名で代用しない |
| チームの分岐 | `TeamTimelineView.sendTeamMessage(_:)` が `AgoraComposerRouting.action(phase:canStartDiscussion:text:)` を呼ぶ |
| チームの開始可否 | `TeamTimelineAgoraPolicy.canStartDiscussion(canResolveProject:)` に `canResolveProjectForNewSession` を渡す。現在の判定はプロジェクトを解決できるかどうか |
| チームの親宛先 | `composerTargetNode` が `TeamComposerTarget.resolveRootSessionID(selectedSessionID:parentByID:)` で根を解決する。直近の親とは限らない |
| チームの入力可否 | `TeamComposer.canSend` は `targetDisplayName != nil && isReadyForInput && !trimmedDraft.isEmpty` |
| チームの準備状態 | 討論中は `composerIsReadyForInput == true`。それ以外は `store.isComposerReadyForInput`。後者は `refreshTimeline` が根セッションの状態から更新する |

注意点：

- `.discussing` と `.concluding` はともに討論への発言。`.idle`、`.ended`、`nil` は開始可能なら討論開始、それ以外は親セッションへの送信である。
- 討論開始可能でも、既存の入力欄の条件により送信ボタンが無効になることがある。開始可能を理由にボタンを有効化しない。
- `ChatSessionViewModel.isReadyForInput` は `.starting` のみ false。`.running`、`.awaitingApproval`、`.awaitingUserQuestion`、`.completed`、`.error` は true。状態名から独自に送信禁止を推定しない。
- 討論開始時のプロジェクト解決は `DashboardViewModel.startAgoraDiscussion` にある。`canResolveProjectForNewSession` と同じ式ではない。開始先を修正する変更や、選択プロジェクトを実際の討論先と断定する表示を追加しない。

### 純粋モデル：表示文言

以下は新規公開面の契約である。

`SessionFeature/ComposerDestinationLabel.swift` に置く。

```swift
public enum ComposerDestinationLabel {
    public enum Destination: Equatable, Sendable {
        case conversation(projectName: String?, taskName: String)
        case startDiscussion
        case discussionUtterance
        case parentSession(projectName: String?, taskName: String?)
    }

    public static func text(
        for destination: Destination,
        hasDestination: Bool,
        isReadyForInput: Bool,
        hasContent: Bool
    ) -> String
}
```

- 引数から文字列を返すだけにする。Foundation による文字列処理は可。
- SwiftUI、AppKit、ViewModel、Router、保存、ファイル、ネットワーク、プロセス、時計、環境変数に依存しない。
- `hasDestination`・`isReadyForInput`・`hasContent` は既存条件の値を受け取る。返り値を送信先や送信可否の決定に使わない。
- プロジェクト名は前後の空白・改行を除去し、nil または空なら `プロジェクト名不明`。
- 作業名は既存 `displayName` を使う。非空の名前は保持する。欠損・空白のみの場合の表示は `作業名不明`。命名や保存は行わない。

基本文言を次に固定する。

| Destination | 基本文言 |
|---|---|
| conversation | `プロジェクト名 / 作業名` |
| startDiscussion | `討論を開始` |
| discussionUtterance | `討論への発言` |
| parentSession、作業名あり | `プロジェクト名 / 作業名 — 親セッションへの送信` |
| parentSession、作業名なし | `親セッションへの送信` |

討論開始・発言に選択カードの作業名を付けない。親宛先には解決された根の名前とプロジェクトを使う。

送信不可の表示は、次の優先順で基本文言へ付加する。

| 優先 | 条件 | 付加する文言 |
|---|---|---|
| 1 | `hasDestination == false` | ` — 送信不可（送信先がありません）` |
| 2 | `isReadyForInput == false` | ` — 送信不可（入力を受け付けられません）` |
| 3 | `hasContent == false` | ` — 送信不可（メッセージを入力してください）` |
| — | 上記に該当しない | 付加しない |

これは既存の送信ボタン条件の説明であり、通信成功の保証ではない。復元エラーなど既存のエラー表示は保持する。

### 純粋モデル：既存の討論分岐との接続

DashboardFeature の `ComposerDestinationLabel+Agora.swift` に、既存の action を表示用の値へ変換する次の拡張を置く。

```swift
extension ComposerDestinationLabel {
    static func teamDestination(
        action: AgoraComposerAction,
        rootProjectName: String?,
        rootTaskName: String?
    ) -> Destination
}
```

対応は次の3件のみとする。

| 既存 action | 返す Destination |
|---|---|
| `.startDiscussion` | `.startDiscussion` |
| `.discussionUtterance` | `.discussionUtterance` |
| `.legacyRootSend` | `.parentSession`。渡された根の名前を使用 |

action の本文・議題は表示しない。phase の分岐や親探索をこの拡張へ複製しない。

`TeamTimelineView` は、既存送信処理と同じ phase・開始可否の式で `AgoraComposerRouting.action` を呼び、その返り値をこの拡張へ渡す。表示用の `text` 引数は `""` でよい。`sendTeamMessage(_:)` は従来どおり実際の送信時に再判定し、変更しない。

### View 配線

**単一・グリッド**

- `DashboardDetailView` から既存 `projects` の名前を渡す。
- 単一は対象 `session.projectID` で名前を取得し、`ChatSessionView` → `ChatComposer` へ渡す。
- グリッドは `[ProjectID: String]` の対応を `SessionGridView` → `PaneLayoutView` へ渡し、各 `PaneTileView` のセッションの `projectID` で取得する。そこから `GridChatColumn` → `GridComposerBar` へ渡す。
- 既存の呼び出し・描画テストとの互換性のため、追加引数は `projectName: String? = nil`、対応表は `projectNames: [ProjectID: String] = [:]` を既定値にする。製品の Dashboard 経路では明示的に実値を渡す。
- `Destination.conversation` の作業名には、入力欄が保持する VM の `displayName` を渡す。
- `hasDestination` は true、準備状態は既存 `canSend` または `viewModel.isReadyForInput`。
- `hasContent` は既存と同じ「trim 後の本文が非空、または添付が存在する」。画像だけの送信を不可と表示しない。
- グリッドの選択カードや `selectedSubAgentId` を宛先名に使わない。表示中の本文がサブエージェントでも、入力欄が送る先を表示する。

**チーム**

- `composerTargetNode` の `projectID` と `displayName` を表示用モデルへ渡す。
- `TeamComposer` へ新しい表示用 Destination を追加して渡す。既存 `targetDisplayName` は送信可否・編集可否の入力として保持する。
- `hasDestination` は既存 `targetDisplayName != nil`、準備状態は既存 `isReadyForInput`、本文の有無は既存 `trimmedDraft.isEmpty` の反転。
- 討論中は既存 `composerTargetDisplayName` が `"討論"` を返すため、根セッションがなくてもそれだけを理由に送信不可と表示しない。
- 現在の `宛先: ...` 表示をモデルの文字列へ置き換える。宛先がない場合にも表示する。

**配置・更新**

- 各入力欄の編集領域の直前に置く。本文のスクロール外、既存 composer の高さ計測内に含める。
- 単一・グリッドは `DSFont.caption` と `DSColor.chatTextSecondary` を使う。表示を help のみに隠さない。
- 狭い幅では表示を1行で省略できるが、全文を `.help` とアクセシビリティラベルに渡す。
- AX identifier は `ChatComposer.destination`、`GridComposer.destination`、`TeamComposer.destination`。
- 値を `@State`・永続化・タイマーへコピーしない。現在の引数と観測状態から再計算し、切替後に前の作業名を残さない。
- 既存の入力高さ、本文余白、幅計算、IME、添付、候補表示、フォーカス、送信・停止操作を維持する。

### 不変条件・スコープ外

- `AgoraComposerRouting.action`、`TeamComposerTarget.resolveRootSessionID`、`TeamTimelineAgoraPolicy`、`sendTeamMessage` の動作は変更しない。
- `composerTargetNode`、`composerTargetDisplayName`、`composerIsReadyForInput`、既存の readiness 更新を変更しない。
- `ChatSessionView.sendDraft`、`GridChatColumn.sendDraft`、`TeamComposer.send`、各送信可否の述語・disabled 条件を変更しない。
- `startAgoraDiscussion`、`submitAgoraUserUtterance`、`defaultProjectID`、VM の送信・復元・命名処理は変更しない。
- 選択カードと根が異なることを表示で説明する。選択状態を根に変更しない。
- ターミナルへの新しい composer、サブエージェント専用返信欄の改修、討論ルーティングの修正は対象外。
- 命名だけの追加 AI 呼び出し・課金セッションを製品にも PM 目視ゲートにも追加しない。
- テスト、rb、契約、検証入口は PM 所有であり `allowed_paths` 外。ハーネスの欠陥は PM に報告する。アサーション変更は禁止し、ハーネス修理も PM 承認後に限定する。

## 成功基準

### 1. Swift Testing：文言と既存分岐の合成

期待値は以下のリテラルから PM が書く。製品の文字列や分岐から期待値を生成しない。

**SessionFeature**

1. `Phlox / 入力欄改善` が完全一致する。
2. 別の宛先 `Garden / 調査` へ入力を変更すると、前の名前を残さない。
3. プロジェクト名の nil・空文字・空白・改行のみを `プロジェクト名不明` にする。
4. 作業名の空白のみを `作業名不明` にし、通常の日本語・英語・内部空白を持つ名前は保持する。
5. 4種類の Destination の基本文言を固定する。親の作業名がない場合も検査する。
6. 各 Destination について、3つの Bool の8組を検査する。送信不可理由の優先順位と、送信可能時に理由が付かないことを確認する。
7. 本文が空でも添付ありから渡された `hasContent == true` では、本文未入力の理由が付かない。
8. `.starting` と、それ以外の既存 readiness の違いをケースに反映する。復元エラーを独自の送信禁止に読み替えない。

単一とグリッドは同じモデル契約を使う。両画面が正しい値を渡すことは rb で別々に検査する。

**DashboardFeature**

既存 `AgoraComposerRouting.action` と新規 `teamDestination`、共通の `text` を実際に合成して検査する。ルーティングをモックに置き換えない。

| phase | `canStartDiscussion == true` | `canStartDiscussion == false` |
|---|---|---|
| nil | 討論を開始 | 親セッションへの送信 |
| `.idle` | 討論を開始 | 親セッションへの送信 |
| `.discussing` | 討論への発言 | 討論への発言 |
| `.concluding` | 討論への発言 | 討論への発言 |
| `.ended(.stopped)` | 討論を開始 | 親セッションへの送信 |
| `.ended(.utteranceLimitReached)` | 討論を開始 | 親セッションへの送信 |

さらに次を固定する。

- 終了後を自動的に親送信と扱わない。開始不可を自動的に送信不可とも扱わない。
- 討論開始の action でも、既存の target/readiness/content が満たされなければ対応する送信不可理由が付く。
- 討論進行中は選択カード・根の名前が変わっても `討論への発言`。本文・議題・カード名が混入しない。
- 実 `TeamComposerTarget.resolveRootSessionID` を使い、選択した子が `Garden / 子の調査`、根が `Phlox / 全体作業` の場合、親送信の表示が `Phlox / 全体作業 — 親セッションへの送信` になる。
- 子→親→根の複数段、選択なし、未知の選択 ID を検査する。親欠損・循環は既存 resolver の返り値を使い、新しい探索規則を定義しない。
- 同じ名前のセッションを別プロジェクトに置き、名前一致で宛先を取り違えない。
- 単一・グリッドに渡す conversation 表示は、上表の討論状態に影響されない。

開始不可・親送信は既存ルーティングに存在する分岐として凍結する。すべての組合せが通常の GUI から到達可能だとは主張せず、テストのために製品の空状態分岐を変更しない。

### 2. Ruby：実 View の配線と不変条件

`.claude/scripts/task43-wiring.rb` を PM が作成する。`task38-wiring.rb` と `task39-wiring.rb` の固定基準・文字列保護・宣言抽出・selftest を見本とする。モデルの条件分岐テストを文字列検索で代用しない。

必須検査：

- 単一・グリッド・チームの描画経路から、新規モデルの返り値を表示する `Text` に到達する。
- 新しい引数が中間 View で捨てられず、製品の Dashboard 経路が既定の nil／空辞書だけで動いていない。
- プロジェクト名は入力欄自身または解決済みの根の `projectID` から取得する。`router.selectedProjectID` やグリッド全体の選択名を代入する変異を拒否する。
- チーム表示用 action の phase・開始可否は `sendTeamMessage` と同じ入力元である。
- `targetDisplayName` の欠損時にも送信不可表示へ到達する。
- AX identifier、全文 help／アクセシビリティ、composer の計測範囲内への配置を確認する。
- 前記不変条件の宣言・関数・条件式を凍結 SHA の blob と比較する。ファイル全体の一律比較で許可された表示差分を拒否しない。
- 抽出不能・対象欠落は失敗とする。コメント、未使用 helper、`if false` 内に名前が存在するだけでは合格させない。

固定基準：

- `TASK43_BASELINE` は必須。契約の `baseline_commit` と解決後の SHA が一致すること。
- 未設定、プレースホルダ、不正 SHA、ブランチ名、`HEAD`・`@` 等、blob 取得失敗は非ゼロ終了。
- 凍結 SHA のテストと rb 自身の blob が作業ファイルと一致すること。
- 基準には受け入れテストが存在し、新規モデルと表示配線は存在しないこと。
- 実装後 HEAD の SHA を数値文字列として渡した自己比較も拒否する。固定 SHA が HEAD の祖先であるだけでは合格にしない。
- 比較対象は `git show <凍結SHA>:<path>` と現在の作業ファイル。`git show HEAD:<path>` を基準にしない。

`--selftest` は実ファイルを変更せず、メモリ上の正例と次の負例を検査する。

- 単一だけ未接続、グリッドだけ選択中カード名を表示、親名を子名に差替え。
- 終了後を親送信に固定、`.concluding` を討論外扱い。
- 討論開始可能を理由にボタンを有効化、画像のみを送信不可表示。
- 表示を help のみに移す、AX 欠落、宛先なしでラベルを非表示。
- 送信先・submit 引数・本文・disabled・フォーカス条件の変更。
- コメントや未使用コードによる偽装、構文抽出失敗。
- 基準の未設定・不正・契約不一致・実装後の自己比較。
- URL、補間文字列、文字列内の括弧・空白を壊さず比較できる正例。

### 3. 凍結・実行ゲート

PM は未実装による red の内容、selftest の結果、凍結後の変異検査を記録する。テスト自身の構文・fixture の欠陥を red の根拠にしない。

凍結時に `TASK43_BASELINE` を実 SHA に設定し、リポジトリルートから次を実行する。

```sh
~/.agents/scripts/compact-test task43-wiring-selftest ruby .claude/scripts/task43-wiring.rb --selftest
~/.agents/scripts/compact-test task43-wiring ruby .claude/scripts/task43-wiring.rb
~/.agents/scripts/compact-test task43-packages bash macos/scripts/run-swift-tests.sh SessionFeature DashboardFeature
~/.agents/scripts/compact-test task43-integration bash .claude/verify.sh
```

Swift テストの実行方法は既存 `macos/scripts/run-swift-tests.sh` を正本とする。統合の `.claude/verify.sh` は8パッケージ、更新隔離検査、`git diff --check` を含む。これを GUI 検証の代用にしない。

App ビルドは `macos` を作業ディレクトリとし、PM が用意した隔離ビルド先を `TASK43_DERIVED_DATA` に設定して実行する。

```sh
~/.agents/scripts/compact-test task43-app-build xcodebuild -project Phlox.xcodeproj -scheme Phlox -configuration Debug -derivedDataPath "$TASK43_DERIVED_DATA" -destination platform=macOS build
```

凍結前の検証入口に関する注意：

- 調査時の `.claude/scripts/ui-ux-verify-task.sh:50` には無条件の `exec` があり、既存 task-38・39 の分岐はその後にある。そこへ task-43 の分岐を追記しても到達しない。
- PM は task-43 の検証を実際に通る位置へ登録し、driver 経由の実走ログで確認する。Cursor の変更範囲には含めない。
- lint・静的解析・既存 E2E の適用範囲は PM が凍結時に確認し、未設定・対象外・実行不能を区別する。課金 CLI を起動する検査は本タスクの必須ゲートにしない。

### 4. PM 目視ゲート：課金不要の経路

**単一・グリッド**

PM 確認済みの `sessions.json` 復元失敗プレースホルダ経路を使う。入力欄は表示できるが transcript 本文は表示されない。

実コードには `SessionSpawnService.makeRestoreErrorChatSession` があり、`DisconnectedStructuredAgentClient` と既存 descriptor のプロジェクト・親・名前から VM を作る。ここでは `startNew`・`restore` を呼ばない。

- PM が確認済みの隔離データと起動方法を使い、別プロジェクトの名前付きプレースホルダ2件を表示する。任意の復元失敗方法を課金不要と見なさない。
- 単一で A→B→A と切り替え、各入力欄の名前とプロジェクトが一致する。
- グリッドで各タイルに固有の名前が表示され、別タイルの選択によって他の入力欄の名前が置き換わらない。
- 未送信の短文の入力・削除で、本文未入力の理由が切り替わる。Enter と送信ボタンは押さない。
- 通常幅と狭い幅で入力欄・送信操作・ラベルが到達可能。省略時の全文 help と AX の全文を確認する。
- プロジェクト名不明のケースも既存 placeholder データで表示する。
- transcript の末尾表示・長い会話のスクロール・実送信成功は、この経路では未検証と記録する。
- `.error` の既存 readiness は true なので、復元失敗だけを理由に送信不可が表示されることを期待しない。

**チーム：既存 fixture の調査結果**

| 確認したもの | 利用範囲と限界 |
|---|---|
| `DashboardFeatureTests/Fixtures/fake-agent.sh` | 課金 CLI を使わない PTY fixture。討論用の構造化チャットクライアントではない |
| `AcceptanceAgoraCoordinatorTests.swift` の `EffectsRecorder` | send・injectPrompt・summon を記録するテスト内の private fixture。製品 GUI へそのまま注入する入口ではない |
| `TeamTimelineViewLayoutTests.swift` | timeline の値・状態更新のテスト。討論全状態を実画面に表示する fixture ではない |
| `AgoraDiscussionCoordinator.phase` | `public private(set)`。外部から値を代入できる前提にしない |

調査した Team／Agora の製品ソースでは、討論全状態を表示する preview／dummy の入口は確認できなかった。

- まず同じプレースホルダを選択してチームへ切り替え、討論開始前の表示と入力欄の位置を確認する。これはコード上の経路に基づく確認案であり、本調査では GUI 到達を未実測。
- 進行中・結論中・終了後・開始不可・親送信は純粋モデルの合成テストで凍結する。GUI でも確認したとは記録しない。
- 討論ボタンを押して実 claude／codex／cursor を起動することを要求しない。
- 無課金の GUI 注入口が必要になった場合は別契約とする。本タスクへ製品用のテストモードを混在させない。
- PM 記録には、実画面で確認した状態とモデルのみで確認した状態を分けて残す。

## レビュー観点（Rubric）

- **宛先との一致**：名前は入力欄の VM または既存 resolver が返した根に属する。グリッドの選択カード、サブエージェント本文、選択プロジェクトを取り違えていない。
- **既存分岐の利用**：phase を独自に再判定せず `AgoraComposerRouting.action` の結果を表示へ変換している。終了後・結論中・開始不可を凍結表どおり扱う。
- **送信条件の維持**：表示用モデルがボタン・編集可否・送信処理を支配していない。`.error` や画像だけの入力を独自判断で禁止していない。
- **構造**：SessionFeature から DashboardFeature へ依存を逆流させない。名前取得のために VM へ保存項目や AI 呼び出しを増やさない。
- **到達性**：3種類の入力欄からモデルの返り値へ到達し、宛先なしでも理由が見える。既定引数だけで製品経路を通していない。
- **切替追随**：値をキャッシュせず、セッション・プロジェクト名・討論状態の更新に追随する。readiness の既存更新方式をこのタスクで修正しない。
- **レイアウト・アクセシビリティ**：ラベルは入力欄の近くに常時表示され、狭幅でも操作を妨げない。全文と AX identifier が取得できる。表示追加が既存の高さ計測に含まれる。
- **検証の誠実性**：Swift Testing が振る舞い、rb が配線を守る。凍結 SHA と比較し、自己比較で合格していない。プレースホルダの確認を transcript・実送信・討論全状態の GUI 確認へ読み替えない。

**分割案**：本契約は「既存宛先・操作の表示」に限定する。①討論全状態の無課金 GUI fixture、②開始可否と実際の開始先の解決方式の統一、③チーム readiness の更新方式変更は独立に失敗しうるため別タスクとする。検証入口の到達性修正は PM の凍結準備として扱い、UX-03 の実装差分へ混在させない。
## PM 採択時の調整（2026-09-13）

- 受け入れテスト・配線検査の作成は Cursor（テスト作成担当）に委譲し、PM が凍結前に RED と `--selftest` を確認する。分割案の①〜③は本契約に含めない（別タスク化はユーザー判断待ちとせず、UX-03 の完了条件を「既存の宛先・操作の表示」で満たすと PM が裁定。decision-log に記録）。
- PM 目視ゲートの実施（Debug ビルド・AX 操作・撮影）は Cursor 観測担当が手順どおり実行し、PM が PNG を確認して判定する。

## 受け入れ検査の敵対レビュー反映（2026-09-13、`docs/agent-output/task43-acceptance-adversarial.md` を PM 裁定）

- MUST1（verify 入口未登録）: 採択。PM が実装ディスパッチ前に `ui-ux-verify-task.sh` に task-43 分岐（selftest・`TASK43_BASELINE` 付き rb・SessionFeature/DashboardFeature `swift test`・`git diff --check`）を登録する。
- MUST2（コンパイル RED）: 却下。本 run は新規型導入タスクを「凍結時はコンパイル RED、実装後に変異検査で保護力を補う」運用と決定済み（decision-log 2026-09-12、task-40 注 9 と同じ）。
- HIGH3〜8・MEDIUM12（rb の保護力）: 採択。rb を強化する: 中間 View の実引数（`projectName`/`projectNames`/`taskName`/`rootProjectName`）の取得元と代入を経路ごとに追跡し nil・空辞書・別カード名・選択プロジェクト差替えを負例化（3）／到達性探索は文字列・非実行分岐（`if false` 等）を除外してから型スコープを保って実参照を追う（4）／チームの表示用 Destination の生成式から action を逆追跡し `sendTeamMessage` 本文を到達集合から除く、phase・開始可否の式を送信側と同一比較（5）／各ラベルへ渡す Bool（`hasDestination`・readiness・`hasContent`）の実引数を既存送信条件へ結び付け、否定欠落・`||`↔`&&`・trim 削除を負例化（6）／不変条件は宣言・条件式・呼び出し引数（footer の `canSubmit`・送信ボタン `.disabled`・フォーカス callback）を比較（7）／表示 Text の修飾・編集領域との順序・composer 高さ計測範囲を構造で検査し、`if x != nil` 形の条件も扱う（8）／表示変数名を固定しない・実在する `AgoraComposerAction` の case だけで負例を作る・`parens` 正例をアサートする（12）。
- MEDIUM9（名前正規化の未被覆）・MEDIUM11（循環 resolver）: 採択。SessionFeature テストに `" \nPhlox\t "`・作業名 `""`/`"\n\t"`/`" 調査 "`・`.parentSession(projectName: nil, taskName: "全体作業")` を追加。Dashboard テストは実 resolver の結果（a 開始→a）に対応する表示だけを期待する。
- MEDIUM10（画面×状態がモデル単体検査）: 採択（記録）。該当テストはモデル単体の確認であり被覆件数に数えない。実値の取得・引き渡しは rb（3・5・6）で保護する。
- MEDIUM13（ADR 0046 パネル高）: PM 裁定。宛先ラベルはキャプション 1 行（約 16pt）をエディタ上部に常設し、composer パネル全体の高さは ADR 0046 の約 80px からその分増える。これを採択し、フェーズ 5 で ADR 0046 に追記する。実合成の高さは PM 目視ゲートで測る。
