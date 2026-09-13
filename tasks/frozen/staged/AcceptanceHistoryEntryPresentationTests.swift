// 実パス: macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceHistoryEntryPresentationTests.swift
// task-49（UX-11b HistoryEntryPresentation）受け入れテスト（PM 著・不変）。
// HistoryEntryPresentation および task-51 の titleUserMessages / titleSummary 未実装のコンパイル RED が正常。
// 期待値は tasks/task-49.md の独立リテラル。製品モデルや SessionTitleDeriver.derive の戻り値から生成しない。

import Foundation
import Testing
@testable import SessionFeature

private enum FrozenTitle {
    static let none = "作業名なし"
    static let login = "ログイン画面を修正"
    static let settings = "設定画面を整理"
    static let historyFix = "履歴表示を修正"
    static let oldPreview = "採用してはいけない旧表示"
    static let chars32 = "abcdefghijklmnopqrstuvwx12345678"
    static let chars33 = "abcdefghijklmnopqrstuvwx123456789"
    static let chars33Title = "abcdefghijklmnopqrstuvwx1234567…"
    static let family32 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦b"
    static let family33 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦bc"
    static let family33Title = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa👨‍👩‍👧‍👦…"
    static let combining32 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}b"
    static let combining33 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}bc"
    static let combining33Title = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaae\u{301}…"
    static let unknownProject = "プロジェクト不明"
    static let projectA = "project-a"
    static let lowercaseBaseDirectory = "base directory for this skill:"
}

private let frozenFirstUserAt = Date(timeIntervalSince1970: 1_700_000_000)
private let frozenLastModified = Date(timeIntervalSince1970: 1_700_000_100)
private let frozenFileURL = URL(fileURLWithPath: "/tmp/session.jsonl")

private func makeEntry(
    sessionID: String = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    preview: String = "preview",
    firstUserAt: Date? = frozenFirstUserAt,
    lastModified: Date = frozenLastModified,
    gitBranch: String? = "dev",
    fileURL: URL = frozenFileURL,
    titleUserMessages: [String]? = nil,
    titleSummary: String? = nil
) -> ClaudeSessionHistoryEntry {
    ClaudeSessionHistoryEntry(
        sessionID: sessionID,
        preview: preview,
        firstUserAt: firstUserAt,
        lastModified: lastModified,
        gitBranch: gitBranch,
        fileURL: fileURL,
        titleUserMessages: titleUserMessages,
        titleSummary: titleSummary
    )
}

private func present(
    _ entry: ClaudeSessionHistoryEntry,
    workingDirectory: String? = "/tmp/work"
) -> HistoryEntryPresentation {
    HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory)
}

@Suite("task-49: HistoryEntryPresentation 表示モデル")
struct AcceptanceHistoryEntryPresentationTests {
    @Test("ユーザー材料 ログイン画面を修正 はそのまま title／fullTitle")
    func userMaterialLoginIsTitle() {
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.login])
        )
        #expect(presentation.title == FrozenTitle.login)
        #expect(presentation.fullTitle == FrozenTitle.login)
    }

    @Test("/review 改行 ログイン画面を修正 は依頼行")
    func slashThenLoginInOneMessage() {
        let presentation = present(
            makeEntry(titleUserMessages: ["/review\nログイン画面を修正"])
        )
        #expect(presentation.title == FrozenTitle.login)
        #expect(presentation.fullTitle == FrozenTitle.login)
    }

    @Test("/review の次のユーザー材料 設定画面を整理 を採る")
    func slashMessageThenSettings() {
        let presentation = present(
            makeEntry(titleUserMessages: ["/review", FrozenTitle.settings])
        )
        #expect(presentation.title == FrozenTitle.settings)
        #expect(presentation.fullTitle == FrozenTitle.settings)
    }

    @Test("Base directory 接頭辞の本文は丸ごと除外し次の依頼を採る")
    func baseDirectoryPrefixSkipsWholeBody() {
        let presentation = present(
            makeEntry(
                titleUserMessages: [
                    "Base directory for this skill: /tmp/skill\n説明文",
                    FrozenTitle.historyFix,
                ]
            )
        )
        #expect(presentation.title == FrozenTitle.historyFix)
        #expect(presentation.fullTitle == FrozenTitle.historyFix)
    }

    @Test("< 始まりの XML 風本文は丸ごと除外し次の依頼を採る")
    func anglePrefixSkipsWholeBody() {
        let presentation = present(
            makeEntry(
                titleUserMessages: [
                    "<command-name>/review</command-name>",
                    FrozenTitle.historyFix,
                ]
            )
        )
        #expect(presentation.title == FrozenTitle.historyFix)
        #expect(presentation.fullTitle == FrozenTitle.historyFix)
    }

    @Test("閉じたコードフェンスに続く依頼行")
    func closedFenceThenRequestLine() {
        let material = #"""
        ```swift
        print(1)
        ```
        履歴表示を修正
        """#
        let presentation = present(
            makeEntry(titleUserMessages: [material])
        )
        #expect(presentation.title == FrozenTitle.historyFix)
        #expect(presentation.fullTitle == FrozenTitle.historyFix)
    }

    @Test("適格なユーザー材料は異なる補助材料より優先")
    func eligibleUserBeatsDifferentSummary() {
        let presentation = present(
            makeEntry(
                titleUserMessages: [FrozenTitle.login],
                titleSummary: FrozenTitle.historyFix
            )
        )
        #expect(presentation.title == FrozenTitle.login)
        #expect(presentation.fullTitle == FrozenTitle.login)
        #expect(presentation.title != FrozenTitle.historyFix)
    }

    @Test("ユーザー材料が不適格なら補助材料 履歴表示を修正")
    func ineligibleUserFallsBackToSummary() {
        let presentation = present(
            makeEntry(
                titleUserMessages: ["/review"],
                titleSummary: FrozenTitle.historyFix
            )
        )
        #expect(presentation.title == FrozenTitle.historyFix)
        #expect(presentation.fullTitle == FrozenTitle.historyFix)
    }

    @Test("ユーザー材料・補助材料が定型文だけなら 作業名なし")
    func boilerplateOnlyIsUntitled() {
        let presentation = present(
            makeEntry(
                titleUserMessages: ["<command-name>/review</command-name>"],
                titleSummary: "Base directory for this skill: /tmp"
            )
        )
        #expect(presentation.title == FrozenTitle.none)
        #expect(presentation.fullTitle == FrozenTitle.none)
    }

    @Test("空配列は preview へ戻らず 作業名なし")
    func emptyUserMessagesDoNotFallBackToPreview() {
        let presentation = present(
            makeEntry(
                preview: FrozenTitle.oldPreview,
                titleUserMessages: [],
                titleSummary: nil
            )
        )
        #expect(presentation.title == FrozenTitle.none)
        #expect(presentation.fullTitle == FrozenTitle.none)
        #expect(presentation.title != FrozenTitle.oldPreview)
    }

    @Test("titleUserMessages が nil なら preview 履歴表示を修正")
    func nilUserMessagesUsePreview() {
        let entry = ClaudeSessionHistoryEntry(
            sessionID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            preview: FrozenTitle.historyFix,
            firstUserAt: frozenFirstUserAt,
            lastModified: frozenLastModified,
            gitBranch: "dev",
            fileURL: frozenFileURL
        )
        let presentation = present(entry)
        #expect(entry.titleUserMessages == nil)
        #expect(entry.titleSummary == nil)
        #expect(presentation.title == FrozenTitle.historyFix)
        #expect(presentation.fullTitle == FrozenTitle.historyFix)
    }

    @Test("32 Character は title／fullTitle とも入力そのもの")
    func thirtyTwoCharactersStayUntruncated() {
        #expect(FrozenTitle.chars32.count == 32)
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.chars32])
        )
        #expect(presentation.title == FrozenTitle.chars32)
        #expect(presentation.fullTitle == FrozenTitle.chars32)
    }

    @Test("33 Character は title 省略・fullTitle は入力33文字")
    func thirtyThreeCharactersTruncateTitleOnly() {
        #expect(FrozenTitle.chars33.count == 33)
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.chars33])
        )
        #expect(presentation.title == FrozenTitle.chars33Title)
        #expect(presentation.fullTitle == FrozenTitle.chars33)
    }

    @Test("cwd /tmp/project-a/ は名前 project-a・projectPath は入力どおり")
    func trailingSlashIsStrippedOnlyForName() {
        let input = "/tmp/project-a/"
        let presentation = present(makeEntry(titleUserMessages: [FrozenTitle.login]), workingDirectory: input)
        #expect(presentation.projectName == FrozenTitle.projectA)
        #expect(presentation.projectPath == input)
    }

    @Test("cwd / は projectName／projectPath ともに /")
    func rootPathKeepsSlashAsName() {
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.login]),
            workingDirectory: "/"
        )
        #expect(presentation.projectName == "/")
        #expect(presentation.projectPath == "/")
    }

    @Test("cwd が nil・空・空白のみなら プロジェクト不明 で projectPath は nil")
    func missingWorkingDirectoryIsUnknownProject() {
        let entry = makeEntry(titleUserMessages: [FrozenTitle.login])
        for cwd in [String?.none, Optional.some(""), Optional.some(" "), Optional.some("\t"), Optional.some("　")] {
            let presentation = present(entry, workingDirectory: cwd)
            #expect(presentation.projectName == FrozenTitle.unknownProject)
            #expect(presentation.projectPath == nil)
        }
    }

    @Test("lastUsedAt は firstUserAt と異なる lastModified")
    func lastUsedAtIsLastModifiedNotFirstUserAt() {
        #expect(frozenFirstUserAt != frozenLastModified)
        let presentation = present(
            makeEntry(
                firstUserAt: frozenFirstUserAt,
                lastModified: frozenLastModified,
                titleUserMessages: [FrozenTitle.login]
            )
        )
        #expect(presentation.lastUsedAt == frozenLastModified)
        #expect(presentation.lastUsedAt != frozenFirstUserAt)
    }

    @Test("lastModified が distantPast なら lastUsedAt は nil")
    func distantPastLastModifiedIsNilLastUsedAt() {
        let presentation = present(
            makeEntry(
                lastModified: .distantPast,
                titleUserMessages: [FrozenTitle.login]
            )
        )
        #expect(presentation.lastUsedAt == nil)
    }

    @Test("複合絵文字の 32 Character 境界は切らない")
    func familyEmojiThirtyTwoCharactersStayIntact() {
        #expect(FrozenTitle.family32.count == 32)
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.family32])
        )
        #expect(presentation.title == FrozenTitle.family32)
        #expect(presentation.fullTitle == FrozenTitle.family32)
    }

    @Test("複合絵文字の 33 Character は 31 Character と省略記号")
    func familyEmojiThirtyThreeCharactersTruncateOnBoundary() {
        #expect(FrozenTitle.family33.count == 33)
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.family33])
        )
        #expect(presentation.title == FrozenTitle.family33Title)
        #expect(presentation.fullTitle == FrozenTitle.family33)
    }

    @Test("結合文字の 32 Character 境界は切らない")
    func combiningMarkThirtyTwoCharactersStayIntact() {
        #expect(FrozenTitle.combining32.count == 32)
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.combining32])
        )
        #expect(presentation.title == FrozenTitle.combining32)
        #expect(presentation.fullTitle == FrozenTitle.combining32)
    }

    @Test("結合文字の 33 Character は 31 Character と省略記号")
    func combiningMarkThirtyThreeCharactersTruncateOnBoundary() {
        #expect(FrozenTitle.combining33.count == 33)
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.combining33])
        )
        #expect(presentation.title == FrozenTitle.combining33Title)
        #expect(presentation.fullTitle == FrozenTitle.combining33)
    }

    @Test("同一入力の決定性")
    func sameInputIsDeterministic() {
        let entry = makeEntry(titleUserMessages: [FrozenTitle.login])
        let first = present(entry, workingDirectory: "/tmp/project-a/")
        let second = present(entry, workingDirectory: "/tmp/project-a/")
        #expect(first == second)
        #expect(first.title == FrozenTitle.login)
        #expect(first.fullTitle == FrozenTitle.login)
        #expect(first.projectName == FrozenTitle.projectA)
        #expect(first.projectPath == "/tmp/project-a/")
        #expect(first.lastUsedAt == frozenLastModified)
    }

    @Test("モデル生成前後で entry の既存・新規フィールドが変化しない")
    func presentationDoesNotMutateEntry() {
        let entry = makeEntry(
            preview: FrozenTitle.oldPreview,
            titleUserMessages: [FrozenTitle.login],
            titleSummary: FrozenTitle.historyFix
        )
        let sessionID = entry.sessionID
        let preview = entry.preview
        let firstUserAt = entry.firstUserAt
        let lastModified = entry.lastModified
        let gitBranch = entry.gitBranch
        let fileURL = entry.fileURL
        let titleUserMessages = entry.titleUserMessages
        let titleSummary = entry.titleSummary
        _ = present(entry, workingDirectory: "/tmp/project-a/")
        #expect(entry.sessionID == sessionID)
        #expect(entry.preview == preview)
        #expect(entry.firstUserAt == firstUserAt)
        #expect(entry.lastModified == lastModified)
        #expect(entry.gitBranch == gitBranch)
        #expect(entry.fileURL == fileURL)
        #expect(entry.titleUserMessages == titleUserMessages)
        #expect(entry.titleSummary == titleSummary)
        #expect(entry.titleUserMessages == [FrozenTitle.login])
        #expect(entry.titleSummary == FrozenTitle.historyFix)
        #expect(entry.preview == FrozenTitle.oldPreview)
    }

    @Test("接頭辞判定は大文字・小文字を区別し小文字 Base directory は除外しない")
    func baseDirectoryPrefixIsCaseSensitive() {
        #expect(FrozenTitle.lowercaseBaseDirectory.count == 30)
        let presentation = present(
            makeEntry(titleUserMessages: [FrozenTitle.lowercaseBaseDirectory])
        )
        #expect(presentation.title == FrozenTitle.lowercaseBaseDirectory)
        #expect(presentation.fullTitle == FrozenTitle.lowercaseBaseDirectory)
        #expect(presentation.title != FrozenTitle.none)
    }

    @Test("前後空白付きの < 接頭辞も本文全体を除外する")
    func trimmedAnglePrefixSkipsWholeBody() {
        let presentation = present(
            makeEntry(
                titleUserMessages: ["  <command-name>/review</command-name>  ", FrozenTitle.historyFix]
            )
        )
        #expect(presentation.title == FrozenTitle.historyFix)
        #expect(presentation.fullTitle == FrozenTitle.historyFix)
    }
}
