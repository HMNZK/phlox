// task-51 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-51.md — 履歴一覧のタイトル材料を元履歴から取得する。
// 期待値は契約の独立リテラル。task-41 / task-49 の製品 API は呼ばない。

import Foundation
import SQLite3
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Suite("task-51: history title sources")
struct AcceptanceHistoryTitleSourcesTests {
    private static let claudeUserTimestamp = "2026-07-01T10:00:00.000Z"
    private static let claudeOlderMtime = Date(timeIntervalSince1970: 1_750_000_000)
    private static let claudeNewerMtime = Date(timeIntervalSince1970: 1_760_000_000)
    private static let reviewLogin = "/review\nログイン画面を修正"
    private static let reviewSettings = "/review\n設定画面を整理"
    private static let metaBody = "メタ本文です"
    private static let realRequest = "ログイン画面を修正"
    private static let pasteBody = "貼り付け内容\nfunc main() {}\n"
    private static let longUserText = String(repeating: "あ", count: 200)
    private static let continuation = "続行の依頼"
    private static let leadingUser = "  先頭空白と改行\nを保つ  "
    private static let secondUser = "二件目の依頼"
    private static let eventUser = "  event_msg の本文  "
    private static let responseUser = "  response_item の本文  "
    private static let dbFirstUser = "  DB の first_user_message  "
    private static let dbPreview = "  DB の preview  "
    private static let whitespaceOnlyUser = " \n\t "
    private static let matchingCWD = "/tmp/work"
    private static let otherCWD = "/tmp/other"
    private static let xmlCommand = "<command-name>/clear</command-name>"
    private static let earlyUser = "early"
    private static let lateUser = "too late"

    // MARK: - 新規公開契約

    @Test("新規引数なしの既存 initializer は titleUserMessages / titleSummary がともに nil。既存6フィールドは入力どおり")
    func legacyInitializerLeavesTitleMaterialsNil() throws {
        let url = URL(fileURLWithPath: "/tmp/task51-legacy.jsonl")
        let firstUserAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastModified = Date(timeIntervalSince1970: 1_700_000_100)
        let entry = ClaudeSessionHistoryEntry(
            sessionID: "11111111-1111-4111-8111-111111111111",
            preview: "既存 preview",
            firstUserAt: firstUserAt,
            lastModified: lastModified,
            gitBranch: "dev",
            fileURL: url
        )
        #expect(entry.sessionID == "11111111-1111-4111-8111-111111111111")
        #expect(entry.id == "11111111-1111-4111-8111-111111111111")
        #expect(entry.preview == "既存 preview")
        #expect(entry.firstUserAt == firstUserAt)
        #expect(entry.lastModified == lastModified)
        #expect(entry.gitBranch == "dev")
        #expect(entry.fileURL == url)
        #expect(entry.titleUserMessages == nil)
        #expect(entry.titleSummary == nil)
    }

    // MARK: - Claude JSONL

    @Test("Claude の文字列本文 /review 改行 ログイン画面を修正 を加工せず1件保持する")
    func claudeStringUserMessageKeepsReviewLiteral() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        let id = "aaaaaaaa-0000-4000-8000-000000000001"
        let file = try env.writeSession(
            id: id,
            lines: [
                try claudeUserJSONL(content: Self.reviewLogin, uuid: "u-review", gitBranch: "dev"),
            ],
            modifiedAt: Self.claudeNewerMtime
        )
        let before = try snapshotTree(env.root)
        let entries = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 10)
        try assertUnchanged(before, env.root)

        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.sessionID == id)
        #expect(entry.id == id)
        #expect(entry.fileURL == file)
        #expect(entry.gitBranch == "dev")
        #expect(abs(entry.lastModified.timeIntervalSince(Self.claudeNewerMtime)) < 1.0)
        #expect(entry.preview == "/review ログイン画面を修正")
        #expect(entry.firstUserAt == isoDate(Self.claudeUserTimestamp))
        #expect(entry.titleUserMessages == [Self.reviewLogin])
        #expect(entry.titleSummary == nil)
    }

    @Test("Claude の text block 配列 /review と 設定画面を整理 は1本文として改行結合する")
    func claudeTextBlocksJoinWithNewline() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        let id = "aaaaaaaa-0000-4000-8000-000000000002"
        try env.writeSession(
            id: id,
            lines: [
                try claudeUserJSONL(
                    content: [
                        ["type": "text", "text": "/review"],
                        ["type": "text", "text": "設定画面を整理"],
                    ],
                    uuid: "u-blocks"
                ),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.titleUserMessages == [Self.reviewSettings])
        #expect(entry.preview == "/review 設定画面を整理")
        #expect(entry.titleSummary == nil)
    }

    @Test("Claude の isMeta true 本文は材料から除外し、後続の実依頼を保持する。既存 preview は従来値")
    func claudeIsMetaTrueExcludedFromMaterialsKeepsLegacyPreview() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        let id = "aaaaaaaa-0000-4000-8000-000000000003"
        try env.writeSession(
            id: id,
            lines: [
                try claudeUserJSONL(content: Self.metaBody, uuid: "u-meta", isMeta: true),
                try claudeUserJSONL(content: Self.realRequest, uuid: "u-real"),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.preview == Self.metaBody)
        #expect(entry.titleUserMessages == [Self.realRequest])
        #expect(entry.titleSummary == nil)
    }

    @Test("Claude の isMeta 欠落は通常のユーザー本文として保持する")
    func claudeMissingIsMetaKept() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000004",
            lines: [try claudeUserJSONL(content: Self.realRequest, uuid: "u-missing")]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.titleUserMessages == [Self.realRequest])
        #expect(entry.preview == Self.realRequest)
    }

    @Test("Claude の isMeta false は通常のユーザー本文として保持する")
    func claudeIsMetaFalseKept() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000005",
            lines: [try claudeUserJSONL(content: Self.realRequest, uuid: "u-false", isMeta: false)]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.titleUserMessages == [Self.realRequest])
        #expect(entry.preview == Self.realRequest)
    }

    @Test("複数のユーザー本文は改行・前後空白・出現順を維持する")
    func claudeMultipleUsersKeepWhitespaceAndOrder() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000006",
            lines: [
                try claudeUserJSONL(content: Self.leadingUser, uuid: "u-1"),
                try claudeUserJSONL(content: Self.secondUser, uuid: "u-2"),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.titleUserMessages == [Self.leadingUser, Self.secondUser])
        #expect(entry.preview == "先頭空白と改行 を保つ")
    }

    @Test("120文字を超える本文は新規材料では切らず、既存 preview は120文字。後続本文も保持する")
    func claudeLongTextNotTruncatedInTitleMaterials() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000007",
            lines: [
                try claudeUserJSONL(content: Self.longUserText, uuid: "u-long"),
                try claudeUserJSONL(content: Self.continuation, uuid: "u-cont"),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.preview == String(Self.longUserText.prefix(120)))
        #expect(entry.preview.count == 120)
        #expect(entry.titleUserMessages == [Self.longUserText, Self.continuation])
        #expect(entry.titleUserMessages?.first?.count == 200)
    }

    @Test("assistant / system / tool result はユーザー材料に混入しない")
    func claudeNonUserRolesStayOutOfTitleMaterials() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000008",
            lines: [
                try jsonLine([
                    "type": "assistant",
                    "message": [
                        "role": "assistant",
                        "content": [["type": "text", "text": "assistant 本文"]],
                    ],
                    "uuid": "a-1",
                    "timestamp": Self.claudeUserTimestamp,
                ]),
                try jsonLine(["type": "system", "subtype": "init", "uuid": "s-1"]),
                try jsonLine([
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": [["type": "tool_result", "tool_use_id": "t1", "content": "tool output"]],
                    ],
                    "uuid": "tool-1",
                    "timestamp": Self.claudeUserTimestamp,
                ]),
                try claudeUserJSONL(content: Self.realRequest, uuid: "u-real"),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.titleUserMessages == [Self.realRequest])
        #expect(entry.preview == Self.realRequest)
    }

    @Test("assistant / system / tool result のみで、isMeta により既存 entry が成立する fixture では titleUserMessages は空配列")
    func claudeNonUserRolesWithMetaOnlyYieldEmptyTitleMaterials() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000017",
            lines: [
                try jsonLine([
                    "type": "assistant",
                    "message": [
                        "role": "assistant",
                        "content": [["type": "text", "text": "assistant 本文"]],
                    ],
                    "uuid": "a-only",
                    "timestamp": Self.claudeUserTimestamp,
                ]),
                try jsonLine(["type": "system", "subtype": "init", "uuid": "s-only"]),
                try jsonLine([
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": [["type": "tool_result", "tool_use_id": "t1", "content": "tool output"]],
                    ],
                    "uuid": "tool-only",
                    "timestamp": Self.claudeUserTimestamp,
                ]),
                try claudeUserJSONL(content: Self.metaBody, uuid: "u-meta-keep", isMeta: true),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.preview == Self.metaBody)
        #expect(entry.titleUserMessages == [])
        #expect(entry.titleSummary == nil)
    }

    @Test("XML 風の本文は取得器では除外せず、出現順のまま材料に残す。既存 preview は従来の firstUserLine")
    func claudeXMLStyleKeptInTitleMaterialsNotUsedForLegacyPreview() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000018",
            lines: [
                try claudeUserJSONL(content: Self.xmlCommand, uuid: "u-xml"),
                try claudeUserJSONL(content: Self.realRequest, uuid: "u-real"),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.preview == Self.realRequest)
        #expect(entry.titleUserMessages == [Self.xmlCommand, Self.realRequest])
        #expect(entry.titleSummary == nil)
    }

    @Test("isMeta のみで既存条件の entry が成立する fixture では titleUserMessages は空配列")
    func claudeMetaOnlyUsersYieldEmptyTitleMaterials() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000009",
            lines: [try claudeUserJSONL(content: Self.metaBody, uuid: "u-meta-only", isMeta: true)]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.preview == Self.metaBody)
        #expect(entry.titleUserMessages == [])
        #expect(entry.titleSummary == nil)
    }

    @Test("Claude の sidechain とメタデータだけのファイルは一覧から除外する")
    func claudeExcludesSidechainAndMetadataOnlyFiles() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000010",
            lines: [
                try jsonLine(["type": "mode", "mode": "default"]),
                try jsonLine(["type": "summary", "summary": "要約だけ"]),
            ]
        )
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000011",
            lines: [try claudeUserJSONL(content: "サブエージェントのプロンプト", uuid: "u-side", isSidechain: true)]
        )
        let keptID = "aaaaaaaa-0000-4000-8000-000000000012"
        try env.writeSession(
            id: keptID,
            lines: [try claudeUserJSONL(content: Self.realRequest, uuid: "u-ok")],
            modifiedAt: Self.claudeNewerMtime
        )
        let entries = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 10)
        #expect(entries.map(\.sessionID) == [keptID])
        #expect(entries[0].titleUserMessages == [Self.realRequest])
    }

    @Test("Claude の件数は mtime 降順と limit。200行を超えたユーザー行は採用しない")
    func claudeOrderLimitAndLineBound() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        let olderID = "aaaaaaaa-0000-4000-8000-000000000013"
        let newerID = "aaaaaaaa-0000-4000-8000-000000000014"
        try env.writeSession(
            id: olderID,
            lines: [try claudeUserJSONL(content: "古い", uuid: "u-old")],
            modifiedAt: Self.claudeOlderMtime
        )
        try env.writeSession(
            id: newerID,
            lines: [try claudeUserJSONL(content: "新しい", uuid: "u-new")],
            modifiedAt: Self.claudeNewerMtime
        )
        var lateLines = (1...200).map { #"{"type":"mode","mode":"line-\#($0)"}"# }
        lateLines.append(try claudeUserJSONL(content: "too late", uuid: "late"))
        try env.writeSession(id: "aaaaaaaa-0000-4000-8000-000000000015", lines: lateLines)

        let limited = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1)
        #expect(limited.map(\.sessionID) == [newerID])
        let all = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 10)
        #expect(all.map(\.sessionID) == [newerID, olderID])
        #expect(all.map(\.preview) == ["新しい", "古い"])
        #expect(all.map(\.titleUserMessages) == [["新しい"], ["古い"]])
        #expect(ClaudeSessionHistoryDiscovery.maxLinesPerFile == 200)
        #expect(ClaudeSessionHistoryDiscovery.maxBytesPerFile == 256 * 1024)
    }

    @Test("同一ファイルで 200 行を超えた後続ユーザー本文は材料に入れない。先行本文は加工せず保持する")
    func claudeSameFileLineBoundDoesNotCollectLateUser() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        var lines = [try claudeUserJSONL(content: Self.earlyUser, uuid: "u-early")]
        lines += (1...199).map { #"{"type":"mode","mode":"pad-\#($0)"}"# }
        lines.append(try claudeUserJSONL(content: Self.lateUser, uuid: "u-late"))
        try env.writeSession(id: "aaaaaaaa-0000-4000-8000-000000000019", lines: lines)
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.preview == Self.earlyUser)
        #expect(entry.titleUserMessages == [Self.earlyUser])
    }

    @Test("256KiB を超えた後続ユーザー本文は材料に入れない。先行本文は切らない")
    func claudeByteBoundDoesNotCollectLateUser() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        let pad = String(repeating: "x", count: 200_000)
        try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000020",
            lines: [
                try claudeUserJSONL(content: Self.earlyUser, uuid: "u-early-bytes"),
                #"{"type":"mode","mode":"\#(pad)"}"#,
                #"{"type":"mode","mode":"\#(pad)"}"#,
                try claudeUserJSONL(content: Self.lateUser, uuid: "u-late-bytes"),
            ]
        )
        let entry = try #require(env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first)
        #expect(entry.preview == Self.earlyUser)
        #expect(entry.titleUserMessages == [Self.earlyUser])
        #expect(entry.titleUserMessages?.first == Self.earlyUser)
    }

    @Test("Claude loader は /review・メタ本文・貼り付け内容を従来どおり返し、fixture を変えない")
    func claudeLoaderKeepsLegacyRestoreAndLeavesBytesUnchanged() throws {
        let env = try ClaudeHarness()
        defer { env.tearDown() }
        let file = try env.writeSession(
            id: "aaaaaaaa-0000-4000-8000-000000000016",
            lines: [
                try claudeUserJSONL(content: Self.reviewLogin, uuid: "id-review"),
                try claudeUserJSONL(content: Self.metaBody, uuid: "id-meta", isMeta: true),
                try claudeUserJSONL(content: Self.pasteBody, uuid: "id-paste"),
                try jsonLine([
                    "type": "assistant",
                    "message": [
                        "id": "msg-1",
                        "role": "assistant",
                        "content": [["type": "text", "text": "a1"]],
                    ],
                    "uuid": "id-a1",
                    "timestamp": "2026-07-01T10:00:04.000Z",
                ]),
            ]
        )
        let before = try snapshotTree(env.root)
        let items = ClaudeSessionTranscriptLoader().load(fileURL: file, maxItems: 10)
        try assertUnchanged(before, env.root)
        try #require(items.count == 4)
        if case .userMessage(_, let text, _, _) = items[0] {
            #expect(text == Self.reviewLogin)
        } else {
            Issue.record("items[0] should be userMessage: \(items[0])")
        }
        if case .userMessage(_, let text, _, _) = items[1] {
            #expect(text == Self.metaBody)
        } else {
            Issue.record("items[1] should be userMessage: \(items[1])")
        }
        if case .userMessage(_, let text, _, _) = items[2] {
            #expect(text == Self.pasteBody)
        } else {
            Issue.record("items[2] should be userMessage: \(items[2])")
        }
        if case .agentMessage(_, let text, _) = items[3] {
            #expect(text == "a1")
        } else {
            Issue.record("items[3] should be agentMessage: \(items[3])")
        }
        _ = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1)
        try assertUnchanged(before, env.root)
    }

    // MARK: - Codex rollout

    @Test("Codex rollout の response_item ユーザー本文を加工せず保持する")
    func codexRolloutResponseItemKeepsRawUserText() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let id = "11111111-1111-4111-8111-111111111111"
        let file = try env.writeRollout(
            id: id,
            cwd: Self.matchingCWD,
            lines: [
                try codexMeta(id: id, cwd: Self.matchingCWD),
                try codexResponseItem(role: "user", text: Self.responseUser, messageID: "u1"),
            ]
        )
        let before = try snapshotTree(env.root)
        let entries = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 10)
        try assertUnchanged(before, env.root)
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.sessionID == id)
        #expect(entry.id == id)
        #expect(entry.fileURL == file)
        #expect(entry.gitBranch == nil)
        #expect(entry.preview == "response_item の本文")
        #expect(entry.titleUserMessages == [Self.responseUser])
        #expect(entry.titleSummary == nil)
        #expect(entry.firstUserAt == isoDate("2026-08-24T10:01:00.000Z"))
    }

    @Test("Codex rollout の event_msg ユーザー本文を加工せず保持する")
    func codexRolloutEventMsgKeepsRawUserText() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let id = "22222222-2222-4222-8222-222222222222"
        try env.writeRollout(
            id: id,
            cwd: Self.matchingCWD,
            lines: [
                try codexMeta(id: id, cwd: Self.matchingCWD),
                try codexEventMsg(payloadType: "user_message", message: Self.eventUser),
            ]
        )
        let entry = try #require(
            env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first
        )
        #expect(entry.titleUserMessages == [Self.eventUser])
        #expect(entry.preview == "event_msg の本文")
        #expect(entry.titleSummary == nil)
    }

    @Test("Codex rollout で assistant が先、user が後なら材料は user のみ。既存 preview 規則は維持する")
    func codexAssistantFirstUserLaterMaterialsAreUserOnly() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let id = "33333333-3333-4333-8333-333333333333"
        try env.writeRollout(
            id: id,
            cwd: Self.matchingCWD,
            lines: [
                try codexMeta(id: id, cwd: Self.matchingCWD),
                try codexResponseItem(role: "assistant", text: "先の回答", messageID: "a1", contentType: "output_text"),
                try jsonLine([
                    "type": "event_msg",
                    "timestamp": "2026-08-24T10:02:00.000Z",
                    "payload": ["type": "agent_message", "message": "system 相当の出力"],
                ]),
                try codexResponseItem(role: "user", text: Self.responseUser, messageID: "u1"),
            ]
        )
        let entry = try #require(
            env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first
        )
        #expect(entry.titleUserMessages == [Self.responseUser])
        #expect(entry.preview == "response_item の本文")
        #expect(entry.titleSummary == nil)
    }

    @Test("Codex は cwd 不一致を除外し、件数は mtime 新しい順と limit")
    func codexCWDFilterOrderAndLimit() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let olderID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let newerID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let otherID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        try env.writeRollout(
            id: olderID,
            cwd: Self.matchingCWD,
            lines: [
                try codexMeta(id: olderID, cwd: Self.matchingCWD),
                try codexResponseItem(role: "user", text: "older", messageID: "u-old"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_010)
        )
        try env.writeRollout(
            id: newerID,
            cwd: Self.matchingCWD,
            lines: [
                try codexMeta(id: newerID, cwd: Self.matchingCWD),
                try codexResponseItem(role: "user", text: "newer", messageID: "u-new"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_020)
        )
        try env.writeRollout(
            id: otherID,
            cwd: Self.otherCWD,
            lines: [
                try codexMeta(id: otherID, cwd: Self.otherCWD),
                try codexResponseItem(role: "user", text: "excluded", messageID: "u-other"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_030)
        )
        let limited = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1)
        #expect(limited.map(\.sessionID) == [newerID])
        #expect(limited.first?.titleUserMessages == ["newer"])
        let all = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 10)
        #expect(all.map(\.sessionID) == [newerID, olderID])
        #expect(all.map(\.titleUserMessages) == [["newer"], ["older"]])
        #expect(CodexSessionHistoryDiscovery.maxSessionMetaBytes == 16 * 1024)
        #expect(CodexSessionHistoryDiscovery.maxBytesPerFile == 512 * 1024)
    }

    @Test("Codex rollout の行数打ち切り後のユーザー本文は材料に入れない")
    func codexScanLineCutoffDoesNotCollectLateUser() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let id = "55555555-5555-4555-8555-555555555555"
        var lines = [
            try codexMeta(id: id, cwd: Self.matchingCWD),
            try codexResponseItem(role: "user", text: Self.earlyUser, messageID: "u-early"),
        ]
        lines += (0..<200).map { #"{"type":"event_msg","timestamp":"2026-08-24T10:01:00.000Z","payload":{"type":"agent_message","message":"pad-\#($0)"}}"# }
        lines.append(try codexResponseItem(role: "user", text: Self.lateUser, messageID: "u-late"))
        try env.writeRollout(id: id, cwd: Self.matchingCWD, lines: lines)
        let entry = try #require(
            env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1).first
        )
        #expect(entry.preview == Self.earlyUser)
        #expect(entry.titleUserMessages == [Self.earlyUser])
        #expect(entry.titleSummary == nil)
    }

    @Test("Codex loader は /review と貼り付け内容を従来どおり返し、fixture を変えない")
    func codexLoaderKeepsLegacyRestoreAndLeavesBytesUnchanged() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let id = "44444444-4444-4444-8444-444444444444"
        let file = try env.writeRollout(
            id: id,
            cwd: Self.matchingCWD,
            lines: [
                try codexMeta(id: id, cwd: Self.matchingCWD),
                try codexResponseItem(role: "user", text: Self.reviewLogin, messageID: "u-review"),
                try jsonLine([
                    "type": "event_msg",
                    "timestamp": "2026-08-24T10:02:00.000Z",
                    "payload": ["type": "user_message", "message": Self.pasteBody],
                ]),
                try codexResponseItem(
                    role: "assistant",
                    text: "回答です",
                    messageID: "a1",
                    contentType: "output_text"
                ),
            ]
        )
        let before = try snapshotTree(env.root)
        let items = CodexSessionHistoryDiscovery.loadTranscript(fileURL: file, maxItems: 10)
        try assertUnchanged(before, env.root)
        #expect(items.map(\.plainText) == [
            "User: \(Self.reviewLogin)",
            "User: \(Self.pasteBody)",
            "Agent: 回答です",
        ])
        _ = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 1)
        try assertUnchanged(before, env.root)
    }

    // MARK: - Codex DB

    @Test("DB の first_user_message と preview が異なるとき、前者はユーザー材料、後者は補助材料")
    func databaseKeepsFirstUserAndPreviewSeparate() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let db = try env.createStateDatabase()
        try insertThread(
            at: db,
            id: "newer",
            rolloutPath: "/tmp/newer.jsonl",
            cwd: Self.matchingCWD,
            preview: Self.dbPreview,
            firstUserMessage: .text(Self.dbFirstUser),
            updatedAtMilliseconds: 2_000
        )
        try env.writeDecoyRollout()
        let before = try snapshotTree(env.root)
        let counter = ScanCounter()
        let entries = env.discovery.entries(
            forWorkingDirectory: Self.matchingCWD,
            limit: 2,
            onScan: { _ in counter.value += 1 }
        )
        try assertUnchanged(before, env.root)
        let entry = try #require(entries.first)
        #expect(entries.map(\.sessionID) == ["newer"])
        #expect(entry.fileURL.path == "/tmp/newer.jsonl")
        #expect(entry.lastModified == Date(timeIntervalSince1970: 2))
        #expect(entry.gitBranch == nil)
        #expect(entry.preview == "DB の preview")
        #expect(entry.titleUserMessages == [Self.dbFirstUser])
        #expect(entry.titleSummary == Self.dbPreview)
        #expect(counter.value == 0)
    }

    @Test("DB のユーザー本文が NULL で preview が非空なら材料は空配列。補助材料を保持し rollout 走査は0回")
    func databaseNullUserYieldsEmptyMaterialsNoRolloutScan() throws {
        try expectEmptyDatabaseUser(firstUser: .null, preview: Self.dbPreview)
    }

    @Test("DB のユーザー本文が空文字で preview が非空なら材料は空配列。補助材料を保持し rollout 走査は0回")
    func databaseEmptyUserYieldsEmptyMaterialsNoRolloutScan() throws {
        try expectEmptyDatabaseUser(firstUser: .text(""), preview: Self.dbPreview)
    }

    @Test("DB のユーザー本文が空白のみで preview が非空なら材料は空配列。補助材料を保持し rollout 走査は0回")
    func databaseWhitespaceUserYieldsEmptyMaterialsNoRolloutScan() throws {
        try expectEmptyDatabaseUser(firstUser: .text(Self.whitespaceOnlyUser), preview: Self.dbPreview)
    }

    @Test("DB の preview が NULL なら titleSummary は nil。空文字・空白のみは加工せず保持する")
    func databasePreviewNullEmptyAndWhitespaceKeptRaw() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let db = try env.createStateDatabase()
        try insertThread(
            at: db,
            id: "null-preview",
            rolloutPath: "/tmp/null-preview.jsonl",
            cwd: Self.matchingCWD,
            preview: nil,
            firstUserMessage: .text("実依頼"),
            updatedAtMilliseconds: 3_000
        )
        try insertThread(
            at: db,
            id: "empty-preview",
            rolloutPath: "/tmp/empty-preview.jsonl",
            cwd: Self.matchingCWD,
            preview: "",
            firstUserMessage: .text("実依頼2"),
            updatedAtMilliseconds: 2_000
        )
        try insertThread(
            at: db,
            id: "ws-preview",
            rolloutPath: "/tmp/ws-preview.jsonl",
            cwd: Self.matchingCWD,
            preview: Self.whitespaceOnlyUser,
            firstUserMessage: .text("実依頼3"),
            updatedAtMilliseconds: 1_000
        )
        let entries = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 10)
        #expect(entries.map(\.sessionID) == ["null-preview", "empty-preview", "ws-preview"])
        #expect(entries[0].titleUserMessages == ["実依頼"])
        #expect(entries[0].titleSummary == nil)
        #expect(entries[1].titleUserMessages == ["実依頼2"])
        #expect(entries[1].titleSummary == "")
        #expect(entries[2].titleUserMessages == ["実依頼3"])
        #expect(entries[2].titleSummary == Self.whitespaceOnlyUser)
    }

    @Test("DB 利用可能で結果0件なら rollout 走査は0回")
    func databaseAvailableZeroRowsDoesNotScanRollout() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        _ = try env.createStateDatabase()
        try env.writeDecoyRollout()
        let counter = ScanCounter()
        let entries = env.discovery.entries(
            forWorkingDirectory: "/tmp/missing",
            limit: 2,
            onScan: { _ in counter.value += 1 }
        )
        #expect(entries.isEmpty)
        #expect(counter.value == 0)
    }

    @Test("DB 利用不可なら既存の rollout フォールバックを維持する")
    func databaseUnavailableFallsBackToRollout() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        try env.createOldStateDatabase()
        let id = "fallback"
        try env.writeRollout(
            id: id,
            cwd: Self.matchingCWD,
            lines: [
                try codexMeta(id: id, cwd: Self.matchingCWD),
                try codexResponseItem(role: "user", text: "JSONL fallback", messageID: "u1"),
            ]
        )
        let counter = ScanCounter()
        let entries = env.discovery.entries(
            forWorkingDirectory: Self.matchingCWD,
            limit: 1,
            onScan: { _ in counter.value += 1 }
        )
        #expect(entries.map(\.sessionID) == [id])
        #expect(entries.first?.preview == "JSONL fallback")
        #expect(entries.first?.titleUserMessages == ["JSONL fallback"])
        #expect(entries.first?.titleSummary == nil)
        #expect(counter.value == 1)
    }

    @Test("DB は archived と cwd 不一致を除外し、採用行の既存6フィールドは固定期待値")
    func databaseRespectsArchivedAndCWDAndKeepsLegacyFields() throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let db = try env.createStateDatabase()
        try insertThread(
            at: db,
            id: "kept",
            rolloutPath: "/tmp/kept.jsonl",
            cwd: Self.matchingCWD,
            preview: "  kept preview  ",
            firstUserMessage: .text("  kept user  "),
            updatedAtMilliseconds: 4_000
        )
        try insertThread(
            at: db,
            id: "other-cwd",
            rolloutPath: "/tmp/other.jsonl",
            cwd: Self.otherCWD,
            preview: "other",
            firstUserMessage: .text("other user"),
            updatedAtMilliseconds: 5_000
        )
        try insertThread(
            at: db,
            id: "archived",
            rolloutPath: "/tmp/archived.jsonl",
            cwd: Self.matchingCWD,
            preview: "archived",
            firstUserMessage: .text("archived user"),
            updatedAtMilliseconds: 6_000,
            archived: 1
        )
        let entries = env.discovery.entries(forWorkingDirectory: Self.matchingCWD, limit: 10)
        let entry = try #require(entries.first)
        #expect(entries.map(\.sessionID) == ["kept"])
        #expect(entry.id == "kept")
        #expect(entry.fileURL.path == "/tmp/kept.jsonl")
        #expect(entry.preview == "kept preview")
        #expect(entry.firstUserAt == nil)
        #expect(entry.lastModified == Date(timeIntervalSince1970: 4))
        #expect(entry.gitBranch == nil)
        #expect(entry.titleUserMessages == ["  kept user  "])
        #expect(entry.titleSummary == "  kept preview  ")
    }

    private func expectEmptyDatabaseUser(firstUser: SQLText, preview: String) throws {
        let env = try CodexHarness()
        defer { env.tearDown() }
        let db = try env.createStateDatabase()
        try insertThread(
            at: db,
            id: "empty-user",
            rolloutPath: "/tmp/empty-user.jsonl",
            cwd: Self.matchingCWD,
            preview: preview,
            firstUserMessage: firstUser,
            updatedAtMilliseconds: 2_000
        )
        try env.writeDecoyRollout()
        let before = try snapshotTree(env.root)
        let counter = ScanCounter()
        let entries = env.discovery.entries(
            forWorkingDirectory: Self.matchingCWD,
            limit: 2,
            onScan: { _ in counter.value += 1 }
        )
        try assertUnchanged(before, env.root)
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.titleUserMessages == [])
        #expect(entry.titleSummary == preview)
        #expect(entry.preview == "DB の preview")
        #expect(counter.value == 0)
    }
}

// MARK: - Fixtures

private struct FileStamp: Equatable {
    var bytes: Data
    var modificationTime: TimeInterval
}

private final class ScanCounter: @unchecked Sendable {
    var value = 0
}

private enum SQLText {
    case null
    case text(String)
}

private struct ClaudeHarness {
    let root: URL
    let discovery: ClaudeSessionHistoryDiscovery

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("task51-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = url
        discovery = ClaudeSessionHistoryDiscovery(projectsRoot: url)
        let dir = url.appendingPathComponent("-tmp-work", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var projectDir: URL {
        root.appendingPathComponent("-tmp-work", isDirectory: true)
    }

    @discardableResult
    func writeSession(id: String, lines: [String], modifiedAt: Date? = nil) throws -> URL {
        let file = projectDir.appendingPathComponent("\(id).jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        if let modifiedAt {
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
        }
        return file
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct CodexHarness {
    let root: URL
    let discovery: CodexSessionHistoryDiscovery

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("task51-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = url
        discovery = CodexSessionHistoryDiscovery(codexHome: url)
    }

    func dayDir() throws -> URL {
        let day = root.appendingPathComponent("sessions/2026/08/24", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        return day
    }

    @discardableResult
    func writeRollout(id: String, cwd: String, lines: [String], modifiedAt: Date? = nil) throws -> URL {
        _ = cwd
        let file = try dayDir().appendingPathComponent("rollout-\(id).jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        if let modifiedAt {
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
        }
        return file
    }

    func writeDecoyRollout() throws {
        try writeRollout(
            id: "decoy",
            cwd: "/tmp/work",
            lines: [
                try codexMeta(id: "decoy", cwd: "/tmp/work"),
                try codexResponseItem(role: "user", text: "should not be scanned", messageID: "u-decoy"),
            ]
        )
    }

    @discardableResult
    func createStateDatabase() throws -> URL {
        let url = root.appendingPathComponent("state_5.sqlite")
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(
            url.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        guard opened == SQLITE_OK, let database else {
            throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 1)
        }
        defer { sqlite3_close_v2(database) }
        let schema = """
        CREATE TABLE threads (
          id TEXT PRIMARY KEY,
          rollout_path TEXT NOT NULL,
          cwd TEXT NOT NULL,
          preview TEXT,
          first_user_message TEXT,
          updated_at_ms INTEGER,
          archived INTEGER NOT NULL DEFAULT 0
        );
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 2)
        }
        return url
    }

    func createOldStateDatabase() throws {
        let url = root.appendingPathComponent("state_5.sqlite")
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(
            url.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        guard opened == SQLITE_OK, let database else {
            throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 3)
        }
        defer { sqlite3_close_v2(database) }
        guard sqlite3_exec(database, "CREATE TABLE threads (id TEXT PRIMARY KEY);", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 4)
        }
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func jsonLine(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    guard let line = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 5)
    }
    return line
}

private func claudeUserJSONL(
    content: Any,
    uuid: String,
    timestamp: String = "2026-07-01T10:00:00.000Z",
    gitBranch: String? = nil,
    isMeta: Bool? = nil,
    isSidechain: Bool? = nil
) throws -> String {
    var object: [String: Any] = [
        "type": "user",
        "message": ["role": "user", "content": content],
        "uuid": uuid,
        "timestamp": timestamp,
        "cwd": "/tmp/work",
        "sessionId": uuid,
    ]
    if let gitBranch {
        object["gitBranch"] = gitBranch
    }
    if let isMeta {
        object["isMeta"] = isMeta
    }
    if let isSidechain {
        object["isSidechain"] = isSidechain
    }
    return try jsonLine(object)
}

private func codexMeta(id: String, cwd: String) throws -> String {
    try jsonLine([
        "type": "session_meta",
        "payload": [
            "id": id,
            "cwd": cwd,
            "timestamp": "2026-08-24T10:00:00.000Z",
        ],
    ])
}

private func codexResponseItem(
    role: String,
    text: String,
    messageID: String,
    contentType: String? = nil,
    timestamp: String = "2026-08-24T10:01:00.000Z"
) throws -> String {
    let type = contentType ?? (role == "user" ? "input_text" : "output_text")
    return try jsonLine([
        "type": "response_item",
        "timestamp": timestamp,
        "payload": [
            "type": "message",
            "id": messageID,
            "role": role,
            "content": [["type": type, "text": text]],
        ],
    ])
}

private func codexEventMsg(payloadType: String, message: String) throws -> String {
    try jsonLine([
        "type": "event_msg",
        "timestamp": "2026-08-24T10:01:00.000Z",
        "payload": ["type": payloadType, "message": message],
    ])
}

private func insertThread(
    at url: URL,
    id: String,
    rolloutPath: String,
    cwd: String,
    preview: String?,
    firstUserMessage: SQLText,
    updatedAtMilliseconds: Int64,
    archived: Int32 = 0
) throws {
    var database: OpaquePointer?
    let opened = sqlite3_open_v2(url.path(percentEncoded: false), &database, SQLITE_OPEN_READWRITE, nil)
    guard opened == SQLITE_OK, let database else {
        throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 6)
    }
    defer { sqlite3_close_v2(database) }
    var statement: OpaquePointer?
    let sql = "INSERT INTO threads(id, rollout_path, cwd, preview, first_user_message, updated_at_ms, archived) VALUES(?, ?, ?, ?, ?, ?, ?);"
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 7)
    }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let bindText: (Int32, String) throws -> Void = { index, value in
        let result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
        guard result == SQLITE_OK else {
            throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 8)
        }
    }
    try bindText(1, id)
    try bindText(2, rolloutPath)
    try bindText(3, cwd)
    if let preview {
        try bindText(4, preview)
    } else {
        guard sqlite3_bind_null(statement, 4) == SQLITE_OK else {
            throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 9)
        }
    }
    switch firstUserMessage {
    case .null:
        guard sqlite3_bind_null(statement, 5) == SQLITE_OK else {
            throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 10)
        }
    case .text(let value):
        try bindText(5, value)
    }
    guard sqlite3_bind_int64(statement, 6, updatedAtMilliseconds) == SQLITE_OK,
          sqlite3_bind_int(statement, 7, archived) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_DONE else {
        throw NSError(domain: "AcceptanceHistoryTitleSourcesTests", code: 11)
    }
}

private func snapshotTree(_ root: URL) throws -> [String: FileStamp] {
    var stamps: [String: FileStamp] = [:]
    let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
    )
    while let item = enumerator?.nextObject() {
        guard let url = item as? URL else { continue }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
        guard values.isRegularFile == true else { continue }
        let relative = String(url.path.dropFirst(root.path.count).drop(while: { $0 == "/" }))
        stamps[relative] = FileStamp(
            bytes: try Data(contentsOf: url),
            modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }
    return stamps
}

private func assertUnchanged(_ before: [String: FileStamp], _ root: URL) throws {
    let after = try snapshotTree(root)
    #expect(Set(after.keys) == Set(before.keys))
    for (path, stamp) in before {
        let now = after[path]
        #expect(now?.bytes == stamp.bytes, Comment(rawValue: "bytes \(path)"))
        #expect(now?.modificationTime == stamp.modificationTime, Comment(rawValue: "mtime \(path)"))
    }
}

private func isoDate(_ string: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: string) {
        return date
    }
    let withoutFraction = ISO8601DateFormatter()
    withoutFraction.formatOptions = [.withInternetDateTime]
    return withoutFraction.date(from: string)
}
