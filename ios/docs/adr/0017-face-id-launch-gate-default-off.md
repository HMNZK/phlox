---
status: active
last-verified: 2026-07-16
---

# ADR 0017: 起動時 Face ID ゲートを既定オフにする

> **このファイルの役割**: wave-7 で、起動時の Face ID 本人確認ゲート（wave-5 で導入）を、新規インストール／未設定時に**オフ**（ロックしない）を既定とする決定を記録する。
> **書かないもの**: Face ID ゲートの実装機構（`LaunchGate`/`BiometricGate`/`AppModel.initialAuthState`・`shouldRelock` の現行構成 → [architecture/overview.md](../architecture/overview.md) の「Face ID 状態機械」）。

## 文脈

wave-5 で起動ゲート（生体認証成功まで API 接続をブロック）を導入した。設定値 `faceIDEnabled` は `UserDefaultsAppSettingsStore` に永続化し、**未設定（新規インストール）時の getter フォールバックは `true`（＝既定 ON）** だった（`AppSettingsStore.swift`）。この結果、インストール直後から毎回の起動・背景復帰でロックがかかっていた。

実機検証で「既定でロックがかかるのは過剰。使いたい人が設定で有効化する形にしたい」との要望が出た（wave-7 依頼）。

## 決定

- `UserDefaultsAppSettingsStore.faceIDEnabled` の getter フォールバックを **未設定時 `false`** に変更する。新規インストール／未設定時はロックせず、`AppModel.initialAuthState(faceIDEnabled: false) == .unlocked` で起動直後から利用できる。
- ユーザーが設定画面で明示的に ON にしたときだけ、従来どおり起動時ロック・背景復帰時の再ロックが働く（`AppModel.initialAuthState`/`shouldRelock` は `faceIDEnabled` を明示引数で受ける純関数のため**無変更**。既定値変更の影響を受けない）。
- 既定値を検証する凍結受け入れテスト `SettingsAcceptanceTests.settingsStoreReturnsDefaultsWhenUnset`（PM 著）を、新既定（`faceIDEnabled == false`）へ**再著**した。要件変更に伴う再定義であり、アサーションの弱体化ではない。
- `ios/project.yml` の `NSFaceIDUsageDescription` は**残す**（設定で ON にしたときに必要）。

## 結果

- 新規インストール時にロックがかからず、初回起動の摩擦が消えた。ロックが要る利用者は設定で ON にすれば wave-5 と同じ挙動になる。
- `notificationsEnabled`（既定 ON 維持）・`appearance`（既定 system）・setter・永続化・`AppSettings` write-through は不変。
- テスト: `AppSettingsStoreTests` の既定アサーションも新既定へ整合。`swift test --package-path ios/Packages/PhloxKit --no-parallel` 全数 green（`SettingsAcceptanceTests` 含む）。
- **未検証**: 実機での「既定オフで起動ロックが出ない／設定 ON で再びロックする」体感は本 run では未確認（シミュレータのユニットテスト＋ビルドまで）。

## 却下した代替案

- **既定 ON のまま初回起動のみスキップ**: 状態が「初回か否か」に依存し複雑化する。既定値そのものを false にする方が単純で意図に合致。
- **`InMemoryAppSettingsStore` の既定引数も false へ揃える**: テストダブルの便宜値であり本番経路は `UserDefaults`。既存テストは明示上書きで無害なため、サージカルに本番フォールバックのみ変更した（テストダブルの既定は追わない）。
