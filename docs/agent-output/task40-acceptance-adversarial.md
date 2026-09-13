---
status: completed
verdict: changes_required
validation: static_only
output_path: docs/agent-output/task40-acceptance-adversarial.md
file_saved_by_reviewer: false
---

静的レビューの判定は差し戻しです。契約を満たす変更を拒否する残余比較と、誤った描画接続を見逃す検査が併存しています。読み取り専用制約のため、このセッションから報告ファイルへの保存は行っていません。

対象は契約末尾の「PM 採択時の調整」を含みます。以下のNG・検出漏れの判定はコード読解によるもので、変異検査の実走結果ではありません。

参照略記：

- 契約：[tasks/task-40.md](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/task-40.md)
- rb：[task40-wiring.rb](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/.claude/scripts/task40-wiring.rb)
- 単体：[AcceptanceTranscriptTypographyTests.swift](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptTypographyTests.swift)
- 統合：[AcceptanceTranscriptTypographyIntegrationTests.swift](/Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/tasks/frozen/staged/AcceptanceTranscriptTypographyIntegrationTests.swift)
- `SF/`：`macos/Packages/SessionFeature/Sources/SessionFeature/`
- `DS/`：`macos/Packages/DesignSystem/Sources/DesignSystem/`

**1. MUST — 残余比較が、契約上必須の変更を拒否する（rb項目12）**

根拠：rb:649–720、1148–1150。描画呼び出しを削除せず `__DRAW__` に置換するため、呼び出しの追加・削除で残余が変わります。また、`typographyRole` は追加後だけ `__DRAW_VAR__` になります。

具体的には、契約必須の次の変更が残余不一致になります。

- `ChatTypography.bodyFontSize` の `15 * scale` を正本呼び出しへ委譲する。
- `ChatTranscriptBlock` に `typographyRole` を追加する。
- `DisclosureCard` の外側paddingを除去する。
- H4〜6に不足する字体指定を追加する。

正例の `inspect_product(good, good)` は変更後同士の比較であり、凍結製品から正しい実装への移行を検査していません。

テスト/rb 側の修正案：凍結製品→契約準拠製品の正例を追加し、指定シンボル内の許可した追加・削除・委譲だけを正規化する。

**2. HIGH — View接続検査が実際の呼び出し経路を追っていない（rb項目7・10・14）**

根拠：rb:214–235、431–455。`body` ではなくstruct全体から、候補文字列が一つでも見つかれば接続済みになります。同じstruct内の未使用ヘルパーでも条件を満たせます。

さらに、実製品のMarkdownテーマは `SF/RichMarkdownView.swift:49` のファイルスコープ関数です。正しくそこへ委譲していても、struct内に検索語がないため拒否され得ます。逆にH4〜6は既存クロージャ名があるだけで接続検査を通り、字体未設定を検出できません。

テスト/rb 側の修正案：各Viewの `body` から呼ばれる既存ヘルパーとテーマクロージャを明示し、対象の文字要素ごとに必須修飾を検査する。

**3. HIGH — Styleが正しくても、生成するFont・Colorの誤りを検出できない**

根拠：単体:54–151、統合:200–242、rb:347–369。Swift検査はStyleの値とpointSizeを検査しますが、`font(for:scale:)` の太さ・等幅指定や `color(for:)` の対応を検査していません。

実際にrbの正例は、fontがweight/designを無視し、colorが常にprimaryを返します（rb:803–804）。Style表を正しく実装したままこの生成処理を残しても、当該Swift検査とrbには検出条件がありません。

テスト/rb 側の修正案：独立した期待Fontと各役割のDSColor対応を検査し、weight・design無視と色固定をそれぞれ単一変異にする。

**4. HIGH — gapの統合検査が製品の適用処理を検査していない（rb項目11）**

根拠：統合:39–46、167、186–197。期待系列と比較するgapは、テスト内の `gaps(for:)` が独自に計算しています。製品Viewが誤った直前ブロックを渡しても、この検査には影響しません。

rb:598–611も呼び出し名・定数名の存在確認です。例えば実Viewのgap引数を常に `after: nil` にしても、名前は残ります。padding引数は残余比較で隠されるため、そこでも検出されません。gapへの倍率の再適用も同様です。

テスト/rb 側の修正案：実Viewが使用する境界計算を検査対象にし、直前ブロック誤参照・先頭余白持ち越し・gap二重適用で失敗させる。

**5. HIGH — 直値・意味色・コード連結の保護が不足している（rb項目8・9・12）**

根拠：rb:461–522、636–705。新規直値検査は `.system(size: 数値)` と `FontSize(数値)` だけです。対象padding/spacingの任意数値、一般の数値×倍率、`DSSpacing.xxs` の説明間隔は検査されません。

残余比較はファイル全域のforeground・padding・spacingを隠すため、次の違反も区別できません。

- `SF/ChatMessageCells+Structured.swift:378` の差分行間0を8へ変更。
- 同:361の追加行の意味色を通常文字色へ変更。
- 料金のopacity 0.7を維持したまま字体だけ更新。

契約:172–174、281–285が要求する「対象箇所単位の例外」になっていません。

テスト/rb 側の修正案：変更可能な描画属性を要素単位で限定し、意味色・コード連結0・操作領域のpaddingは凍結値と比較する。

**6. HIGH — selftestが「違反1件を、その理由で検出する」を満たさない**

根拠：rb:1283–1301ではテスト2ファイルを同時に欠落・改変しています。rb:1317–1318のSHA不一致検査は「無効」でも成功するため、SHA一致比較そのものを削除しても保護力を証明できません。

未使用ヘルパーの負例もstruct外に追加しており、項目2のstruct内偽装を試していません（rb:1212–1219）。通常の負例の多くはbaselineを渡さず、残余比較を含む本番構成を通していません。

テスト/rb 側の修正案：準拠fixtureの一箇所だけを変え、解決可能な異なるSHAと具体的な違反識別子を用いて、本番と同じ構成で判定する。

**7. HIGH — 変更禁止対象の一覧が契約を覆っていない（rb項目13）**

根拠：rb:202–212。契約:233が明示する `DashboardViewModel.adjustTerminalFontSize(by:)` のファイルが対象外です。パッケージ依存・クライアント・保存形式も、契約:239では変更禁止ですが、この一覧にはありません。

例えば `DashboardViewModel.swift:689` の `ChatFontSettings.save(newChatScale)` を削除しても、rbの禁止対象比較では検出されません。

テスト/rb 側の修正案：契約の変更禁止対象を実パスへ展開し、少なくとも文字倍率操作経路とPackage.swiftを固定SHA比較へ追加する。

**8. HIGH — 独立に成立する二つの契約が同居している**

根拠：契約:93–174と177–206。字体・セル内部余白の統一と、可視ブロックの分類・境界gap適用は、片方だけを採用しても成果が成立します。後者には可視窓・ID・スクロールとの接続という別の失敗条件があります。

15製品ファイルという数だけを問題とはしませんが、この分解では値表の修正と可視窓の修正が同じ凍結条件を揺らします。

契約側の修正案：「文字役割とセル内部への適用」「可視ブロック境界のgap適用」に分け、共有正本の変更順を依存関係で固定する。

**9. HIGH — 凍結前の実測・assertion RED・検証配線が未充足**

指定手順 `phase1_5-acceptance-adversarial.md` は「**アサーションで落ちる red**」と実物描画による期待値の根拠を要求しています。一方、報告 `docs/agent-output/tests-task-40.md:41–87` の証拠は未定義シンボルによるコンパイルエラーです。

契約:373の凍結前描画についても、指定ハーネスと `visual-task-40.md` は確認時点で存在しません。末尾:401は描画を凍結テストから移す調整であり、凍結前実走を免除していません。また `.claude/verify.sh` にtask40のRuby検査は接続されていません。

テスト/rb 側の修正案：コンパイル可能な旧挙動または単一変異でassertion REDを確認し、描画実測・verify接続・更新した報告を揃えて再凍結する。

**10. HIGH — PM目視の設定隔離方法が実際の参照先に対応していない**

根拠：契約:353–355、375–377。`DS/AppTheme.swift:433–434` のテーマ色は `UserDefaults.standard` を読みます。Viewへ専用suiteを注入しても、DSColorの保存先は切り替わりません。

文字倍率操作も `DashboardViewModel.swift:677–689` から、既定保存先が `.standard` の `ChatFontSettings.currentScale/save` を呼びます。suite指定だけでは「通常設定へ混入させず、色と倍率を連続変更する」という手順を成立させられません。

契約側の修正案：App・fixture双方でstandardを含む隔離方法と起動コマンドを固定し、実際に読むテーマ・倍率と通常設定の前後差を確認する。

**11. HIGH — 復元失敗プレースホルダへの無課金到達条件が不足している**

根拠：`SessionSpawnService.swift:770–786` のプレースホルダ生成自体は通信しません。しかし `SessionRestoreCoordinator.swift:185–234` は、その前に起動準備・実クライアント生成・`vm.restore` へ進む経路を持ちます。

契約:353–354は使用するsessions.jsonの内容と失敗条件を固定していません。「復元失敗を表示する」だけでは、実バックエンドを起動せずにcatchへ入る保証になりません。

契約側の修正案：実クライアント生成前に必ず失敗する隔離descriptorを固定し、入力JSON・到達分岐・プロセス非起動の確認方法を記載する。

**12. HIGH — 目視fixtureの実合成と入力空間に不足がある**

入力軸として、文字役割、倍率、テーマ、幅、可視窓境界、空／非空出力、展開状態、質問・タスク状態、Reduce Motion、表・コード・日本語折り返しを照合しました。

契約:372–378のfixtureは `ChatTranscriptView` へ固定履歴を渡しますが、製品の `ChatSessionView.swift:120–123` が渡す `contentMaxWidth` とcomposer回避余白を再現する指定がありません。既定引数では内容幅が変わるため、同じ「幅360」の画像でも折り返し条件が一致しません。

またfixture一覧:363–368に表がなく、質問の回答済み・期限切れ、タスクの各状態、空出力グループも指定されていません。既存の値・描画テストは存在しますが、今回変更する字体・間隔の状態別確認にはなっていません。

契約側の修正案：製品と同じ幅・末尾余白を渡すホスト仕様と、表・状態別セル・非表示グループを含む目視ケースを固定する。

照合結果として、Role表14役割、倍率4条件、間隔10定数、gap20条件、混在系列の独立リテラルは契約と一致しています。ChatFontScale系の既存期待値、およびgrouping系の「単独コマンドも集約・先頭ID維持」との直接の衝突はありません。ADR 0030・0045・0127の描画・表・集約方針も契約文面では維持されています。

`allowed_paths` は製品15ファイル＋報告1ファイルです。確認した呼び出し経路では、製品実装に必須の範囲外ファイルは特定していません。コピー操作の字体は既存委譲で届き、PM所有ハーネス・検査・契約が範囲外であること自体も妥当です。

検証範囲と実行制約：

- 固定SHAは `42859188ba5d8880df8ebd4d2ec8b8375847d2a2` に解決でき、確認時のHEADの祖先でした。
- 凍結SHAの正位置にあるSwiftテスト2本は退避ファイルと、rbは現ファイルとバイト単位で一致しました。基準時点に `TranscriptTypography.swift` はありません。退避中のため正位置が存在しないことは、指摘に数えていません。
- HEAD文字列を拒否し、固定SHAの製品・凍結テスト内容を比較する実装はあります。固定SHA＝HEADだけでは拒否しない仕様にも一致しています。ただし項目1・5の残余処理に欠陥があります。
- selftestは必須ラッパー経由で試行しましたが、exit 1で検査本体へ到達していません。原文：

```text
mktemp: mkstemp failed on /tmp/tmp.WBwdJTwP3K: Operation not permitted
/Users/ryosuke/.agents/scripts/compact-test: line 26: : No such file or directory
cat: : No such file or directory
```

Swiftテスト・ビルド・変異検査・GUIは未実走です。既存報告のselftest成功とコンパイルREDは過去の記録として読み、今回の検証成功には数えていません。レビュー中に他作業によるHEAD・未コミット状態の変化を観測しましたが、本レビューでは製品・テスト・検査ファイルを変更していません。

=== REPORT COMPLETE ===