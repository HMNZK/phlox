---
id: task-13
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/AcceptanceSidebarTextContrastTests.swift
baseline_commit: f084245
contract_tests: []
allowed_paths:
  - macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift
  - macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift
  - docs/agent-output/task-13.md
---

## 目的

UI-01。サイドバーの見出し・時刻・名前を、状態やテーマが変わっても読めるようにする。2026-09-12 に受け入れテストを作成し凍結した（下記「受け入れ方式（2026-09-12 確定）」）。

## 入出力契約

- 事前条件: 既存ThemeStore.allの10テーマ、RGB、DSColor、サイドバーの共通行を使う。現在の名称・順序・時刻内容・選択挙動を維持する。
- 事後条件: Projectsと「その他」の見出し、経過時間、空文字名/空白名の短ID、通常名について、通常/hover/選択/注意の実際に使う背景とのコントラスト比を4.5:1以上にする。見出しは行外の基底背景だけ、行内情報は4面を対象にする。修正前の文字トークン割当はProjects/時刻/空文字名がtertiary、空白名/通常名がprimary。「その他」は未指定なので、既存の文字役割へ明示的に接続する。
- 情報の階層は失わない。主文字は補助文字より弱くせず、見出しや時刻を本文と同じ大きさへ一括変更して色不足を隠さない。無効状態の文字・意味のない装飾は本タスクの対象外。
- 背景の状態解決は選択→hover→注意→通常の優先順を維持する。重複8条件で2枚を重ねない。現在の基底背景、主文字5%/10%のhover/選択、attention22%の注意面は変更しない。ただし主文字自体の可読性補正に伴う合成色の変化は検査対象。
- 不変条件: terminalBackground/terminalForeground/ANSI16色、アクセント・状態色、テーマID/登録数/選択・保存ルール、フォント設定、会話・プロジェクト選択・木の展開・時刻計算を維持する。通常UserDefaultsを書き換えて検査しない。新しい公開API、依存、テスト専用の製品API、色のコピー定義は追加しない。

## 成功基準

1. PMが既存Swift Testingに1ファイルを追加する。ThemeStore.allの実RGBを使用し、primary/secondary/tertiaryと通常/hover/選択/注意背景の120組を丸め前の比率で検査する。同じ各背景でcontrast(primary) >= contrast(secondary) >= contrast(tertiary)も要求し、全役割4.5以上でも主副が逆転した配色を落とす。背景は製品契約のsource-overをDoubleで計算し、実装の色補正処理はコピーしない。白黒21:1・同色1:1・透明0/1の自己検査を含める。全10テーマが存在し追加テーマも検査へ入ること、ANSI等の不変条件は既存テーマ定義との限定比較で確認する。数値検査だけを実描画の合格と呼ばない。
2. 凍結前に実サイドバーを隔離して描画し、実際の背景と数値モデルの一致を確認する。テーマ指定は通常設定へ保存しない起動引数`-phlox.theme <id>`を候補とする。Foundation単独プローブでは実効値と永続ドメイン不変を確認済みだが、実アプリでの実効性・実Listの色空間/測定方法/許容差は未確定。この具体的な実画面手順を確定し、想定テーマ・背景の一致が成立するまでは、凍結・実装ディスパッチ・完了を禁止する。不成立を未実測と記録するだけで先へ進まず、PMが原因を調べて契約と手順を修理する。署名/権限/通常設定の変更で迂回しない。
3. PMは製品の共通行へのPTY/Chat・project配下/未所属の接続、全対象ラベルのトークン割当と追加opacityの有無を実コードで確認する。ソースの単純contains検査を製品動作の検証として追加しない。実GUIでは架空データを使い、各テーマの見出し/名前/時刻を通常・hover・選択・注意で確認する。短ID・空白名・通常名、選択と注意/hoverの重複も実表示で照合する。
4. 正本8パッケージと更新12条件、Debug build-for-testing/リンク、既存GUI3件をcompact-test経由で実走する。実画面の可読性は上の専用確認と区別する。Release・通常Debugの保護範囲と対象外差分を記録し、起動した所有Debugだけを終了する。
5. 検証値・失敗・警告・未検証範囲を報告する。UI-03で文字役割、UI-08で背景を変更した後は、同じ読ませる情報と使用面の検査を再実走する。本タスクの完了だけで他21改善やアプリ全体のWCAG適合を主張しない。

## 変更してよいファイル / スコープ

allowed_pathsの製品3ファイルで対象文字色と見出しへの適用のみ。共有のAppTheme/RGB導出で不足が解決するなら既存処理を再利用する。Tokensの文字以外の役割、背景の優先順位、UI-03/08の別設計は変更しない。PM所有のテスト・契約・台帳・設定・コミット・GUIハーネスは実装役が編集しない。受け入れテストのアサーションは変更禁止。ハーネス欠陥はPMへ報告し承認後に限定修理する。

## レビュー観点（Rubric）

- 10テーマの実値と実ラベルが対応し、未指定の「その他」や空白名を取りこぼさない。主文字が十分という仮定でSolarized Lightを落とさない。
- 比率のためにANSI/端末文字や意味のあるアクセントまで一括補正しない。補助文字の階層を保ち、既存文字サイズ設定へ追随する。
- 半透明合成、角丸・文字のアンチエイリアス、Listのシステム描画を区別する。画素1点だけの測色や不透明色標本を実サイドバーの合格としない。
- 純粋な色検査と実適用の検査を補完させる。privateビューを公開してテストだけの経路を作らず、製品の実呼出元から到達性を確認する。
- UI-03/08は同じファイルを触るため逐次実装する。現在の各パッケージ検査を別タスクのREDで失敗させないよう、task24の完了ゲート後に受け入れテストを追加する。

## 受け入れ方式（2026-09-12 確定）

- 客観ゲート（driver の `VERIFY_TASK_BIN`）: ①`.claude/scripts/task13-wiring.rb`（「その他」見出しが `Text("その他")` + `DSColor.textSecondary|textTertiary` へ明示接続され、`Section("その他")` のシステム既定色が残っていない。Projects 見出しが `DSColor.text*`）②`AcceptanceSidebarTextContrastTests`（DesignSystem、7 テスト）③DashboardFeature の `swift build` ④`git diff --check`。
- 成功基準 2 の「実描画と数値モデルの一致」の根拠: 2026-09-08 の Dracula 実サイドバー測色（`docs/agent-output/ui01-pixel-method-investigation.md`）で、基底・選択面はモデルの 8bit 丸め値と完全一致、注意面は G が +1 の**未解明残差**（出典はこれを「許容誤差内で合格」とは扱わず、既知色対照で誤差幅を先に固定せよと書いている）。実効テーマは起動引数の申告と画像の間接証拠のみ。PM はこれを「sRGB 符号値上の source-over が実描画経路を表す補助証拠」として凍結の根拠にし、残差は実装目標（下記、最悪面 4.56 以上）の余裕で吸収する。hover 面・明色テーマ・残り 9 テーマ・List 内の見出し行（projectHeader / その他）の面は**未実測**。XCUITest 経由の検査は Automation Mode 認証が無く実行不能。旧記述「凍結禁止」はこの限定付きで解除する。
- PM 目視・測色ゲート（`user_visible: true`。`ready_for_integration` で止め、通るまで `complete` を打たない）: 隔離 Debug（`PHLOX_DATA_DIR`/専用 suite/`-phlox.theme <id>`）に架空プロジェクト 1 件と名前が通常/空文字/空白の PTY 3 件を seed し、①Catppuccin Latte ②Solarized Light の 2 テーマで注意面・選択面・見出し行（Projects と「その他」）の矩形を `screencapture -l <windowid>` で撮り、`NSBitmapImageRep.converting(to: .sRGB)` 経路で最頻値を測色してモデルと比較する（Dracula で確立済みの手順。System Events/AX/他 PID 操作・実エージェント seed は禁止＝lessons L-3）。hover は未実測のまま記録する。
- 旧「テスト保護解除の承認待ち」は XCUITest helper 編集の話であり、本方式（単体テスト＋既存測色）では不要。

## 実装指針（実装役向け・契約の一部）

- 根本原因は `AppTheme.fromPalette` の固定混合率（42%/62%）と Phlox 既定の固定 RGB。修正は **AppTheme の導出 1 箇所**で行う: 補助文字は「主文字を背景へ混ぜる比率」を、サイドバー 4 面（基底／主文字 5%／主文字 10%／attention 22%）の最悪面に対して **4.56:1 以上**（WCAG 4.5 に実測残差 G+1 と 8bit 丸め分の余裕を足した実装目標。受け入れテストの判定値は 4.5）を満たす最大値へクランプする。**クランプは tertiary にだけ適用し、secondary は tertiary の比率を理想比（42/62）で按分する**（`secondary = min(0.42, tertiary × 42/62)`）。2026-09-12 独立レビュー H-1: 実値では暗色テーマも上限 0.24〜0.39 で 42% に届かず、両役を同じ上限へクランプすると全 10 テーマで secondary == tertiary に縮退する（`DSColor.textSecondary` 41 箇所・`textTertiary` 27 箇所がアプリ全体で同色になる）。Rubric「補助文字の階層を保つ」を優先する裁定。主文字が最悪面で 4.56 未満（Solarized Light）のときだけ、主文字を黒または白（**最悪面比が大きくなる方**。輝度しきい値で決めない＝レビュー L-1）へ寄せて 4.56 を満たす最小の補正を行う。
- 4 面の不透明度は AppTheme 側に定数として 1 箇所で定義し、`Tokens.swift` の `fillSubtle`/`fillSelected`/`idleHighlight` はその定数を参照する（数値のコピーを 2 箇所に置かない）。値は変えない。
- Phlox 既定テーマは **`fromPalette` に通さない**（background/surface/attention/status/agentColors の固定値が変わるため。受け入れテストが指紋で固定）。固定 RGB の textSecondary/textTertiary だけを、fromPalette と共有する導出関数の呼び出しに置き換える。主文字 0xE6 は既に十分なので変わらない。
- `statusStarting`/`statusIdle`/`agentColors.cursor`・端末色・ANSI・accent・`preferredColorScheme` は触らない（受け入れテストが不変条件を固定）。
- `DashboardSidebarView.swift`: `Section("その他")` を `Section { … } header: { Text("その他").font(DSFont.caption).foregroundStyle(DSColor.textTertiary) }` の形で既存文字役割へ接続する。Projects 見出し（`DSColor.textTertiary`）と同じ役割。行内ラベルの割当（空文字名=tertiary、空白名/通常名=primary、時刻=tertiary）は変更しない。
- 色差を出す余裕が無いテーマ（Catppuccin Latte は混合上限 3%、Solarized Light は 0%）では secondary/tertiary が primary と同色〜ほぼ同色になる。これは契約上正当（受け入れテストは主文字の最悪面比 6.0 以上の 8 テーマだけに、tertiary≠primary かつ secondary≠tertiary の色差を要求）。そこでの階層は既存のサイズ差（見出し・時刻 = caption、名前 = body）と配置で残す。太さの追加やサイズの一括変更はしない。
- テスト・契約・台帳・スクリプトは PM 所有。編集禁止。

## 適用範囲の注記（2026-09-13、task-48/50 敵対レビューを受けて）

`task13-wiring.rb` の逐語一致・全体比較は **task-13 の着手時検査**であり、task-13 done 以降の後続タスク（task-48/50 等）には適用しない。後続タスクは自分の rb で必要な不変を限定検査する。
