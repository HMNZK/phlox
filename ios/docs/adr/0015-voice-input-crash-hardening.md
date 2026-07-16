---
status: active
last-verified: 2026-07-16
---

# ADR 0015: 音声入力のクラッシュを、危険 API 呼び出し前のガードと nonisolated ブリッジで根絶する

> **このファイルの役割**: wave-6（task-2）で、音声入力（`DSVoiceInputController`／`DSLiveVoiceInputRecognizer`）が実機で落ちていた2つのクラッシュ機序（TCC 完了ブロックのスレッド境界違反・`installTap` の Objective-C 例外）を特定し、Swift の `do/catch` では捕捉できないという制約を前提に、危険 API を呼ぶ前のガードで防いだ決定を記録する。
> **書かないもの**: 入力欄の視覚再デザイン（→ [ADR 0016](0016-input-bar-compact-pill-redesign.md)）。音声入力の状態遷移・プロトコル構成全体（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

wave-5 task-1 で `DSVoiceInputController`（`VoiceInputRecognizing` 抽象＋既定実装 `DSLiveVoiceInputRecognizer`）を新設し、Speech/AVFoundation ベースの音声入力を追加した。wave-5 の実機検証では mic の実録音は未検証のまま残っていた（wave-5 worklog「積み残し・実機確認事項」）。wave-6 のゲート①で、実機検証により音声入力がクラッシュする不具合が確認され、修正対象6件の1つとして task-2 に切り出された。

実機のクラッシュログを取得する手段が無かったため（decision-log wave-6 フェーズ0/1）、PM は機序の仮説を実装役に課し、実装役が検証可能な形（`DSVoiceAudioFormatValidator`／`DSVoiceRecognitionSetupState` という純粋な値型への切り出しによるユニットテスト、および simulator 上での再現）で機序を特定させた。特定された機序は次の2つで、いずれも Swift の `do/catch(Error)` では捕捉できない種類のクラッシュだった:

1. **TCC 完了ブロックのメインスレッド境界違反**: `SFSpeechRecognizer.requestAuthorization` / `AVAudioApplication.requestRecordPermission` の完了ブロックは、実行スレッドを保証しない（メインキューで呼ばれるとは限らない）。既存コードはこれらを `@MainActor` 隔離のインスタンスメソッド内で直接 `withCheckedContinuation` に包んでいたため、完了ブロックがメインキュー外で `continuation.resume` を呼ぶと、Swift 6 のアクター隔離ランタイム検査に違反し、libdispatch のアサーション違反 → `SIGTRAP` でプロセスが落ちる。
2. **`installTap` の不正フォーマットによる ObjC 例外**: `AVAudioEngine.inputNode.installTap(onBus:bufferSize:format:)` に無効な `AVAudioFormat`（サンプルレート 0/非有限、チャンネル数 0 等）を渡すと、Objective-C の `NSException` を投げて `SIGABRT` で落ちる。`NSException` は Swift の `Error` プロトコルに準拠しないため、`do/catch` で捕捉できない（Swift の例外機構は ObjC 例外を対象にしていない）。

## 決定

- **危険 API 呼び出し前の前提検証**: `startRecognition` の先頭で、(a) 二重起動でないこと（`DSVoiceRecognitionSetupState.beginStart()` が `isStarting`/未解放資源を見て `false` なら早期に throw）、(b) simulator でないこと（`supportsLiveAudioCapture`、後述）、(c) 入力フォーマットが妥当であること（`DSVoiceAudioFormatValidator.isValid(sampleRate:channelCount:isStandard:)`）を、危険 API（`AVAudioSession.setActive`／`installTap`／`AVAudioEngine.start`）を呼ぶ**前**に順に検証し、いずれか不成立なら Swift `Error` として安全に throw する形に倒す。
- **フォーマット取得元の是正**: 検証に使う `AVAudioFormat` を、セッション活性化前の `inputNode.outputFormat(forBus: 0)` から、`AVAudioSession.setActive(true)` 後の `inputNode.inputFormat(forBus: 0)`（実ハードウェア入力値）へ変更した。活性化前の `outputFormat` は活性化後に変化しうるため、`installTap` に渡す直前の実測値で検証する。
- **`nonisolated static` ブリッジで TCC 完了ブロックのスレッド境界を正す**: `requestSpeechAuthorization()`／`requestMicrophoneAuthorization()` を `nonisolated private static func` として切り出し、`withCheckedContinuation` をメインアクター隔離コンテキストの外に置いた。TCC の完了ブロックが任意スレッドで `continuation.resume` を呼んでも、`@MainActor` 隔離の実行キュー検査に触れない。
- **安全なオーディオセッション設定**: `AVAudioSession` のモードを `.measurement` から `.default` へ変更し、`options` から `.duckOthers` を除去した（`.record` カテゴリは維持）。
- **simulator ガード**: `nonisolated private static var supportsLiveAudioCapture`（`#if targetEnvironment(simulator)` で `false`、実機は `true`）を新設し、simulator では `startRecognition` が `AVAudioEngine` に一切触れる前に `.unavailable` を throw する。Simulator の CoreAudio は物理入力を持たず、構成によっては `AVAudioEngine` の初期化が RPC タイムアウトでプロセスを abort させることがあるため、危険 API の手前で穏当に失敗させる（実機の経路はこのガードの影響を受けず温存される）。
- **状態追跡の値型化と一元的なクリーンアップ**: `isAudioSessionActive`/`hasInstalledAudioTap`/`isStarting` を `DSVoiceRecognitionSetupState`（`Equatable, Sendable` な値型）に集約し、`requiresCleanup` で未解放資源の有無を判定できるようにした。`startRecognition` の `do` ブロック内で失敗した場合は必ず `stopRecognition()` を経由してから元のエラーを再 throw する構造にし、再入時に中途半端な状態が残らないようにした。

## 結果

- 2機序（TCC 完了ブロックのスレッド境界違反・`installTap` の不正フォーマット例外）はいずれも、危険 API を呼ぶ前のガードで到達不能になった。
- `DSVoiceAudioFormatValidator`／`DSVoiceRecognitionSetupState` はユニットテストで直接検証可能（`DSVoiceInputControllerWave6Tests`）: 有効/無効なサンプルレート・チャンネル数・`isStandard` の組み合わせ、再入禁止と資源解放後の再開始許可。
- stage-2 レビューで Apple ヘッダの記述と突き合わせ、メインスレッド機序の妥当性を裏取り済み（decision-log wave-6 フェーズ2/3/4）。
- **未検証**: 実機での実録音成功経路（`swift test` は macOS ホスト実行のため iOS 専用 `SFSpeechRecognizer` 系コードはコンパイル対象外で、確認できるのは iOS シミュレータビルドの通過まで）。実機でクラッシュが再発しないことの確認は本 run では行えていない（実機クラッシュログ取得手段が無いままの機序特定であるため、この点は次回実機検証で裏取りが必要）。

## 却下した代替案

- **`do/catch` で ObjC 例外を捕捉しようとする**: Swift の例外処理は `Error` プロトコル準拠の Swift エラーのみを対象とし、`NSException` を捕捉できない言語仕様上の制約があるため不可能。
- **TCC 完了ブロックを `@MainActor` コンテキストのまま受け続け、`DispatchQueue.main.async` で resume だけラップする**: 部分的な緩和にはなるが、Swift 6 のアクター隔離検査がクロージャキャプチャ全体に及ぶケースを取りこぼす可能性があり、根本的な境界分離（`nonisolated static` 化）の方が確実と判断した。
- **simulator でも実際に音声認識を試行させる**: CoreAudio の制約により `AVAudioEngine` 初期化が RPC タイムアウトでプロセスを abort させる既知の構成があり、危険 API 呼び出し自体を simulator では回避するガードを採用した（実機の音声入力機能は温存）。
