---
status: completed
verdict: changes_required
review_mode: static
output_path: docs/agent-output/task41-acceptance-adversarial.md
file_written: false
---

指摘は **MUST 1件、HIGH 6件、MED 1件**。後続契約と凍結検査が衝突し、公開型・純粋性・入力除外の違反を受け入れ検査が見逃すため、現状での受け入れ承認はできない。

指定の2手順を読み、①単一責務、②入力被覆、③反証可能性、④変更許可範囲、⑤既存契約・ADR、⑥課金なし目視手順を静的確認した。以下の変異例は実走結果ではない。

**1. MUST — 後続の正当な変更をtask-41検査が拒否する**

根拠：`.claude/scripts/task41-wiring.rb:330–345,552–560`、`tasks/task-44.md:15–16`、`tasks/task-45.md:12,202–207`。

Rubyは導出ファイル以外のAgentDomainソースについて、新規追加も既存変更も拒否する。task-44の`SessionTitleState.swift`追加・`PersistedSessionDescriptor.swift`変更、task-45の`SessionTitlePresentation.swift`追加は必ずNGになる。一方、task-45は元のtask-41凍結SHAによる再検査を要求する。公開APIの契約文面は接続しているが、検査の寿命が後続契約と矛盾する。

**テスト/rb側の修正案：着手時の変更範囲検査と継続する導出契約の回帰検査を分離し、後続の許可変更を通す正例と導出契約違反を落とす負例を凍結する。**

**2. HIGH — `String?`への型変更を公開API検査が見逃す**

根拠：`.claude/scripts/task41-wiring.rb:277–279`、凍結Swiftテスト`:13,17–20,27–33`、`tasks/task-41.md:39–45`。

Rubyは`publiclettitle:String`の部分一致なので、`public let title: String?`でも通る。Swiftテストも`result?.title == expected`という値比較であり、値が入っていれば非Optional型であることを保証しない。task-44が要求する状態の`name: String`への受け渡しで初めて型不整合が表面化し得る。

**テスト/rb側の修正案：通常の`import AgentDomain`から戻り値を取り出し、両プロパティを明示的な`String`変数へ代入するコンパイル検査と、Optional型への単独変異負例を追加する。**

**3. HIGH — 純粋性違反と文字列補間内の実行コードを見逃す**

根拠：`.claude/scripts/task41-wiring.rb:10–48,62–65,302–325`、`tasks/task-41.md:65,110`。

禁止語一覧には`print`、`ProcessInfo`、`random`等がなく、正しい戻り値を維持したまま`print(text)`を追加しても検査ではNGにならない。`Date .now`も検出対象外。文字列全体をマスクするため、Swiftの文字列補間内で実行される呼び出しも消える。属性付きの`@preconcurrency import Darwin`も行頭`import`の正規表現から外れる。

**テスト/rb側の修正案：補間内コード・属性付きimportを検査対象に含め、出力・設定参照・時計・乱数の各違反を独立した負例で固定する。**

**4. HIGH — 4空白インデント除外を削除しても対応テストが通る**

根拠：凍結Swiftテスト`:151–154`、`tasks/task-41.md:55,89`。

入力は`"    let value = 1\nログインを修正"`だけである。4空白の除外処理を削除しても、トリム後の`let `接頭辞で同じ行が除外され、期待値を満たす。このテストはインデント規則単独の保護になっていない。

**テスト/rb側の修正案：`"    説明\nログインを修正"`の期待値を`"ログインを修正"`に固定し、3空白なら`"説明"`を採る対の検査を追加する。**

**5. HIGH — selftestの負例が単一違反に分離されず、各検査の保護力を保証しない**

根拠：`.claude/scripts/task41-wiring.rb:418–432,503–514`、`docs/agent-output/tests-task-41.md:160`。

「コメントだけの宣言偽装」はstructとenumを同時に消し、どちらかのエラーがあれば成功する。「解析不能」もstruct未閉鎖に加えてenumが存在しない。各プロパティ・公開修飾・適合宣言を1件ずつ壊す負例はなく、例えば`title`の検査を削除してもselftestはそれを検出できない。親コミットがない場合の契約不一致検査も「無効なSHA」で代用している。

HEAD自己比較対策自体は`:125–127,226–245`でblobの内容一致と実装ファイル不在を確認しており、単なるHEAD文字列拒否だけではない。ただし、その本番接続を外す変異はselftestで保護されていない。

**テスト/rb側の修正案：有効な正例から条件を1件だけ変え、期待するエラー集合を厳密比較し、基準検査の本番接続にも単独変異検査を設ける。**

**6. HIGH — 凍結前に必要なアサーションREDの証拠がない**

根拠：`docs/agent-output/tests-task-41.md:49–53,180`、凍結Swiftテスト`:3–5`。

報告の原文は「エラーはすべて `cannot find 'SessionTitleDeriver' in scope`」。これはコンパイル失敗であり、アサーションが誤実装を拒否した証拠ではない。指定手順の「**アサーションで落ちる red を確認**」を満たしていない。期待値そのものは製品出力から生成されず、独立リテラルになっている。

**テスト/rb側の修正案：PMが隔離した検証環境でコンパイル可能な変異実装を使い、規則を除去したときに失敗するアサーション名・期待値・結果を記録する。**

**7. HIGH — 課金なし目視の成立条件が再現可能な形で指定されていない**

根拠：`tasks/task-44.md:299–305`、`tasks/task-45.md:220–230`、`SessionRestoreCoordinator.swift:185–228`。

契約は「PM確認済みの復元失敗用データ」を複製させるが、fixtureの所在・内容・確実に失敗する条件を指定していない。実コードではチャット復元時に`agentRef`から起動計画を再生成するため、保存した`command`を存在しないパスに変えるだけでは失敗を保証できない。またthread ID不在の判定より先にクライアント生成へ進む。切断クライアントを使う失敗経路は実在するが、契約の手順だけではそこへの到達を保証できない。

**契約側の修正案：PTY／チャット別のfixtureパスと内容、実クライアント生成前に失敗する条件、隔離起動コマンドを固定し、実AIプロセス不在の確認を手順に含める。**

**8. MED — 入力空間に未被覆の領域が残る**

確認した軸は、言語・Unicode、空白・改行、スキル呼び出し、コード除外、URL、長さ、空入力である。凍結Swiftテストには次の領域がない。

| 未被覆領域 | 見逃し得る違反 |
|---|---|
| URL | `https://example.com`をコメントやコマンドとして誤除外 |
| 極端に長い入力 | 33文字まで正しく、それ以上で全文欠落・走査不良 |
| 単独CR | CRLFだけ正規化し、CRを行境界として扱わない |
| 全角空白のみ・連続する内部空白 | 空候補の採用、空白圧縮漏れ |
| 1〜3空白付きフェンス、開始より長い終了フェンス | 有効なフェンスを認識しない |
| 終了フェンス後の非空白文字 | 本来閉じない行でフェンスを閉じる |
| 除外接頭辞に似た英語の適格行 | `Return home`、`important fix`等の過剰除外 |
| 半角カナ・濁点の幅変換 | 全角英数字だけの置換で合格する |

根拠：`tasks/task-41.md:53–63`、凍結Swiftテスト`:36–242`。日本語、ASCII、家族絵文字、結合文字、`/review`、空文字などの既存ケースから、上記領域の成立までは判定できない。

**テスト/rb側の修正案：表の未被覆領域に独立した固定期待値を追加し、極端な長さは具体的なfixtureサイズと全文保持条件を定める。**

検証制約：必須ラッパー経由のselftest起動はexit 1。原文は以下のとおりで、Ruby本体は実行されていない。

```text
mktemp: mkstemp failed on /tmp/tmp.SQZyg0CMbw: Operation not permitted
/Users/ryosuke/.agents/scripts/compact-test: line 26: : No such file or directory
cat: : No such file or directory
```

Swift・変異検査・GUIは未実走。Gitによる読み取りでは、退避中Swiftテストと凍結SHA `7a31a0b`の正位置blobはともに`ebdfba87ae320bb9d44e8f93466620a58c2f9eec`で一致し、Rubyにも凍結時点との差分はなかった。読み取り専用制約により、指定ファイルへの保存は未実施。

=== REPORT COMPLETE ===