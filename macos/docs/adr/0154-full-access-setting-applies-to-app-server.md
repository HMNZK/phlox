---
status: accepted
last-verified: 2026-08-01
---

# ADR 0154: フルアクセス設定を app-server セッションの承認・サンドボックス方針へ適用する

> **このファイルの役割**: 設定「フルアクセス（bypass）」が Codex の app-server セッションにも
> 効くようにした決定と、設定とコンポーザの Permission メニューの役割分担。
> **書かないもの**: 承認バナーそのものの是非（→ [ADR 0152](0152-codex-unsupported-server-request-is-not-an-approval.md)）。

## 文脈

不具合報告の調査で、ADR 0152 の写像バグとは**独立した 2 つ目の欠陥**が見つかった。
`BypassSettings`（キー `phlox.bypass.codex`、未設定時は既定 ON）はターミナルモードの
CLI 起動オプションにしか届いておらず、app-server セッションでは
`SessionSpawnService` が `approvalPolicy` / `sandboxPolicy` を**固定値でハードコード**していた。
つまりフルアクセスを ON にしても app-server では承認が出続ける状態だった。

## 決定

`SessionSpawnService.appServerApprovalPolicy(for:defaults:)` /
`appServerSandboxPolicy(for:defaults:)` が `BypassSettings.isEnabled(for: .codex)` を読み、
`SessionLaunchContext` ごとに次を返す。

| フルアクセス | approvalPolicy | sandboxPolicy |
|---|---|---|
| ON（既定） | `never` | `danger-full-access` |
| OFF | `on-request` | `workspace-write` |

**設定が決めるのはスレッド開始時の初期値**であり、開始後はコンポーザの Permission メニューで
上書きできる（ゲート①の決定 D3）。設定を「常時強制」にはしない。

## 結果

- フルアクセス ON のとき、app-server セッションでコマンド実行・パッチ適用の承認が出なくなる。
  ユーザーが設定でこの挙動を ON/OFF できるという当初の要求を満たす。
- ON が既定なので、既存ユーザーの体感は「承認が減る」方向に変わる。承認を戻したい場合は
  設定を OFF にするか、セッションごとに Permission メニューで切り替える。
- `danger-full-access` はサンドボックスを外すため、ON のセッションは作業ディレクトリ外へも
  書き込める。これは設定名（フルアクセス）が意味するとおりの挙動として受け入れる。
- 呼び出し側は既定引数のまま変更不要（`defaults:` は `.phloxDefaults()` 既定）。
  テストは専用の `UserDefaults` スイートを渡して ON/OFF を切り替える。
