import AgentDomain
import Foundation
import Testing
@testable import PTYKit

/// review-task-5-r2.md MUST-A の再現テスト。`Posix.spawn` は file_actions で
/// 明示的に dup2 した fd（PTY の slaveFD 複製）以外の、たまたま親プロセスで開いている
/// fd（例: 別スレッドが同時に実行している `git` の pipe 書き込み端）を、
/// `POSIX_SPAWN_CLOEXEC_DEFAULT` が無いと子プロセスへ継承してしまう。
/// 継承された書き込み端が生き続けると、pipe の読み手（`WorkingTreeService.runGit` 等）は
/// EOF を受け取れず恒久的にブロックする。
///
/// このテストは、spawn とは無関係な pipe を親側で開いておき、子プロセスから
/// その pipe の書き込み端 fd 番号へ直接書き込みを試みさせることで、fd が
/// 子プロセスに継承されているかどうかを決定論的に判定する（ハングの再現ではなく、
/// fd の生死を直接観測する形。レビューが挙げた 20 並列レースより安定する）。
/// 子の終了検知は本パッケージの標準経路である `PTYManager`（`DispatchSourceProcess` /
/// `exitStream`）を使う。テストコードで直接 `waitpid` を呼ぶと、テストランナー
/// プロセス内の他所（Foundation 等）による子プロセスの終了通知と競合しうるため、
/// production と同じ経路に揃えている。
@Suite("Posix spawn CLOEXEC default white-box tests")
struct PosixSpawnCloexecTests {
    @Test(
        "posix_spawn した子は、file_actions で明示 dup2 していない fd（他プロセスの pipe 書き込み端相当）を継承しない",
        .timeLimit(.minutes(1))
    )
    func spawnedChildDoesNotInheritUnrelatedFileDescriptor() async throws {
        // 「別スレッドで同時に実行中の git が持つ pipe の書き込み端」を模した、
        // このテスト固有の spawn とは無関係な pipe。
        let leakPipe = Pipe()
        let leakWriteFD = leakPipe.fileHandleForWriting.fileDescriptor

        let manager = PTYManager()
        // CLOEXEC_DEFAULT が効いていれば、子から見て leakWriteFD は exec 時に
        // 自動で閉じられ、`>&<fd>` への書き込みは失敗する（2>/dev/null で握りつぶす）。
        // 効いていなければ fd がそのまま複製され、"leaked" が pipe へ書き込まれる。
        let id = try await manager.spawn(
            command: "/bin/sh",
            args: ["-c", "printf leaked >&\(leakWriteFD) 2>/dev/null; exit 0"],
            env: ["PATH": "/usr/bin:/bin"],
            id: nil,
            initialSize: nil,
            workingDirectory: nil
        )

        // exit stream は `PTYManager` 内部の `DispatchSourceProcess`（kqueue EVFILT_PROC）
        // 経由で子の終了を検知してから 1 要素発行する。これを待てば子は既に reap 済み。
        var exitIterator = manager.exitStream(for: id).makeAsyncIterator()
        _ = await exitIterator.next()

        // 子は既に終了しているので、親が書き込み端を閉じれば read 側は
        // 追加データが来ないことを即座に確定できる（EOF 待ちでブロックしない）。
        leakPipe.fileHandleForWriting.closeFile()
        let leaked = leakPipe.fileHandleForReading.availableData
        leakPipe.fileHandleForReading.closeFile()

        #expect(leaked.isEmpty, "子プロセスが無関係な pipe の書き込み端を継承した（fd リーク）")
    }
}
