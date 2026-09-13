指摘 1・2・3・4・5・8 を契約の裁定どおり直し、製品コード・契約・台帳は触っていません。コミットもしていません。

**結果:** `ruby .claude/scripts/task41-wiring.rb --selftest` は未設定と `TASK41_SCOPE_CHECK=1` の両方で `task41-wiring --selftest: OK`（exit 0）。

主な修正は次のとおりです。

- **1:** 導出契約の回帰（公開面・純粋性）は常時。AgentDomain 他ファイル不変は `TASK41_SCOPE_CHECK=1` のときだけ。両モードの正例・負例を selftest に固定
- **2:** Swift で `title` / `fullTitle` を明示的な `String` へ代入。rb は `String?` を拒否し、Optional 変異の負例を追加
- **3:** 補間内コードと属性付き import を走査。`print` / `ProcessInfo` / `Date` / `.now` / `random` / `UserDefaults` を独立負例に
- **4:** `"    説明\nログインを修正"` → `"ログインを修正"`、3 空白なら `"説明"`
- **5:** 負例を単一違反に分離し、期待エラー配列を厳密比較。基準検査の本番切断も負例に
- **8:** URL・10000 Character 全文保持・単独 CR・全角空白・1〜3 空白フェンス・長い終了フェンス・終了後の非空白・`Return home` / `important fix`・半角カナ／濁点を固定期待値で追加

報告は `docs/agent-output/tests-task-41-r2.md` です。契約の曖昧点（終了フェンスの行頭空白、幅変換 API、濁点の正規化形、長文サイズ 10000 は検査側固定）もそこに列挙しています。契約変更は PM 側です。
�きも対象。`print` / `ProcessInfo` / `Date` / `.now` / `random` / `UserDefaults` を各 1 件の負例 | `code_for_purity` / `imported_modules` / `check_imports_and_purity` | rb `:142` / `:416` / `:424` |
| 4 | `"    説明\nログインを修正"` → `"ログインを修正"`。3 空白なら `"説明"`。契約表の `    let value = 1` ケースは残す | `fourSpaceIndentedPlainLineIsExcluded` / `threeSpaceIndentedLineIsEligible` | staged Swift `:169` / `:174` |
| 5 | 負例は正例から条件 1 件だけ変更し、エラー配列を `==` で厳密比較。基準検査の本番接続（`check_frozen_baseline`）を外す変異と、SCOPE ゲートを外す変異も負例 | `selftest_errors_eq` / `baseline_check_connected?` / `scope_check_gated?` | rb `:561` / `:544` / `:548` |
| 8 | 未被覆領域に独立リテラルの固定期待値を追加（下表） | 下記テスト | staged Swift `:290`–`:360` |

指摘 6（アサーション RED）と 7（課金なし目視）は今回の委譲対象外。

## 指摘 8 の期待値（契約規則からの独立リテラル）

製品の戻り値からは作っていない。幅変換は契約 L56 の Foundation 変換を、既存成功基準 L79（`ＡＰＩ　１２３を修正` → `API 123を修正`）と同じ **全角→半角** 方向で、`SessionTitleDeriver` を使わずに求めた。

| 領域 | 入力 | 期待 | 契約の根拠 |
|---|---|---|---|
| URL | `https://example.com` | 両方その文字列 | L57–62 の除外接頭辞に無い。L53 の `/` は行頭のみ |
| URL 先頭 | `https://example.com\nログインを修正` | 両方 `https://example.com` | 同上 + L57 最初の適格行 |
| 長文 | ASCII `a` × **10000 Character** | `fullTitle` は入力全文（count 10000）、`title` は `a`×31 + `…`（count 32） | L63。サイズは契約に無いため検査側が 10000 で固定 |
| 単独 CR | `"説明\rログインを修正"` | 両方 `説明` | L53 CRLF・CR を LF |
| 先頭 CR | `"\rログインを修正"` | 両方 `ログインを修正` | L53 + L58 空行除外 |
| 改行のみ CR | `"\r"` | `nil` | L53 + L80 |
| 全角空白のみ | `"\u{3000}"` / 2 個 | `nil` | L56 前後空白除去、L58 空行除外 |
| 連続内部空白 | `"API\u{3000}\u{3000}\u{3000}接続を修正"` | 両方 `API 接続を修正` | L56 幅変換のあと L58 連続空白を半角 1 個 |
| 混在内部空白 | `"API \t\u{3000}接続を修正"` | 両方 `API 接続を修正` | 同上 |
| 1〜3 空白フェンス | `" "`/`"  "`/`"   "` + `\`\`\`\nprint(1)\n\`\`\`\nログインを修正` | 両方 `ログインを修正` | L54 行頭半角 0〜3 + バッククォート 3 個以上 |
| 長い終了フェンス | `"\`\`\`\nprint(1)\n\`\`\`\`\nログインを修正"` | 両方 `ログインを修正` | L54 終了は開始時以上の個数 |
| 終了後の非空白 | `"\`\`\`\nprint(1)\n\`\`\`x\nログインを修正"` | `nil` | L54 「その後が空白だけの行」。未閉鎖なら末尾まで除外 |
| 類似英語 | `Return home` / `important fix` | 両方その文字列 | L58 接頭辞は大文字・小文字を区別。`return ` / `import ` に一致しない |
| 全角カナ | `カタカナ修正` | 両方 `ｶﾀｶﾅ修正` | L56 + L79 と同じ全角→半角 |
| 全角濁点 | `ガ行を修正` | 両方 `ｶﾞ行を修正`（`ｶ` U+FF76 + `ﾞ` U+FF9E が 1 Character） | L56、切らない単位は L63 の Swift Character |
| 半角カナ / 濁点 | `ｶﾀｶﾅ修正` / `ｶﾞ行を修正` | 両方入力のまま | L56 すでに半角なら変化なし |

## 契約の曖昧点（変更は PM）

検査側で期待値を置いたが、契約文面だけでは一意に決まらない箇所。

1. **終了フェンスの行頭空白**（L54）。開始は「行頭の半角空白 0〜3 個」とある。終了は「同じ文字が開始時以上の個数続き、その後が空白だけ」とあり、行頭 0〜3 空白の可否が書いていない。本検査の終了行は行頭 0 空白。
2. **幅変換 API**（L56）。「Foundationの幅変換」とだけある。成功基準 L79 から全角→半角方向は読めるが、`.fullwidthToHalfwidth` か互換の別 API かは未指定。半角カナ期待値はその方向で置いた。
3. **濁点の正規化形**（L56）。全角 `ガ` が `ｶ`+半角濁点になることは Foundation の全角→半角に依存する。契約は「揃える」のみ。Swift Character では変換後も 1 文字（L63）。
4. **極端な長さの上限**（L63）。32 / 33 Character しか無い。全文保持の fixture サイズ 10000 は検査側の固定値。
5. **「行の前後の空白」に U+3000 が含まれるか**（L56）。含まれても、幅変換→圧縮→空行除外（L58）でも `nil` になり、本検査の期待はどちらでも同じ。

## selftest 原文

コマンド: `ruby .claude/scripts/task41-wiring.rb --selftest`

exit 0。

```
task41-wiring --selftest: OK
```

コマンド: `TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb --selftest`

exit 0。

```
task41-wiring --selftest: OK
```

`--selftest` は実ファイルを変更しない。両モードの正例・負例はメモリ fixture。`TASK41_SCOPE_CHECK` は本番ゲートの読み取り検査にだけ使い、selftest 本体のモード切替は `collect_checks(..., scope_check:)` の引数。

両モードで固定した代表例:

- SCOPE オフ + 後続ファイル `SessionTitleState.swift` 追加 → 空（通す）
- SCOPE オフ + `title: String?` → `["public let title: String が無い"]`
- SCOPE オン + Deriver のみ追加 → 空
- SCOPE オン + 後続ファイル追加 → 新規製品ファイル 1 件
- 基準検査呼び出しを `removed_fn` に置換 → 接続なしと判定

## PM 向け

凍結時は退避 Swift を契約 `acceptance_tests` の正位置へ戻し、`git add -f .claude/scripts/task41-wiring.rb`。契約の「task-41 の verify 分岐で `TASK41_SCOPE_CHECK=1` を付与」は未反映（`.claude/scripts/ui-ux-verify-task.sh` は今回触っていない）。task-44/45 の回帰再検査では付与しない。

Swift テストは退避中のため、本作業では `AgentDomain` の `swift test` は走らせていない。

=== REPORT COMPLETE ===
