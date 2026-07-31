---
status: accepted
last-verified: 2026-08-01
---

# ADR 0151: PTY spawn は継承可能な fd を既定で close-on-exec にする（`POSIX_SPAWN_CLOEXEC_DEFAULT`）

> **このファイルの役割**: `PTYKit`（`Posix.spawn`）が子プロセス（ユーザーターミナルのシェル）を
> `posix_spawn` するときに、無関係な fd（他所で開いている `Pipe` 等）を継承しないようにした決定。
> **書かないもの**: `WorkingTreeService.runGit` の stdout/stderr 排出方式（→ [ADR 0150](0150-editor-panel-git-semantics.md)）、
> ユーザーターミナルのライフサイクル（→ [ADR 0149](0149-user-terminal-lifecycle.md)）。

## 文脈

task-5 でターミナルパネルとエディタパネルを同一ドロワーに同居させたことで、初めて
「ユーザーターミナルの PTY spawn（`posix_spawn`）」と「エディタパネルの `WorkingTreeService.runGit`
（`Foundation.Process` + `Pipe`）」が同一プロセス内で並行に走る構成になった。この組み合わせで、
テスト全数を並列実行したときにだけ再現する断続的ハングが 2 回観測された
（1 回目は task-3 マージ後検証で負荷起因の一過性と判定し継続、2 回目は task-5 で決定論的な
修正を要する不具合として再調査を委譲）。

r2 レビューでスタックトレースを採取した結果、`git` プロセスの stdout パイプに対する
`readDataToEndOfFile()` が `read(2)` で恒久停止していた。原因は次のとおり:

- `Posix.spawn`（`PTYKit/Sources/PTYKit/Posix.swift`）は `posix_spawn_file_actions_addclose` で
  PTY の `slaveFD`・`masterFD` の 2 本だけを閉じており、それ以外の継承可能な fd（親プロセスが
  他所で開いている `Foundation.Pipe` の書き込み端など）を子（ユーザーシェル）へ**そのまま継承**
  していた。
- `WorkingTreeService.runGit` が `git` の実行に使う `Pipe` の書き込み端を、たまたま同時に
  `posix_spawn` された子シェルが継承すると、その子シェルが生きている間ずっと write 端の参照が
  残るため、`readDataToEndOfFile()` は EOF を受け取れず永久に返らない。

## 決定

**`Posix.spawn` の `posix_spawnattr_setflags` に `POSIX_SPAWN_CLOEXEC_DEFAULT`（`0x4000`）を追加する。**
これにより、`file_actions` で明示的に `dup2` されなかった fd（0/1/2 以外の全て）は子側で既定
close-on-exec 扱いになり、無関係な `Pipe` の fd を継承しなくなる。PTY の `slaveFD` を複製した
`STDIN_FILENO`/`STDOUT_FILENO`/`STDERR_FILENO` はこのフラグの対象外（`addup2` で明示済み）なので、
シェルの入出力は従来どおり機能する。

多層防御として `WorkingTreeService.runGit` 側の `Pipe` に別途 `FD_CLOEXEC` を立てることも検討したが、
**不要と判定した**。実測により Foundation の `Process`/`Pipe` は既に CLOEXEC 既定で fd を作っており
（`/bin/sh` へ渡らないことを実プローブで確認）、リポジトリ内で `posix_spawn`/`fork` を直接呼ぶのは
`PTYKit/Posix.swift` の 1 箇所のみ（`SwiftTerm` の `fork` 経路はアプリから未使用）と確認できたため、
漏らし手は 1 箇所に閉じている。

## 棄却した選択肢

- **`readers.wait()` / `waitUntilExit()` に期限を付けて逃げる**: 明示的に不採用とした（対症療法）。
  fd を握ったシェルが生き続ける限り、期限で抜けても `git` の出力を取りこぼす。原因（fd の複製）
  そのものを入口で止める方を選んだ。

## 結果

- 変異検証（`POSIX_SPAWN_CLOEXEC_DEFAULT` を外すと fd リークが再現すること）とスタック採取の
  両方で根本原因への到達を確認済み（レビュー r3）。
- 回帰保護: `PosixSpawnCloexecTests`（`PTYKit`。無関係な `Pipe` の書き込み端 fd を子シェルへ
  渡し、`printf ... >&<fd>` が親へ届かない＝継承されないことを直接観測する）。
- 実アプリでの PTY 起動退行チェック（Claude/Codex/Cursor CLI が fd 3 以降を前提にしていないか）は
  レビューで「今回の修正に直結する最優先項目」として統合検証フェーズへの持ち越しに指定されている
  （[delivery/0029](../delivery/0029-terminal-editor-panels-worklog.md) 参照）。
