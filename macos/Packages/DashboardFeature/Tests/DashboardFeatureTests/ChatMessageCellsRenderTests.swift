import AppKit
import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// task-3 白箱: AgentAvatar（private）経由で builtin ブランド・symbol フォールバック・
// 頭文字フォールバックの各 descriptor が AgentMessageCell / ThinkingIndicatorCell で
// クラッシュせず非空描画になる（swift test では xcassets 未コンパイルのためピクセル検証は行わない）。
@Test @MainActor
func agentAvatarBrandIconPathsRenderWithoutCrash() throws {
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    let descriptors: [AgentDescriptor] = [
        AgentRegistry.descriptor(for: .claudeCode),
        AgentRegistry.descriptor(for: .codex),
        AgentRegistry.descriptor(for: .cursor),
        AgentDescriptor(
            ref: .custom("custom-agent"),
            displayName: "Custom Agent",
            binaryName: "custom-agent",
            symbolName: "",
            colorRGB: AgentRGB(0x66, 0x77, 0x88),
            bypassKey: "phlox.bypass.custom",
            launchSpec: AgentLaunchSpec()
        ),
    ]

    for descriptor in descriptors {
        let agentImage = try renderImage(from: AgentMessageCell(
            text: "Agent avatar smoke.",
            timestamp: timestamp,
            descriptor: descriptor
        ))
        let thinkingImage = try renderImage(from: ThinkingIndicatorCell(descriptor: descriptor))
        #expect(try tiffData(from: agentImage).isEmpty == false)
        #expect(try tiffData(from: thinkingImage).isEmpty == false)
    }
}

// スモークテスト: 各セルが crash せず描画され、非空画像（chrome を含む）を生成することを確認する。
@Test @MainActor
func chatMessageCellsRenderAllVariants() throws {
    let descriptor = AgentRegistry.descriptor(for: .codex)
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    let renderedImages = try [
        renderImage(from: UserMessageCell(text: "Implement the chat UI.", timestamp: timestamp)),
        renderImage(from: AgentMessageCell(text: representativeAgentMarkdown, timestamp: timestamp, descriptor: descriptor)),
        renderImage(from: CodeBlockView(language: "swift", code: representativeCode)),
        renderImage(from: CommandExecutionCell(command: "swift test", output: "Build complete\nTest Suite passed", timestamp: timestamp, isRunning: false)),
        renderImage(from: CommandExecutionCell(command: "npm test", output: "", timestamp: timestamp, isRunning: true)),
        renderImage(from: ReasoningSummaryView(text: "Checked the formatter and cell states.", timestamp: timestamp)),
        renderImage(from: FileChangeCell(changes: [representativeFileChange], timestamp: timestamp)),
        renderImage(from: ThinkingIndicatorCell(descriptor: descriptor)),
    ]

    for image in renderedImages {
        #expect(try #require(image.tiffRepresentation).isEmpty == false)
    }
}

@Test @MainActor
func agentMarkdownRendersDifferentlyFromEmptyMarkdown() throws {
    let contentImage = try renderImage(from: RichMarkdownView(representativeMarkdownOnly))
    let emptyImage = try renderImage(from: RichMarkdownView(""))

    #expect(try tiffData(from: contentImage) != tiffData(from: emptyImage))
}

@Test @MainActor
func codeBlockRendersDifferentlyFromEmptyCodeBlock() throws {
    let contentImage = try renderImage(from: CodeBlockView(language: "swift", code: representativeCode))
    let emptyImage = try renderImage(from: CodeBlockView(language: "swift", code: ""))

    #expect(try tiffData(from: contentImage) != tiffData(from: emptyImage))
}

@Test
func composerPlaceholderVisibilityTracksIMEComposition() {
    #expect(ComposerPlaceholderVisibility.shouldShowPlaceholder(text: "", isComposing: false))
    #expect(!ComposerPlaceholderVisibility.shouldShowPlaceholder(text: "", isComposing: true))
    #expect(!ComposerPlaceholderVisibility.shouldShowPlaceholder(text: "こんにちは", isComposing: false))
    #expect(!ComposerPlaceholderVisibility.shouldShowPlaceholder(text: "こんにちは", isComposing: true))
}

// task-7 成功基準6: 非空 reasoning セルは ReasoningSummaryView を描画し、
// 空 reasoning は EmptyView（空背景と同一）になる。ChatItemView の分岐(18-23行)を検証。
@Test @MainActor
func reasoningCellRendersContentButEmptyReasoningRendersBlank() throws {
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    let descriptor = AgentRegistry.descriptor(for: .codex)

    let contentImage = try renderImage(from: ChatItemView(
        item: .reasoning(id: "r1", text: "Checked the formatter and cell states.", timestamp: timestamp),
        isRunningCommand: false,
        agentDescriptor: descriptor
    ))
    let emptyImage = try renderImage(from: ChatItemView(
        item: .reasoning(id: "r2", text: "   ", timestamp: timestamp),
        isRunningCommand: false,
        agentDescriptor: descriptor
    ))
    let blankImage = try renderImage(from: EmptyView())

    #expect(try tiffData(from: contentImage) != tiffData(from: emptyImage))
    #expect(try tiffData(from: emptyImage) == tiffData(from: blankImage))
}

// task-18 成功基準3: output が空の commandExecution は DisclosureCard
// 自体を描画せず、空 reasoning と同じく EmptyView 相当になる。
@Test @MainActor
func commandExecutionWithEmptyOutputRendersBlank() throws {
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    let descriptor = AgentRegistry.descriptor(for: .cursor)

    let contentImage = try renderImage(from: ChatItemView(
        item: .commandExecution(id: "cmd1", command: "Glob", output: "keep.txt\n", timestamp: timestamp),
        isRunningCommand: false,
        agentDescriptor: descriptor
    ))
    let emptyImage = try renderImage(from: ChatItemView(
        item: .commandExecution(id: "cmd2", command: "Delete", output: "   \n", timestamp: timestamp),
        isRunningCommand: false,
        agentDescriptor: descriptor
    ))
    let blankImage = try renderImage(from: EmptyView())

    #expect(try tiffData(from: contentImage) != tiffData(from: emptyImage))
    #expect(try tiffData(from: emptyImage) == tiffData(from: blankImage))
}

// task-5: 実行中ツールコールは完了時と描画が異なり、repeat-forever を使わないこと。
@Test @MainActor
func commandExecutionRunningRendersDifferentlyFromComplete() throws {
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    let runningImage = try renderImage(from: CommandExecutionCell(
        command: "swift test",
        output: "",
        timestamp: timestamp,
        isRunning: true
    ))
    let completeImage = try renderImage(from: CommandExecutionCell(
        command: "swift test",
        output: "Build complete",
        timestamp: timestamp,
        isRunning: false
    ))

    #expect(try tiffData(from: runningImage) != tiffData(from: completeImage))
}

@Test
func chatMessageCellsSourceHasNoRepeatForeverModifier() throws {
    // ChatMessageCells.swift は R1(task-27)で SessionFeature パッケージへ移設した。
    // テストは DashboardFeatureTests に残るため、Packages/ まで 4 階層遡って新 location を指す。
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceURL = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("SessionFeature/Sources/SessionFeature/ChatMessageCells.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(
        !source.contains(".repeatForever"),
        "DisclosureStatus.running のアニメは Core Animation か TimelineView 駆動に限定すること"
    )
}

// task-18 レビュー差し戻し #1: Cursor の実行中コマンドは completed まで
// output が空なので、running 中は空でも CommandExecutionCell を描画する。
@Test @MainActor
func runningCommandWithEmptyOutputStillRendersCommandExecutionCell() throws {
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    let descriptor = AgentRegistry.descriptor(for: .cursor)

    let runningItemImage = try renderImage(from: ChatItemView(
        item: .commandExecution(id: "cmd-running", command: "npm test", output: "", timestamp: timestamp),
        isRunningCommand: true,
        agentDescriptor: descriptor
    ))
    let directCellImage = try renderImage(from: CommandExecutionCell(
        command: "npm test",
        output: "",
        timestamp: timestamp,
        isRunning: true
    ))
    let blankImage = try renderImage(from: EmptyView())

    #expect(try tiffData(from: runningItemImage) != tiffData(from: blankImage))
    #expect(try tiffData(from: runningItemImage) == tiffData(from: directCellImage))
}

// task-11 成功基準1/2/4: Claude/Cursor セッションのコンポーザーに model/permission(mode)
// メニューが出る（メニュー無しの未対応エージェントと描画が異なる＝分岐が効いている）。
@Test @MainActor
func composerRendersSettingsMenusForSpawnAgents() async throws {
    let claude = try await startedSpawnViewModel(agentRef: .builtin(.claudeCode))
    let cursor = try await startedSpawnViewModel(agentRef: .builtin(.cursor))
    let unsupported = try await startedSpawnViewModel(agentRef: .custom("unknown-cli"))

    // 前提: 分岐に必要な軽量表示状態が用意されている。
    #expect(claude.availableSpawnAgentModels == ["opus", "sonnet", "fable", "haiku"])
    #expect(claude.selectedPermissionProfile == "bypassPermissions")
    #expect(!cursor.availableSpawnAgentModels.isEmpty)
    #expect(unsupported.availableSpawnAgentModels.isEmpty)

    let claudeImage = try renderImage(from: ChatSessionView(viewModel: claude))
    let cursorImage = try renderImage(from: ChatSessionView(viewModel: cursor))
    let unsupportedImage = try renderImage(from: ChatSessionView(viewModel: unsupported))

    #expect(try tiffData(from: claudeImage).isEmpty == false)
    #expect(try tiffData(from: cursorImage).isEmpty == false)
    // メニュー有り（Claude/Cursor）とメニュー無し（未対応）で描画が変わる＝出し分けが効いている。
    #expect(try tiffData(from: claudeImage) != tiffData(from: unsupportedImage))
    #expect(try tiffData(from: cursorImage) != tiffData(from: unsupportedImage))
}

// task-16 成功基準1/2: Claude/Cursor の Plan は permission/mode メニューから分離され、
// 独立トグルとして active 状態を描画へ反映する。
@Test @MainActor
func composerRendersIndependentPlanToggleForSpawnAgents() async throws {
    let claude = try await startedSpawnViewModel(agentRef: .builtin(.claudeCode))
    let cursor = try await startedSpawnViewModel(agentRef: .builtin(.cursor))

    let claudeOffImage = try renderImage(from: ChatSessionView(viewModel: claude))
    try await claude.setPlanMode(true)
    let claudeOnImage = try renderImage(from: ChatSessionView(viewModel: claude))

    let cursorOffImage = try renderImage(from: ChatSessionView(viewModel: cursor))
    try await cursor.setPlanMode(true)
    let cursorOnImage = try renderImage(from: ChatSessionView(viewModel: cursor))

    #expect(try tiffData(from: claudeOffImage) != tiffData(from: claudeOnImage))
    #expect(try tiffData(from: cursorOffImage) != tiffData(from: cursorOnImage))
}

// task-16 成功基準4: Plan トグル操作は permission/mode 選択から独立して ViewModel 状態を切り替える。
// Claude は常に具体値（nil を渡さない）、Cursor の Run Everything は nil でよい。
@Test @MainActor
func spawnAgentSelectionHandlersUpdateViewModelState() async throws {
    let claude = try await startedSpawnViewModel(agentRef: .builtin(.claudeCode))
    await claude.setSpawnAgentModel("sonnet")
    await claude.setSpawnAgentPermission("acceptEdits")
    #expect(claude.selectedModel == "sonnet")
    #expect(claude.selectedPermissionProfile == "acceptEdits")
    try await claude.setPlanMode(true)
    #expect(claude.isPlanMode)
    #expect(claude.selectedPermissionProfile == "acceptEdits")
    try await claude.setPlanMode(false)
    #expect(!claude.isPlanMode)
    #expect(claude.selectedPermissionProfile == "acceptEdits")

    let cursor = try await startedSpawnViewModel(agentRef: .builtin(.cursor))
    await cursor.setSpawnAgentPermission(nil)
    #expect(cursor.selectedPermissionProfile == nil)
    try await cursor.setPlanMode(true)
    #expect(cursor.isPlanMode)
    #expect(cursor.selectedPermissionProfile == nil)
    try await cursor.setPlanMode(false)
    #expect(!cursor.isPlanMode)
    #expect(cursor.selectedPermissionProfile == nil)
}

@MainActor
private func startedSpawnViewModel(agentRef: AgentRef) async throws -> ChatSessionViewModel {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: agentRef,
        client: SpawnSettingsRecordingClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    return vm
}

/// spawn 型（Claude/Cursor）ハンドラ検証用: StructuredAgentClient かつ
/// SpawnAgentSettingsControlling に準拠し、actor への反映呼び出しを受け付ける。
private final class SpawnSettingsRecordingClient: StructuredAgentClient, SpawnAgentSettingsControlling, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent> = AsyncStream { _ in }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {}
}

@MainActor
private func renderImage<V: View>(from view: V) throws -> NSImage {
    let renderer = ImageRenderer(
        content: view
            .padding(16)
            .frame(width: 720, height: 420, alignment: .topLeading)
            .background(DSColor.chatBackground)
    )
    renderer.scale = 1
    return try #require(renderer.nsImage)
}

private func tiffData(from image: NSImage) throws -> Data {
    try #require(image.tiffRepresentation)
}

private let representativeMarkdownOnly = """
# Plan

- Keep the transcript stable.
- Replace inline-only `MarkdownText`.
- Preserve auto-follow behavior.
"""

private let representativeCode = """
struct Example {
    let value = "Phlox"
    // keep syntax color visible
}
"""

private let representativeAgentMarkdown = """
# Plan

- Keep the transcript stable.
- Replace inline-only `MarkdownText`.
- Preserve auto-follow behavior.

```swift
\(representativeCode)
```
"""

private let representativeFileChange = FilePatchChange(
    path: "Sources/Example.swift",
    diff: """
    diff --git a/Sources/Example.swift b/Sources/Example.swift
    @@ -1,3 +1,3 @@
    -let title = "Old"
    +let title = "Phlox"
     print(title)
    """
)
