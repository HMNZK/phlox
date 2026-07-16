import Foundation
import Testing
@testable import AppBootstrap

/// 凍結受け入れテスト（PM 著・実装役は編集禁止）: シグナル起点クリーンアップ設置 API
/// `TerminationSignalHandlers.install(signals:queue:handler:)` の契約を検証する。
///
/// 契約（App/PhloxApp.swift の installSignalHandlers から抽出される公開 API）:
/// - 各シグナルに対し `signal(sig, SIG_IGN)` で既定動作を無効化してから DispatchSource を設置し resume する
/// - handler は `@Sendable`（呼び出し元の actor isolation を継承しない）で、指定キュー上で直接実行される
/// - 返り値の source 配列（シグナルごとに1本）は呼び出し側が保持する
///
/// 実装前は本ファイルは型不在のコンパイルエラーで red になる（未実装による失敗＝正当な red）。
/// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえで
/// ハーネス部分に限り修理してよい。
@Suite(.serialized) struct AcceptanceTerminationSignalTests {

    /// 使用後のシグナル状態を片付ける（source を止め、既定動作へ戻す）。
    private func tearDown(_ sources: [DispatchSourceSignal], signals: [Int32]) {
        for source in sources { source.cancel() }
        for sig in signals { signal(sig, SIG_DFL) }
    }

    /// シグナル送達でハンドラが非メインスレッドで発火し、プロセスが落ちない。
    @Test func handlerFiresOffMainThreadOnSignalDelivery() {
        let fired = DispatchSemaphore(value: 0)
        let wasMainThread = SignalSafeBox<Bool?>(nil)
        let sources = TerminationSignalHandlers.install(
            signals: [SIGUSR1],
            queue: DispatchQueue(label: "test.signal.usr1"),
            handler: {
                wasMainThread.set(Thread.isMainThread)
                fired.signal()
            }
        )
        defer { tearDown(sources, signals: [SIGUSR1]) }
        #expect(sources.count == 1)
        kill(getpid(), SIGUSR1)
        #expect(fired.wait(timeout: .now() + 5) == .success, "ハンドラが5秒以内に発火しない")
        #expect(wasMainThread.value == false, "ハンドラは指定キュー（非メイン）で実行されるべき")
    }

    /// 核心の回帰テスト: MainActor 文脈で生成したクロージャを渡しても、シグナル監視キューでの
    /// 実行が executor チェックで SIGTRAP しない（= API が @Sendable で受け、isolation を継承させない）。
    /// 旧バグ（PhloxApp.installSignalHandlers 内のクロージャ）はこの形で SIGTERM 受信時に必ずクラッシュした。
    @MainActor @Test func handlerFormedInMainActorContextDoesNotTrapOnSignalQueue() {
        let fired = DispatchSemaphore(value: 0)
        let sources = TerminationSignalHandlers.install(
            signals: [SIGUSR2],
            queue: DispatchQueue(label: "test.signal.usr2"),
            handler: { fired.signal() }
        )
        defer { tearDown(sources, signals: [SIGUSR2]) }
        kill(getpid(), SIGUSR2)
        #expect(
            fired.wait(timeout: .now() + 5) == .success,
            "MainActor 文脈から設置したハンドラが発火しない（isolation 継承ないし未 resume の疑い）"
        )
    }

    /// 複数シグナルの一括設置: シグナルごとに source が1本ずつ返り、連続送達でも落ちない。
    @Test func installReturnsOneSourcePerSignalAndSurvivesRepeatedDelivery() {
        let fired = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "test.signal.multi")
        let sources = TerminationSignalHandlers.install(
            signals: [SIGUSR1, SIGUSR2],
            queue: queue,
            handler: { fired.signal() }
        )
        defer { tearDown(sources, signals: [SIGUSR1, SIGUSR2]) }
        #expect(sources.count == 2)
        kill(getpid(), SIGUSR1)
        #expect(fired.wait(timeout: .now() + 5) == .success, "1回目（SIGUSR1）が発火しない")
        kill(getpid(), SIGUSR2)
        #expect(fired.wait(timeout: .now() + 5) == .success, "2回目（SIGUSR2）が発火しない")
    }
}
