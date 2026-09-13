幅変換の期待値だけを契約に合わせて直しました。製品コード・rb・契約・台帳は触っていません。コミットもしていません。

**置き換え（2件）**
- 「全角カタカナを半角カナへ幅変換する」→ 「半角カナを全角カナへ幅変換する」  
  `ｶﾀｶﾅ修正` → `カタカナ修正`、`ｶﾞ行を修正` → `ガ行を修正`
- 「濁点付き全角カナを半角カナ+半角濁点へ幅変換する」→ 「全角英数を半角へ幅変換する」  
  `ＡＢＣ１２３` → `ABC123`

**追加（1件）**
- 「全角カナは変更しない」  
  `カタカナ修正` → `カタカナ修正`

**検証**  
`task41-wiring.rb --selftest` は未設定と `TASK41_SCOPE_CHECK=1` の両方で `OK`（exit 0）。退避先テストはコンパイル確認していません。

**残している矛盾**  
指示どおり他ケースは未変更のため、`halfwidthKatakanaAndDakutenAreKept` は同じ入力に対して半角のままを期待したままです。新ケースの半角→全角と両立しません。再凍結前に残すか直すかを決める必要があります。

報告: `docs/agent-output/tests-task-41-r3.md`
`ＡＰＩ　１２３を修正` → `API 123を修正`）と `halfwidthKatakanaAndDakutenAreKept`（半角カナを半角のまま期待）はそのまま。

## 差分原文

コマンド: `git diff -- tasks/frozen/staged/AcceptanceSessionTitleDeriverTests.swift`

```
diff --git a/tasks/frozen/staged/AcceptanceSessionTitleDeriverTests.swift b/tasks/frozen/staged/AcceptanceSessionTitleDeriverTests.swift
index 5f32277..5352295 100644
--- a/tasks/frozen/staged/AcceptanceSessionTitleDeriverTests.swift
+++ b/tasks/frozen/staged/AcceptanceSessionTitleDeriverTests.swift
@@ -344,14 +344,20 @@ struct AcceptanceSessionTitleDeriverTests {
         expectBoth("important fix", "important fix", "important fix")
     }
 
-    @Test("全角カタカナを半角カナへ幅変換する")
-    func fullwidthKatakanaConvertsToHalfwidth() {
-        expectBoth("カタカナ修正", "ｶﾀｶﾅ修正", "fw katakana")
+    @Test("半角カナを全角カナへ幅変換する")
+    func halfwidthKatakanaConvertsToFullwidth() {
+        expectBoth("ｶﾀｶﾅ修正", "カタカナ修正", "hw katakana")
+        expectBoth("ｶﾞ行を修正", "ガ行を修正", "hw dakuten")
     }
 
-    @Test("濁点付き全角カナを半角カナ+半角濁点へ幅変換する")
-    func fullwidthVoicedKatakanaConverts() {
-        expectBoth("ガ行を修正", "ｶﾞ行を修正", "fw dakuten")
+    @Test("全角英数を半角へ幅変換する")
+    func fullwidthLatinAndDigitsConvertToHalfwidth() {
+        expectBoth("ＡＢＣ１２３", "ABC123", "fw ABC123")
+    }
+
+    @Test("全角カナは変更しない")
+    func fullwidthKatakanaIsUnchanged() {
+        expectBoth("カタカナ修正", "カタカナ修正", "fw katakana kept")
     }
 
     @Test("半角カナと半角濁点は幅変換後も保持する")
```

## selftest 原文

退避先のテストは正位置に無いためコンパイル確認はしていない。配線検査だけを両モードで走らせた。

### `ruby .claude/scripts/task41-wiring.rb --selftest`

exit 0。

```
task41-wiring --selftest: OK
```

### `TASK41_SCOPE_CHECK=1 ruby .claude/scripts/task41-wiring.rb --selftest`

exit 0。

```
task41-wiring --selftest: OK
```

## 判断に迷った点

`halfwidthKatakanaAndDakutenAreKept` は同一入力（`ｶﾀｶﾅ修正` / `ｶﾞ行を修正`）に対し半角のままを期待する。新ケースの半角→全角と両立しない。指示どおり「他のケースは変更しない」ため未改変。再凍結前に PM が残すか直すかを決める必要がある。

=== REPORT COMPLETE ===
