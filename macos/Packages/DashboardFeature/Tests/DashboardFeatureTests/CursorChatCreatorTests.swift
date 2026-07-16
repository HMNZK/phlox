import Foundation
import Testing
@testable import DashboardFeature

// CursorChatCreator は実プロセスを起動するため、即時終了する標準コマンドで検証する
// （PTYKit のテストが /bin/echo を spawn するのと同じ方針）。

@Test
func createChatID_trimsStdoutOfSuccessfulProcess() async throws {
    // /bin/echo create-chat は "create-chat\n" を出力する。
    let creator = CursorChatCreator(
        command: "/bin/echo",
        pathEnvironment: "/usr/bin:/bin"
    )

    let chatID = try await creator.createChatID()

    #expect(chatID == "create-chat")
}

@Test
func createChatID_nonZeroExit_returnsNil() async throws {
    let creator = CursorChatCreator(
        command: "/usr/bin/false",
        pathEnvironment: "/usr/bin:/bin"
    )

    let chatID = try await creator.createChatID()

    #expect(chatID == nil)
}

@Test
func createChatID_emptyOutput_returnsNil() async throws {
    let creator = CursorChatCreator(
        command: "/usr/bin/true",
        pathEnvironment: "/usr/bin:/bin"
    )

    let chatID = try await creator.createChatID()

    #expect(chatID == nil)
}

@Test
func createChatID_missingBinary_throws() async {
    let creator = CursorChatCreator(
        command: "/nonexistent/cursor-binary",
        pathEnvironment: "/usr/bin:/bin"
    )

    await #expect(throws: (any Error).self) {
        try await creator.createChatID()
    }
}

@Test
func createChatID_processExceedingTimeout_isTerminatedAndReturnsNil() async throws {
    // 引数を無視して長時間 sleep するスクリプトでタイムアウト経路を検証する。
    let scriptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cursor-chat-creator-test-\(UUID().uuidString).sh")
    try Data("#!/bin/sh\nsleep 30\n".utf8).write(to: scriptURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: scriptURL.path
    )
    defer { try? FileManager.default.removeItem(at: scriptURL) }

    let creator = CursorChatCreator(
        command: scriptURL.path,
        pathEnvironment: "/usr/bin:/bin",
        timeout: .milliseconds(200)
    )
    let started = ContinuousClock.now

    let chatID = try await creator.createChatID()

    #expect(chatID == nil)
    // terminate で打ち切られ、sleep 30 を待たずに返る。
    #expect(ContinuousClock.now - started < .seconds(5))
}
