import Foundation
import Testing
@testable import DashboardFeature

// MARK: - 受け入れテスト（loopflow task-1・PM 著・実装役は編集不可）
//
// 契約: cursor-agent（appServer backend）の spawn 環境に、ユーザーの zsh 起動ファイル
// （~/.zshrc 等）を読み込ませない ZDOTDIR を注入する。cursor-agent はシェルコマンド実行時に
// ユーザーの zsh をスナップショットするが、`alias ls="eza …"` 等の core コマンド上書きが
// あるとスナップショット機構が FD デッドロックしコマンドが永久ハングする。ZDOTDIR を
// zsh 設定ファイルの無い空ディレクトリへ向けることで、ユーザーの ~/.zshrc を編集せずに
// この破綻を回避する。PATH 等の他の環境変数は保持する（Phlox が注入する PATH を壊さない）。

@Test func sanitizedCursorEnvironment_setsZDotDirAndPreservesOtherVars() {
    let base = ["PATH": "/usr/bin:/bin", "FOO": "bar", "HOME": "/Users/x"]
    let result = CursorShellSanitizer.sanitizedEnvironment(base: base, zdotDir: "/tmp/phlox-empty-zdot")

    // ZDOTDIR が指定ディレクトリに設定される。
    #expect(result["ZDOTDIR"] == "/tmp/phlox-empty-zdot")
    // 他の変数（特に PATH）は保持される。
    #expect(result["PATH"] == "/usr/bin:/bin")
    #expect(result["FOO"] == "bar")
    #expect(result["HOME"] == "/Users/x")
}

@Test func sanitizedCursorEnvironment_overridesPreexistingZDotDir() {
    // base に既存の ZDOTDIR があっても、サニタイズ後は空ディレクトリを指す。
    let base = ["ZDOTDIR": "/Users/x", "PATH": "/usr/bin"]
    let result = CursorShellSanitizer.sanitizedEnvironment(base: base, zdotDir: "/tmp/phlox-empty-zdot")
    #expect(result["ZDOTDIR"] == "/tmp/phlox-empty-zdot")
}

@Test func ensureEmptyZDotDir_createsExistingDirectoryWithoutUserZshConfig() throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let dir = try CursorShellSanitizer.ensureEmptyZDotDir(inParent: parent)

    // 実在するディレクトリで、
    var isDir: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
    #expect(isDir.boolValue)
    // ユーザーの zsh 起動ファイルが存在しない（＝ ~/.zshrc の alias 等を読み込まない）。
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(".zshrc").path))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(".zshenv").path))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(".zprofile").path))
}

@Test func ensureEmptyZDotDir_isIdempotent() throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let dir1 = try CursorShellSanitizer.ensureEmptyZDotDir(inParent: parent)
    let dir2 = try CursorShellSanitizer.ensureEmptyZDotDir(inParent: parent)
    #expect(dir1 == dir2)
    #expect(FileManager.default.fileExists(atPath: dir2.path))
}

// 共有固定名 dir を再利用したとき、前回 spawn が残した zsh 設定（例: cursor-agent が
// スナップショット時に書きうる .zshrc の残骸）を掃除する load-bearing 分岐を検証する。
// これが無いと残骸 .zshrc（alias ls="eza" 等）が次回 spawn まで居座りデッドロックが再発する。
@Test func ensureEmptyZDotDir_removesPreexistingZshConfigFromReusedDir() throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let dir = try CursorShellSanitizer.ensureEmptyZDotDir(inParent: parent)
    // 前回 spawn の残骸を模す。
    let stale = dir.appendingPathComponent(".zshrc")
    try "alias ls=\"eza\"\n".write(to: stale, atomically: true, encoding: .utf8)
    #expect(FileManager.default.fileExists(atPath: stale.path))

    // 同一 dir を再利用したとき、残骸が掃除されて空になる。
    let dir2 = try CursorShellSanitizer.ensureEmptyZDotDir(inParent: parent)
    #expect(dir2 == dir)
    #expect(!FileManager.default.fileExists(atPath: stale.path))
}
