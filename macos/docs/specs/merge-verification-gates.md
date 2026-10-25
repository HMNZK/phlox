---
status: active
---

# 問題定義: 統合前検証と実機シナリオの鮮度

本書は2026-10-25の実装契約。調査基準はローカルdev `90a0c80109283b8498569815b4d44ec8e58a7351`。**監査表はこのOIDの静的確認であり、実装後の状態・検査・実機結果を示さない**。既存のE2E設計・受入仕様を再利用し、共通マージツールは変更しない。実装担当と合意した入口は末尾に示す。

## 解決したい問題

通常テストの成功をE2E・iOS・実機確認の成功と取り違えない。古いシナリオや別ビルドの合格を流用せず、必要な検証の欠落を統合前に検出する。一方、任意検査や人操作待ちを一括起動して不要に停止させない。

## 現状（調査の根拠つき）

以下の行は上記OIDに対する静的確認。過去文書の実測結果を今回再検証したものではない。

| 根拠 | 確認した不足・再利用先 |
|---|---|
| `macos/scripts/run-swift-tests.sh:45,94-103,165-205` | 標準入口の既定はAgentDomain/DesignSystem/MessageStore/SessionFeature/DashboardFeature/SimulatorBridgeKit。ControlServer/AppBootstrapは既定外。絞り込み・除外が可能 |
| `ios/Makefile:31-41,49-64` | 既存の生成・build・PhloxKit単体・raw値lint。snapshotは別入口。pipefailなしの`xcodebuild \| xcpretty`はbuild失敗を成功に見せ得て、xcprettyが無ければ再実行するため、初回buildの終了コードを保持する修正が必要 |
| `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/E2EControlServerTests.swift:14-25` | fake E2Eも`PHLOX_E2E=1`なしでは無効。広い`E2E`フィルタは実CLI依存テストも選び得る |
| `ios/PhloxMobileSnapshotTests/DesignSnapshotRenderTests.swift:67-70` | 環境変数なしでは画像出力をせずreturn。testのexit 0だけでは撮影・比較の証明にならない |
| `release/dev-to-main-checklist.html:10,801,833,866` | 7月のOIDを表示し、項目IDだけをキーにチェックを保存・コピー。現在のビルド・シナリオ版との照合がない |
| `ios/scripts/prepare-ad-hoc.py:159-165` | revision・版・buildを記録するが、HEAD取得はexport後。ビルド開始時の入力を保証せず、本契約の正式な来歴としては不足。実機インストールも別の未検証項目 |
| `ios/docs/specs/session-activity-parity.md:97-107` | 状態・完了確認・中断・履歴・描画・読み上げのACがある。実機結果の代用にはしない |
| `ios/docs/delivery/0036-mobile-desktop-parity.md:111-115,125-127` | skip・未検証・旧失敗と候補更新の記録がある。古い件数やテスト削除を現在の動作保証に読み替えない |

調査元リポジトリのローカル設定は`gitflow.verifyCommand=bash macos/scripts/run-swift-tests.sh`。`releaseCommand`は版別記録・ノート・appcastの存在とDMGのstapler確認で、実機記録の内容を照合しない。これはGit管理外の調査時設定であり、本書は設定を変更しない。

## 成功基準（検証可能な形で）

| ID | 必須条件 | 判定方法 |
|---|---|---|
| G1 | dev/verify/mainのどの反映前にも、同じ最終統合候補でmacOS全19パッケージを標準入口から実行し、iOS lint/単体/build・指定fake E2Eも実行 | 候補外に段階別生ログ、候補OID、終了コード、個別テスト結果を保存。必須段階や新パッケージが検査対象から漏れれば非0 |
| G2 | 0件、必須skip、未知の結果形式、未設定、環境不足を合格にしない | 下記否定テスト。通常検査の対象外opt-in skipは別記し、fake E2E必須集合とは混ぜない |
| G3 | 要件・コード・テスト・実機シナリオの対応があり、影響のある差分は独立した別担当（AI可）の内容レビューを通る | 対応表の参照検査と、具体的な差分に結び付いた独立レビュー記録。意味の十分性は自動保証しない |
| G4 | main反映前に、必要な実機シナリオの実施結果・ビルド・実際に配布する成果物の対応を確認 | 必須フィールド・成果物/証拠ハッシュ・候補の実ビルド入力・シナリオ版・結果を照合。既存release検査のDMGと別成果物なら非0 |
| G5 | 文書保守だけでOIDが変わった場合、同じ実機ビルドを正当に再利用できる | 下記入力比較が一致する例を受理し、ソース/設定/資源/シナリオが変わる例を拒否 |

## 具体契約

### 1. 接続先と実行タイミング

- `macos/scripts/verification-gate.py quality`から既存スクリプト・Makefileの品質検査を呼ぶ。コマンドを別実装で再構成して品質を落とさない。必要な出力先指定と失敗を正しく返す修正は実装担当の範囲。
- 共通`~/.agents/scripts/gitflow-merge.sh`が文書保守後の隔離候補で呼ぶ`gitflow.verifyCommand`へ接続する。`GITFLOW_MERGE_CANDIDATE`と実際のHEADが一致することを確認し、開始・終了時に候補とビルド入力の不変性を確認する。手元の古いgreenは代用不可。
- `gitflow.releaseCommand`には既存の署名・版・ノート・appcast・stapler確認を先行して残し、`macos/scripts/verification-gate.py release --dmg <同じ実DMG> --evidence-root <証拠基準ディレクトリ> [--record <記録JSON>]`によるmain用の実機記録照合を追加する。releaseサブコマンド自身が既存署名検査を代行するわけではない。ローカルGit設定の接続は、実装・検証後に親担当が行う。共通ツールを変更せず、別のmerge操作へ迂回しない。
- devとverifyへの統合は実機未実施でも自動検査が合格すれば進められる。verifyで検証するビルドを固定し、実機結果を保存する。mainへの統合は自動検査と必要な実機記録の両方を要求する。
- docs保守でシナリオ内容が変われば古い実機結果は使えない。更新前の検査を通したことを理由に最終候補の検査を省かない。

個別テストID・生ログ・機械可読結果・実効設定は、共通マージ経由なら`$GITFLOW_VERIFICATION_DIR`配下のcandidate外へ保存する。外側のcompact-testが成功ログを要約しても証拠が残るようにする。通常の直接検証はそのworktreeの固有`.verification/<作業名>/`へ保存する。managed-buildの再生成できる出力と永続させる検査証跡を分離し、成功時にcandidateが削除されても証跡を失わない。

管理ビルドのsessionと証跡ディレクトリを過去の日付名へ固定しない。sessionは`GITFLOW_VERIFICATION_DIR`の末尾名、ブランチ名、短縮HEADの順に解決する。使用できるのは英数字と`_ . -`で、`.`・`..`は禁止。各実行を識別できる値と出力先を記録し、再生成用キャッシュの再利用単位と、上書きしない実行証跡の単位を区別する。

### 2. 必須の自動検査

入口自体の否定テストと標準入口の出力回帰テストもqualityから実行する。これらの成功だけをmacOS/iOS・fake E2E・実機の成功と読み替えない。

1. macOSは`macos/scripts/run-swift-tests.sh`へ下記19パッケージを明示し、同じ素材準備・直列化・実Git別パスを維持する。`macos/Packages/*/Package.swift`の集合と必須集合を照合し、新パッケージを黙って対象外にしない。対象の追加・削除は契約とレビューを更新する。
2. iOSは既存のraw値lintとPhloxKit全単体検査、XcodeGen生成後の`PhloxMobile`コンパイル・リンクを実行する。既存`ios/Makefile`の入口を保ち、build出力先を管理ビルド領域へ指定する。xcprettyパイプ/自動再実行を修正して初回xcodebuildの終了コードを保持する。xcodegenは検出した絶対パスを使い、既存の`/opt/homebrew/bin`にも対応する。必要なツールが無ければ理由付き非0。端末起動不要の`generic/platform=iOS Simulator`を利用でき、`iPhone 16`という名前の端末の存在を合格の前提にしない。
3. fake E2Eは次の**関数IDだけ**を明示選択して直列実行する。`PHLOX_E2E`を通常検査全体へ一括exportせず、この段階の子プロセスだけに`1`を渡す。広い`--filter E2E`を使わない。

macOS必須集合は`APNsClient`, `AgentConfigKit`, `AgentDomain`, `AppBootstrap`, `ClaudeAgentKit`, `CodexAppServerKit`, `ControlServer`, `CursorAgentKit`, `DashboardFeature`, `DesignSystem`, `HookServer`, `LocalHTTPServer`, `MessageStore`, `MobileProxy`, `PTYKit`, `SessionFeature`, `SimulatorBridgeKit`, `StructuredChatKit`, `TerminalUI`。開始OIDで19パッケージすべてにテストがあることを確認した。通常検査を8パッケージだけで完了扱いしない。

親環境の`SWIFT_TEST_SKIP/FILTER/PACKAGES/SERIAL_PACKAGES/GIT_SUITES`を含む対象・並行性・構成の変更指定と、任意のパッケージ位置引数は拒否またはゲートの固定値で上書きする。標準の直列化と実Git別パスを空指定で無効化できないようにし、適用したパッケージ・filter/skip・並行性・構成・出力先を記録する。fake段階に必要なfilter/envのみ、その段階でゲートが設定する。

| suite | 必須関数ID（括弧は省略） |
|---|---|
| `E2EFakeAgentSmokeTests` | `fakeAgent_inputEchoThenSilenceReachesIdleCompletion`, `fakeAgent_exitAfterZeroCompletesWithoutStuckRunning` |
| `E2ESessionLifecycleTests` | `sessionLifecycle_hookDrivenSendAndStopCompletion`, `sessionLifecycle_exitAfterOneRoundTripThenCompletes`, `sessionLifecycle_killTerminatesChildProcess` |
| `E2EControlServerTests` | `s4_phloxListSendRead`, `s4_invalidTokenAndMissingRecipient`, `s5_apiSpawnRecordsParentAndKillParentEndsChild` |
| `E2EPersistenceTests` | `s2_restartRestoresSessionNamesAndProjectPlacement`, `s2_corruptSessionsJSONStartsWithEmptyState`, `s6_projectPlacementSurvivesRestart`, `s9a_bypassTogglesClaudeHooksSettingsFileSelectionAndContent` |
| `E2ERealPTYTests` | `realPTY_deterministic_inputEchoThenSilenceReachesIdleCompletion` |

開始OIDで上記は13関数。`E2ERealPTYTests`の対象は`/bin/sh`で完結する決定論的テストで、実claude/codex/cursorのテストではない。テスト名の存在確認だけでなく、テストランナーの個別結果から必須IDの実行・成功を照合する。追加/削除/改名時は対応表と集合をレビューして更新し、実行結果に合わせて黙って集合を縮めない。未知の出力形式、0件、欠落、skip、known issueによる必須項目の未達、失敗は非0。

通常検査内の既存の任意opt-inテストは未実行ならskipとして保存し、成功件数に加えない。任意検査のskipだけを理由に通常検査を失敗させず、別段階のfake E2E必須集合は省略を許さない。通常検査の実失敗・未知の必須範囲縮小は許可しない。

通常検査で既存許容するknown issueは、`GitHistoryWorkflowTests.GTWRegression_改名前の名前を再利用しても利用順を混同しない`のADR 0209「旧名を再利用したブランチの利用順を区別できない」だけ。根拠は開始OIDの`macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/GitHistoryWorkflowTests.swift:111`。観測した場合はID付きで未解決として別記し、成功件数へ加えない。未知のknown issueは非0。fake必須13関数はknown issueもskipも不可。

実CLI依存テスト、人操作/ACK待ち、XCUITestを自動ゲートで一括起動しない。`PhloxMobileSnapshots`全suiteや`make snapshot`も人操作待ちを含み得るため必須自動ゲートへ無条件追加しない。画像が必要なら別途対象を限定し、PNG生成と人の比較を分けて記録する。xcodebuildのbuildをテスト・実機確認と呼ばない。

テスト実行は`~/.agents/scripts/compact-test`、ビルドとビルドを伴う検査は`managed-build`に従う。Xcode・SDK・端末の不足、依存解決失敗、未設定は理由付き非0。新規依存・新規ツールを自動導入しない。

### 3. 対応表とシナリオ変更のレビュー

既存AC本文を正本とし、小さな追跡用JSON `release/verification-scenarios.json`に対応を保持する。独立レビューは`release/verification-reviews.json`、実機結果は`release/verification-records.json`に保存する。各JSONは`schemaVersion`を持つ。下表は必須の情報を示すもので、実際のフィールド名・型・CLI引数は実装担当のコードで確定し、二重定義しない。

| フィールド | 内容 |
|---|---|
| requirement | 仕様パスとACのID |
| codePaths / testIDs | 関連する共有コード・macOS/iOSコード範囲と実在するテストID。新規/未分類パスを無視しない |
| scenarioID / revision | 安定ID、意味を変えたときの版。本文のハッシュも比較する |
| procedure / expected | 実機の前提・操作・観察可能な合格条件。既存文書への参照でよい |
| method / required | 自動・描画・実機の区別と、リリースに必要な検証。実機をシミュレータへ置換しない |

開始時の対応例は次のとおり。これだけで製品全体のシナリオが十分とはしない。

| 要件 | 対象コード範囲 | 既存テスト | 必要な実機シナリオ |
|---|---|---|---|
| session-activity-parity AC-1〜4 | 共有状態/描画部品、iOS SessionList・SessionDetail、Mac完了確認API | `ChatActivityStateIOSTests`, `CompletionParityAcceptanceTests`, 共有状態テスト | 実行→前面/別会話/背面で正常完了→確認、中断との競合、再接続 |
| 同 AC-5・7 | iOS `ChatAutoFollowPolicy.swift`, `SessionDetailView.swift` | `HistoryPullAcceptanceTests` | 実指で引く/離す/取消、履歴なし、新着中の位置維持、VoiceOver操作 |
| 同 AC-6 | 共有DesignSystem、iOS一覧/会話ヘッダー | `ChatActivityComponentsWhiteboxTests`（ファイルは`DSChatActivityComponentsTests.swift`）、共有`ChatActivityStateTests`、対象の描画テスト | ライト/ダーク、Reduce Motion、文字拡大で状態表示・動き・重複読み上げを確認 |
| 同 AC-8 | iOS AppRoot・Usage・設定画面、共有UsageBarStyle、使用量API | `UsageParityAcceptanceTests`, `UsageViewModelTests` | 横棒/数値の設定保存、60秒取得と背面/切断/ロックでの停止、期限切れ・欠損・失敗回復、詳細/VoiceOver |
| 同 AC-9 | iOS NewChat・ネットワーク、Mac新規会話・ControlServer/AppBootstrap | `NewChatParityAcceptanceTests`, `NewChatParityClientAcceptanceTests`, `NewChatParityRoutingAcceptanceTests`, `SessionResumeHistoryTests` | 通常/worktree各起点、Claude/Codex履歴再開、候補除外・選択切替、不正指定拒否、送信0/1回 |
| E2E設計 S1〜6・9-A | SessionFeature/DashboardFeature、HookServer/ControlServer/AppBootstrap、CLI | 上記13関数 | fake経路の成功は実Mac↔iPhone接続の成功とは別に扱う |

追加した2フローのcatalog参照はそれぞれ`ios/docs/specs/session-activity-parity.md#AC-8`と`#AC-9`、`requirementIDs`もそれぞれ`["AC-8"]`・`["AC-9"]`とする。既存AC行ハッシュの方式を再利用し、新たなMarkdown節パーサーは加えない。初期対応表で直前の統一要件を落とさないための追加で、全製品シナリオの網羅を意味しない。

要件・コード・テストの差分と対応表から、影響するシナリオの**本文を読む独立レビュー**を必須とする。実装者とは別担当が行い、AI担当でもよい。レビューは比較元/先OID、正規化した内容差分ハッシュ、影響ID、更新した内容または「影響なし」の具体的理由、担当識別子・担当種別（`ai`/`human`）・日時・判定を保存する。照合は候補OIDの一致ではなく、パス・追加/削除・モード・変更前後の内容ハッシュを安定順に正規化した差分を根拠にする。固定の`release/verification-reviews.json`と`release/verification-records.json`だけはレビュー差分比較から外し、記録追加による循環を防ぐ。AIレビューを人の承認・実機操作・観測の証言として記録しない。要件の解釈変更、必須項目の削除・対象外化が必要な判断はユーザーへ戻す。

レビューには明示的な`decision`を必須とし、対象の内容差分について最新の判定が`pass`のときだけ受理する。古いpassがあっても、後続の要修正判定を無視して通さない。`review-input --base <比較元> [--target <対象>]`は読み取り専用で、target未指定時はHEAD。標準出力に`schemaVersion`・`baseOID`・`targetOID`・`diffSHA256`・正規化した`changes`を出す。対象シナリオとの対応と本文は独立レビューで確認し、出力を得ただけでレビュー済みやpass判定と混同しない。同入口はJSONや作業ツリーを書き換えない。

全変更で全シナリオの版上げを要求しない。コード差分があっても要件・観察条件が同じなら、理由付きレビューで版を維持できる。未分類の新規コード、参照切れ、対象差分にレビューがない場合は要確認として止める。固定ID・版番号・更新日の一致だけで十分性を証明しない。

文書保守がレビュー後に意味のある要件/シナリオ変更を加えた場合は正当に停止し、変更を作業ブランチへ戻して独立レビューを更新する。保守コミットを理由に無条件で通さない。リンク・メタデータだけの変更は、対象シナリオの手順・期待結果・前提・適用範囲を比較し、意味が同じと独立レビューで確認できれば全シナリオの版上げや実機再実行を要求しない。

### 4. 実機記録とビルドの対応

版別の既存`macos/docs/operations/release-<版>.md`から`release/verification-records.json`の該当結果を参照する。初期の実機記録は空集合とし、サンプルのpassedを配らない。記録だけを作って実機済みにしない。`macos/scripts/verification-gate.py capture-build`でビルド入力と成果物を結び付けるが、この操作を実機操作・観測の代わりにはしない。

capture-buildには`--platform macos|ios`、`--artifact`、`--settings`、`--output`、`--bundle-id`、`--version`、`--build-number`と、実際に実行するビルドコマンドを渡す。`--settings`は呼び出し側が実測した`xcodebuild -showBuildSettings -json`の配列であり、対象bundle ID、版/build、実機向け`macosx`/`iphoneos`、有効な署名設定を照合する。必要なローカル設定・依存入力は`--external-input`で明示する。既存成果物の後付け採番ではなく、新規成果物・新規来歴を記録する。

**限界**: settings JSONは呼び出し側の実測資料で、その採取コマンドと実ビルドコマンドが完全に同じ条件だったことまでは機械保証しない。呼び出し側と独立レビューが構成・platform・入力の対応を確認する。署名設定の照合は成果物への実署名検査の代用ではなく、既存の署名・公証検査は別途維持する。

| 記録の単位 | 必須内容 |
|---|---|
| ビルド（Mac/iOSそれぞれ） | クリーンなビルド開始時の完全sourceOID、ビルド入力manifestとハッシュ、Xcode/SDK・構成・有効設定、bundle ID・版・一意なbuild番号、成果物SHA-256 |
| 端末 | 実機であること、端末を区別できる識別子・機種、OS版/build。公開資料にはUDIDなど個人識別情報を載せず証拠への参照で管理 |
| 実施 | シナリオID・版/本文ハッシュ、実施者、実施時刻とタイムゾーン、結果・観測内容、スクリーンショット/動画/ログ等の永続的な証拠の参照とSHA-256 |
| 組み合わせ | 実際に接続したMacとiPhone両方のbuild識別。端末上のbundle ID/版/buildの読取とインストール元成果物を照合した記録 |

単なるHEADの後付け記入は禁止。ビルド開始前に入力を採取し、終了時も一致を確認する。未コミット入力があれば正式な再利用可能記録として受理しない。Gitの外にあるビルド設定・依存ロック/解決結果・署名等の有効入力も採取し、秘密そのものは保存しない。ハッシュと必要な非秘密メタデータで照合する。

端末上の版/buildと、記録した成果物の対応を確認できなければ未確認。画面の版番号だけからSHA-256一致を主張しない。同じbuild番号を別バイナリに使い回さない。成果物・証拠は`.verification/`の使い捨て領域を片付ける前に保存先を確保し、存在/ハッシュを照合する。秘密トークン・私的データをGitへ含めない。

実機記録が有効な間は、統合を操作するリポジトリの`.verification/release-evidence/<版>/<buildID>/`を継続保管先とし、OWNERに用途・保持理由を記す。消えるcandidateや削除予定worktreeの内部へ最終証拠を置かない。既存配布DMGの実体も保持し、既存releaseCommandでstapler等を検査する**同じ実DMGパスをrelease照合へ渡す**。記録内のMac配布成果物のSHA-256と一致しない場合は拒否する。実機で試したAと実際に配るBを別々に検査して合格にしない。将来の保存先移動時は参照とハッシュを再照合する。

capture-buildとreleaseの両方に証拠の明示基準`--evidence-root`を渡す。来歴・成果物・設定・端末/インストール証拠などの記録中の相対参照は、この基準から解決し、消えるcandidateや実行時cwd、記録JSONの置き場所を暗黙の基準にしない。基準は、継続保管する成果物と有効な外部設定を含む共通の親（例: 統合元リポジトリのルート）にする。capture時も同じ基準に沿って相対参照を記録し、別worktreeで照合しても同じ証拠を指すようにする。記録中の絶対パス・`..`・symlink等による基準外参照は許さない。実際の引数・保存形式の確定形は末尾のコード照合で記録する。

capture-buildのartifact/settings/output/external-inputとreleaseのdmgは、この基準内のパスを指定する。`--record`は照合する追跡JSONの選択で、既定は候補内の`release/verification-records.json`。記録JSON自体の選択と、その中にある証拠参照の基準を混同しない。releaseは最終統合候補の`GITFLOW_MERGE_CANDIDATE`と比較元`GITFLOW_MERGE_TO`を要求する。

実機確認後は、固定したverifyから**記録だけの作業ブランチ**を切り、記録JSON・その参照を含む文書だけを保存する。共通マージツールを通してverifyへ戻し、同じ自動検査を実行する。新しいdevの製品変更を混ぜずにverify→mainへ進める。sourceOIDは実際にビルドした旧OIDを維持し、記録追加後のOIDとは入力比較で対応付ける。以後コードを変更した場合は該当ビルドの実機結果を再利用しない。

### 5. 文書保守後の正当な再利用

sourceOIDは「実際にビルドしたソース」のまま保存し、最終候補OIDに書き換えない。コミットOIDの一致だけでも、祖先であることだけでも判定しない。

ビルド入力manifestはパス・Gitモード・内容ハッシュを安定順で含める。原則として追跡ファイルを保守的に含め、ビルドに読まれないと確認した`macos/docs/`・`ios/docs/`配下の文書拡張子は追加・削除も含めて除外できる。catalog・レビュー・実機記録の固定JSONも除外する。一方、ソース・資源・スクリプト・project.yml・Package.swift・ロック・entitlements・参照される生成入力は除外せず、新しいコードパスも既定で入力対象。未解決の外部/ローカル入力があれば再利用を認めない。

catalogをビルド入力から外しても、その内容を無視するわけではない。第1層で実ビルド入力を比較し、第2層でシナリオID・版・方式・必須性・手順・期待結果と、参照したAC行の内容ハッシュを比較する。コード範囲/テスト参照などの対応表の変更も独立レビューの差分対象に残す。単なるリンク先/空白・メタデータ変更と、意味のあるAC/操作/期待結果の変更を区別する。

main照合では、(1)候補の入力manifestと記録したビルドの入力が同じ、(2)有効ビルド設定/依存入力が同じ、(3)必須シナリオID・版・対象内容と適用範囲が同じ、(4)実機で確認した成果物/証拠が存在し実配布DMGを含めハッシュ一致、(5)差分の独立した内容レビュー済み、を要求する。これにより文書保守コミットや実機記録の追加だけなら再ビルド・再実機確認を要求しない。シナリオの比較は仕様ファイル全体のblobではなく該当AC・手順ブロックとする。リンク/メタデータのみで意味が同じと独立レビューで確認した変更は結果を維持できる。シナリオ文書はビルド入力から除外できても、意味のある変更を(3)の比較から除外できない。

記録のXcode/SDK等のtoolchainは**実際にビルドした当時の来歴**であり、現在の検査マシンの版と違うことだけで同一の実機成果物を失効させない。ビルド実行中の入力/環境変化の検出と、後日の既存成果物の再利用判定を分ける。証拠ファイルの設定・入力ハッシュは引き続き照合する。

ビルド入力が変わった場合は古いビルドを合格扱いせず、新ビルドで必要な実機項目を確認する。シナリオ変更は影響項目の結果を失効させる。経過日数だけの自動失効や、文書OID変更だけでの全項目再実行は設けない。

### 6. 状態と対象外

`passed`（条件を満たす実施証拠あり）、`failed`、`not_run`、`stale`（入力/シナリオ不一致）、`not_applicable`を区別する。必須項目のnot_run/stale/failed、記録欠落、検査不能はmainを止める。dev/verifyの実機not_runは実機成功と表示しない。

対象外は、対象要件・プラットフォーム/構成、理由、根拠差分、承認者・日時を対応表の変更レビューで確定する。結果JSONのフラグだけで必須性を外せない。端末がない、環境が足りない、テストが失敗する、iOS配布を今回は行わない、は既存の実機要件を自動的に対象外にする理由にならない。必要条件が同じ候補内で勝手に縮んだ場合は止め、親/ユーザーへ判断を戻す。

### 7. 否定テスト（実装担当の受入条件）

- 必須段階の欠落/非0、テスト0件、必須ID欠落/skip/known issue、未知の結果形式、E2E未設定、SDK/端末不足で失敗する。通常の対象外opt-in skipと必須fake E2Eの成功が共存する正例も検査する。
- 新パッケージの集合漏れ、親環境/位置引数による対象縮小・直列化/実Git別パス無効化、未知の通常known issueを拒否する。指定のADR 0209だけを未解決として別記できることと、candidate削除後も個別結果と生ログが残ることを検査する。
- 実CLI依存・人操作待ち・XCUITestの呼出しが自動計画に混入しないこと、正確なfake必須集合が選ばれることを検査する。
- 端末/OS/実施者/時刻/成果物/証拠/シナリオ版の欠落、別build・別Mac組合せ・古い版・ハッシュ不一致、シミュレータ記録の実機扱いを拒否する。
- 同じ一意build番号を異なる成果物に対応付ける記録、ビルド中の入力変更、ビルド後にHEADだけ記入した記録を拒否する。
- 既存release検査が確認するDMGと記録の配布成果物が異なるA/B取り違えを拒否する。xcpretty有無での誤成功/自動再実行がなく、generic Simulator buildと検出済みxcodegen絶対パスで動くことを確認する。
- docs保守/記録追加のみのOID差は、入力とシナリオ等が一致すれば受理する。コード/資源/設定/ロック/新規未分類パス/シナリオ本文変更は古い結果の再利用を拒否する。
- 非入力docs文書の追加/削除、意味を変えないリンク修正は独立レビュー付きで結果を維持できる一方、同じID/版のままACの操作・期待結果を変更した場合は拒否する。
- レビューなしの影響コード変更、必須項目削除、根拠のない対象外、既存IDを維持したまま意味を変えたシナリオを拒否する。内容を読んだかの真偽や未知の不足を自動証明するテストではない。

## 仮定 / 未知

- 指定13関数は静的に存在を確認した集合であり、この草稿での実行成功は未確認。テストランナーの結果形式を実装時に実測し、判別不能を合格にしない。
- 実機の利用可能性、確認する端末/OSの組合せ、実施者は未確定。親がverifyで確定し、不足はnot_runとして残す。証拠の継続保管先は上記契約に従い、実機実施前に実パスを確保する。
- 調査元のAGENTS.mdはGit除外のローカル文書で、開始時worktreeには存在しない。共通規則や元作業場所は変更せず、追跡する正本は本書と既存E2E設計に置く。

## 制約（技術・運用・期限）

- 作業場所は`/Users/ryosuke/Projects/Phlox-oss-worktrees/test-gates-20261025`。文書担当は設計と関連文書のみを所有し、他担当の変更を戻さない。コード・テスト・Git設定・commit/merge/pushは別担当。
- XCUITest・入力ソース設定変更・新規ツール/依存導入・`.env*`変更は禁止。シミュレータを実機の代替にしない。人の結果・ACKを生成しない。
- 検証出力はworktreeの`.verification/<作業名>/`、所有とPIDを記録し、ユーザーや他セッションのアプリ・サーバー・端末は終了しない。自分の不要物だけを所有確認して片付ける。
- 旧チェックリストのlocalStorageや過去のgreenは現候補の証拠として使わない。ローカル設定だけでサーバー側保護があるとは報告しない。

## スコープ外

新しいCIサービス・汎用ワークフロー基盤・テストフレームワーク、全E2Eの書き直し、実CLI品質の保証、XCUITest再導入、全変更での全シナリオ版上げ、全端末/OSの網羅、リリース実行そのもの。既知失敗をskipや期待値変更で通すことも本契約の実装には含めない。

## 既知リスク

固定ID、パス対応表、ハッシュは記録の取り違えや更新漏れを減らすが、シナリオが要件を十分に覆うことや人の申告の真実性は機械保証できない。実指の操作感・動的表示・端末間競合は実機で観察する。入力範囲を狭く定義すると偽の再利用、広すぎると不要な再確認になるため、除外を限定し、変更レビューで判断する。

ビルド入力の除外範囲は限定している。rootの`SECURITY.md`・`THIRD_PARTY_NOTICES.md`等はまだ入力に含むため、実バイナリに影響しない文書修正でも古い来歴の再利用を拒否し、再確認を要求し得る保守的な限界がある。「文書変更なら必ず再利用できる」とは主張しない。

## 導入時の観測と未解決事項（監査基準OIDと別）

以下は2026-10-25の親/実行担当からの報告で、文書担当が検査を実行した結果ではない。原ログの保存先と最終の再検査結果は実行担当の記録へ対応付ける。

- `90a0c801`上のControlServer初回検査で期限超過があり、その後の診断5回は成功したが原因は未特定。再現しなくなったことを根本解決とは扱わず、未解決として残す。後続devの状態と取り違えない。
- 最初のquality実走はmacOS19パッケージのテストコマンドがexit 0で終わった後、イベント解析で失敗した。原因はJSON文字列内のUnicode改行の`splitlines`誤認と、PTY子による同じ出力ファイルの上書き。これらは解析と子プロセスの出力引数を直す対象であり、テストの削除・skip・期待値変更で回避しない。
- 最初の独立レビューでは、パッケージごとの結果欠落と不要な文書差分による停止などが指摘された。最新の独立判定は`verification-reviews.json`、全体検査の成否は各実行の`result.json`・終了コード・原ログで確認する。過去の指摘や単体検査の成功だけを最終候補の成功と読み替えない。

## 文書保守と実装状況の区別

関連文書は本契約へ案内する。`e2e-test-design.md`の広いE2Eフィルタ・旧Layer Bの合格風表記・XCUITest実行コマンド・既存アプリ終了・flaky隔離の指示を修正し、旧設計案を現行の指示から区別した。`vision-testing-desktop-ui.md`のXCUITest案内・通常Release終了・禁止削除コマンドも修正した。リリース運用/索引から本書へ案内し、7月版チェックリストを過去資料と明示した。過去リリースの実測記録は書き換えていない。

### 入口・保存先

| 入口/ファイル | 役割 |
|---|---|
| `macos/scripts/verification-gate.py quality` | 文書保守後の候補で必須の自動検査を実行するプロジェクト入口。`gitflow.verifyCommand`の接続先 |
| `macos/scripts/verification-gate.py capture-build --evidence-root <基準> ... -- <ビルドコマンド>` | 実機に入れるビルドの実入力・ソース・成果物を対応付ける。settingsは呼び出し側の実測資料。実機合格は作らない |
| `macos/scripts/verification-gate.py release --dmg <既存staplerと同じDMG> --evidence-root <基準> [--record <JSON>]` | main反映前の独立レビュー・実機記録・再利用条件の照合。既存署名/版検査は親の接続先で先行実行する |
| `macos/scripts/verification-gate.py review-input --base <比較元> [--target <対象、既定HEAD>]` | 正規化差分とハッシュを標準出力に得る。レビュー判定を作らず、作業ツリーも書き換えない |
| `release/verification-scenarios.json` | 要件/対象コード/テスト/実機シナリオ対応。`schemaVersion`付き |
| `release/verification-reviews.json` | 差分に結び付いた独立レビュー。担当種別は`ai`/`human`を明記する |
| `release/verification-records.json` | 実ビルドと実機観測の記録。初期は空集合で、passedを作らない |

上記は検査の契約と入口の説明であり、実行済みの証明ではない。開始OIDの監査表は履歴として残し、新実装の動作確認として上書きしない。Git管理外の設定は各環境で接続を確認し、実機の合否は対象ビルドに結び付いた実施記録で確認する。
