# tasks/frozen — ディスパッチ待ちの受け入れテスト置き場

Swift は同一テストターゲット内の全ファイルがコンパイルできないとテストが 1 件も走らない。
そのため、まだ実装が始まっていないタスクの受け入れテストをテストターゲットへ置いたままにすると、
**先行タスクの verify まで巻き添えで落ちる**。

そこでフェーズ1では、すぐディスパッチするタスクの受け入れテストだけをテストターゲットへ置き、
残りはここへ凍結して置く（コミット済み＝実装役は改変できない）。

## 運用

PM は該当タスクをディスパッチする直前に、次を行う:

1. `tasks/frozen/<Name>.swift` を所定のテストターゲットへ `git mv` する
2. その状態でコミットする（これが凍結コミット）
3. コミットの SHA と配置先パスを `tasks/frozen/BASELINES.txt` にタブ区切りで追記する
   （`.claude/verify.sh` がこれを読み、配置済みのものだけ無改変を検査する）

## 配置先

| ファイル | タスク | 配置先 |
|---|---|---|
| `AcceptancePairedDeviceStoreTests.swift` | task-1 | `macos/Packages/AgentDomain/Tests/AgentDomainTests/` |
| `AcceptanceLegacyTokenPurgeTests.swift` | task-1 | 同上 |
| `ContractPairedDeviceStoreSeamTests.swift` | task-1 | 同上 |
| `AcceptanceDeviceProvisioningTests.swift` | task-2 | 同上 |
| `AcceptanceDeviceRevocationTests.swift` | task-2 | 同上 |
| `AcceptancePendingTokenExpiryTests.swift` | task-2 | 同上 |
| `AcceptancePairingLifecycleIntegrationTests.swift` | task-4 | 同上 |
