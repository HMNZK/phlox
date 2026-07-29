---
status: completed
last-verified: 2026-07-30
---

# 0018: iOS から作ったセッションが macOS の「その他」に落ちる問題

関連: [ADR 0141](../../../macos/docs/adr/0141-spawn-project-id-wire.md) /
[specs/mobile-api-extensions-contract.md §7.1.1](../specs/mobile-api-extensions-contract.md) /
[macos/docs/architecture/mobile-proxy.md](../../../macos/docs/architecture/mobile-proxy.md)

## 何をしたか

「iOS でプロジェクト（Gardenia）を選んでセッションを作ったのに、macOS 側で『その他』に入る」という
報告の原因を特定し、選んだプロジェクトを spawn まで届ける配線を iOS・macOS の両側で通した。

## 判ったこと

- 「その他」は `DashboardViewModel.unassignedSessionNodes`（`projectID == nil`）の一点で決まる。
  **CWD はグルーピングに一切関与しない**ので、作業ディレクトリを合わせても直らない。
- 欠落は 2 段あり、片方だけ直しても再現した。
  1. iOS: 選んだプロジェクトは `SpawnRequest.workspace` に入るが `PhloxAPIClient.spawn` の送信 DTO には
     載らず、ローカルの `Session.subtitle` に使われるだけだった（`DTOs.swift` のコメントが
     「workspace/prompt は無視」と明記＝意図的な既存仕様）。
  2. macOS: `Action.spawn` → `ControlActionHandler.handleSpawn` → `spawnNewSessionFromControlAPI` に
     projectID を渡す引数が無く、`spawnNewSessionImpl(projectID:)` を常に既定 nil で呼んでいた。
- 親からの継承も効かない。モバイルの要求元は実在セッションでないため
  `SessionOriginPolicy.origin` が `parentSessionID: nil` を返し、`resolveProjectID` も nil になる。
  救済経路が無く 100% 再現する。
- 受け皿（`spawnNewSessionImpl(projectID:)` と `resolvedWorkingDirectoryPath`）は既に存在していた。
  欠けていたのは配線だけだった。
- 同根の可視バグがもう 1 件あった。下書き画面の文脈ラベルが `ProjectGroup.id`（実運用では UUID）を
  表示していた。下書きが「表示名」と「ID」を 1 本の String に押し込んでいたのが原因。

## 変更したもの

**macOS**（`2a192c2` / `aef7255`）
- `ControlServer`: `SpawnBody.projectId` を `UUID(uuidString:)` で検証し、成功時のみ `ProjectID` にして
  `Action.spawn(ref:backend:workingDirectory:projectID:)` へ載せる。parse 失敗は 400。
- `AppBootstrap`: `ControlActionDashboard.spawnSession(…, projectID:)`、`handleSpawn` の転送、
  `mapSpawnError` に `unknownProject → 422` を追加。
- `DashboardFeature`: `spawnNewSessionFromControlAPI(…, projectID:)` が spawn 開始前に存在検査を行い、
  無ければ `AgentSpawnError.unknownProject` を throw。
- `macos/App`: conformance の追随。

**iOS**（`41fdd71` / `b2baa18`）
- `SpawnRequest.projectID` / `SpawnRequestDTO.projectId`（nil ならキーごと省略）/ `PhloxAPIClient.spawn` の送信。
- `ProjectGroup.projectID`（本物の `session.projectId` のときだけ非 nil）と `ProjectGroup.addSessionDraft`。
- `SessionComposeDraft` が表示名と projectID を分けて運ぶ。`Route`・`onAddSession`・
  `SessionDetailViewModel` の追随。

## 効いた設計判断

- **projectID を `Action.spawn` の associated value で運ぶ**（`ControlSpawnContext` のような
  サーバ側の可変一時状態に載せない）。role/model がその方式で、ControlServer のテストが並列実行で
  相互に踏み合って落ちる原因になっている（`.claude/verify.sh` が `--no-parallel` を使う理由）。
- **未知の projectId は黙って未所属で作らず 422 で拒否する**。今回のバグは「黙って未所属になる」
  ことで気づかれずに残った。同じ失敗の形を仕様に固定しない。
- **公開シグネチャに既定値 `= nil` を置かない**。独立レビューが、既定値のせいで 8 箇所の呼び出し元が
  未更新のまま通っている（＝同型の穴がコンパイラから隠れる）ことを検出した。

## 検証

- `.claude/verify.sh`（フィルタ・skip なしの全数）exit 0:
  ControlServer 146 / AppBootstrap 155 / DashboardFeature 1496 / PhloxKit 649 = **2446 tests pass**。
- `xcodebuild -project macos/Phlox.xcodeproj -scheme Phlox build` → BUILD SUCCEEDED
  （SwiftPM のテストは `macos/App` をコンパイルしないため、conformance の型検査はここで担保する）。
- `xcodebuild -project ios/PhloxMobile.xcodeproj -scheme PhloxMobile build` → BUILD SUCCEEDED。
- **未実施**: 実機 iPhone → 実 Mac の縦断確認。HTTP から ViewModel までを 1 本で通す自動テストも無く、
  3 区間（HTTP→Action / Action→spawnSession / spawnNewSessionFromControlAPI→割り当て）に分けて
  固定している。

## 積み残し

- `E2EControlServerTests` のダッシュボードスタブが `projectID` を捨てているため、HTTP から
  プロジェクト配下のセッションが生まれる縦断テストが存在しない。スタブを
  `spawnNewSessionFromControlAPI` に差し替えれば張れるが、既存 E2E の origin/launchContext の意味が
  変わるため今回は見送った。
- 起動直後（`ControlActionHandler.dashboard` の結線後・`DashboardViewModel.start()` の projects ロード前）に
  届いた正しい projectId が一時的に 422 になりうる（未実測）。本変更前は同じ窓で「黙って未所属で
  作られる」＝今回直したバグそのものが起きていたので退行ではない。
- ControlServer の既存 flaky（`pendingSpawnRole`/`pendingSpawnModel` の可変一時状態を並列テストが
  踏み合い 3 件落ちる）は本 run のスコープ外として温存。`--no-parallel` で回避している。
- iOS が作成できるのは「セッションが 1 件以上あるプロジェクト」だけ（一覧をセッションから導出して
  いるため）。セッション 0 件のプロジェクトへ作るには `GET /projects` 相当の新設が要る。
