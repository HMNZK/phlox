---
status: accepted
last-verified: 2026-08-02
---

# ADR 0158: Debug ビルドも証明書で署名できるようにし、TCC の承認をリビルドを跨いで保持する

> **このファイルの役割**: Debug 構成の署名を ad-hoc 固定から「ローカル設定があれば正規署名」へ
> 変えた決定と、その理由（TCC 承認ダイアログの再発）。
> **書かないもの**: Release 版と Debug 版の共存手順（→
> [guides/running-release-and-debug-together.md](../guides/running-release-and-debug-together.md)）。

## 文脈

Debug ビルドを作り直すたびに、「"Phlox" から "ダウンロード" フォルダ内のファイルへの
アクセス権を求められています」等の TCC ダイアログが繰り返し出ていた。一度「許可しない」を
選んでも、次のビルドでまた聞かれる。

調べた事実は 2 つある。

**1. 実際に触っているのは Phlox 自身ではなく、Phlox が起動した `claude` CLI。**
`tccd` の帰属チェーンにそのまま残っている:

```
accessing    = com.anthropic.claude-code, /Users/.../.local/share/claude/versions/2.1.220
responsible  = com.phlox.Phlox.debug
service      = kTCCServiceSystemPolicyDownloadsFolder
```

macOS は責任プロセス（responsible process）の名前で聞くため、ダイアログには子プロセスではなく
「Phlox」と出る。アプリ側の Swift コードに `~/Downloads` を触る経路は無い。

**2. 毎回聞かれるのは Debug が ad-hoc 署名だから。**
ad-hoc（Sign to Run Locally）の designated requirement は `cdhash H"..."` そのもので、
リビルドのたびに変わる。TCC は許可／拒否を designated requirement と紐づけて保存するため、
記録は毎回無効化される（`tccd`: `Failed to match existing code requirement for subject
com.phlox.Phlox.debug`）。Release 版は Developer ID 署名なので同じ問題が起きず、
一度答えて以降は聞かれていなかった。

同じ ad-hoc の不安定さは既に別の症状も起こしていた（Dock 表示名が更新されない問題への
`lsregister` 再登録スクリプト。`project.yml` の postBuildScripts）。

## 決定

**Debug 構成の署名を、リポジトリ既定は ad-hoc のまま、ローカル設定があれば正規署名に切り替わる
形にする。**

- `macos/Config/Signing.xcconfig`（コミット対象）を Debug / Release 両構成の設定ファイルにし、
  既定値として ad-hoc 相当（`CODE_SIGN_STYLE = Automatic` / `CODE_SIGN_IDENTITY = -` /
  チーム ID 空）を置く。
- 末尾で `#include? "../../Signing.local.xcconfig"` する。`#include?` はファイルが無ければ
  黙って読み飛ばすので、**証明書を持たない環境のビルドは今までどおり通る**。
- `project.yml` の署名設定はこの xcconfig の変数を参照するだけにする
  （`CODE_SIGN_STYLE: "$(PHLOX_DEBUG_CODE_SIGN_STYLE)"` 等）。ターゲットの build settings は
  xcconfig より優先されるため、直接値を書くと上書きの余地が無くなる。
- Release の `DEVELOPMENT_TEAM` も同じ変数から引く。従来はここが `""` 固定で、
  正規署名するには毎回 `xcodebuild` の引数でチーム ID を渡す必要があった。

「Debug も常に Developer ID を要求する」案は採らなかった。OSS の利用者が証明書無しで
ビルドできなくなるためである。「TCC の許可を事前に配布する」案も採れない
（TCC.db への書き込みは SIP か MDM が要る）。

## 結果

- 正規署名した Debug の designated requirement は
  `anchor apple generic and identifier "com.phlox.Phlox.debug" and ... certificate leaf[subject.OU] = "<TeamID>"`
  になり、cdhash を含まない。**リビルドしても同一**なので、一度答えた TCC の判断がそのまま残る。
  実測: cdhash を変えたビルドで再起動しても Downloads は
  `Auth Right: Denied (User Consent), DB Action:None` で解決し、ダイアログは出なかった。
- 切り替え直後だけ、**サービスごとに一度ずつ聞かれる**。ad-hoc 時代の記録は旧 identity に
  紐づいていて引き継がれないため。そこで答えた結果は以後保持される。
- 埋め込みの Sparkle.framework も同じチーム ID で再署名されるため、hardened runtime の
  library validation と整合する（ad-hoc では不整合になる。→ delivery 0025）。
- デバッガ接続は維持される。`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: YES` により Debug には
  `com.apple.security.get-task-allow` が入ったままである（署名後の entitlements で確認済み）。
- `claude` CLI が `~/Downloads` を読もうとする理由自体は未特定。TCC の記録には Phlox 経由でない
  `claude` 単体の要求も残っており、Phlox 固有の挙動ではない。本 ADR はダイアログの
  **再発**を止めるもので、アクセスそのものを無くしてはいない。
