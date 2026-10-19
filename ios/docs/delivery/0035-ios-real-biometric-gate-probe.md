# 実LocalAuthenticationの専用Simulator検査

## 実装前の契約

製品は変更しない。新しい `RealBiometricGateTests.swift` の独立suite `RealBiometricGateTests` で、本物 `AppRoot` / `LaunchGateView` / view-model / `BiometricGate` をhostする。認証以外の依存はインメモリとAPI spyを使い、実ネットワーク・Keychainには出ない。

親だけが今回所有する専用Simulatorで疑似Face ID enrollmentを操作する。実生体・端末パスコード・credentialを変更しない。初回利用許可が出たら許可せず取り消し、ackに `permissionBlocked` を指定する。testはblocked記録を残してエラーで終わり、pass/skipにはしない。許可済みで実OS認証画面が出たら、親がOS画面を撮影してCancelし、再試行後Matching Faceを送る。

既存対話suiteと分けて実行する。selectorは `PhloxMobileSnapshotTests/RealBiometricGateTests`、専用env `PHLOX_REAL_BIOMETRIC_PROBE=1` が必要（`TEST_RUNNER_`接頭辞対応）。出力は `PHLOX_REAL_BIOMETRIC_OUTPUT`、既定は `.verification/ios-redesign-stage8b/remaining/real-biometric/`。Simulator窓名は `PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE` を親が渡す。

## ready/ack

sceneは `RealBiometricGate`。各stepはnonce/pid/udid/scene/step/requestedAt/ackFileと実auth呼出し状態をready JSONへ保存する。ackは同じ識別子と `phase=reviewed` / `confirmed=true` / `capturedAt` / `outcome` を持つ。OS画面はアプリwindowのPNGには写らないため、各ackに親が採取した `screenshotFile` の絶対パスも必要とする。

1. `os-cancel`: 初回許可なら取消＋`permissionBlocked`、実Face ID認証ならOS画面撮影＋Cancel＋`authenticationCancelled`。actual evaluatePolicy完了を待つ。
2. `retry-match`: アプリの「もう一度 Face ID」から再試行し、実OS画面を撮影してSimulatorのMatching Faceを送る。`authenticationMatched` とackする。actual authenticate呼出し2回・完了、AppModel.unlocked、保持overlay復帰、API write0回を必須確認する。

各stepは180秒。応答期限切れや途中失敗でOS評価がpendingなら `cleanup-cancel` readyを発行し、親がOS Cancelで評価を終わらせて `authenticationCancelled` とackする。cleanupも180秒で記録・失敗を出すが、pendingのままhostを閉じず、新nonceでCancelを再要求して親の収束操作を待つ。Task.cancelだけで終了済みとは扱わない。エラーログと結果は一意ディレクトリへ保存する。親は終了後疑似enrollmentを元の状態へ戻す。

ビルド・Simulator・実操作は親の次のBFTとGOを待つ。実OS認証画面と結果の検査は未実施である。
