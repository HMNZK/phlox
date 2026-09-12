// task-33（UX-07）の受け入れテスト。
//
// ベースラインでの red 理由: `NewSessionMenuModel` と
// `NewSessionMenuModel.make(projectName:descriptors:)`、
// `NewSessionMenuModel.Item` / `Section`、
// `chatSectionTitle` / `terminalSectionTitle` は本タスクが新設を要求する API で、
// baseline_commit には存在しない（参照未解決でコンパイル不能＝red）。
//
// 契約: 作成先を明示し、「新しいチャット」を先頭の主操作にし、
// 残りをチャット／ターミナルの節に分ける。既存の各エージェント×表示方式への経路は残す。

import AgentDomain
import SessionFeature
import Testing
@testable import DashboardFeature

@Suite("task-33: new session menu model")
struct AcceptanceNewSessionMenuModelTests {
    @Test("destinationText は trim 済み非空なら「作成先: 」+名前。nil・空・空白のみは「作成先: 名称未設定のプロジェクト」")
    func destinationTextTrimsEmptyAndNil() {
        #expect(
            NewSessionMenuModel.make(projectName: "UI検証A", descriptors: []).destinationText
                == "作成先: UI検証A"
        )
        #expect(
            NewSessionMenuModel.make(projectName: "  UI検証A  ", descriptors: []).destinationText
                == "作成先: UI検証A"
        )
        #expect(
            NewSessionMenuModel.make(projectName: nil, descriptors: []).destinationText
                == "作成先: 名称未設定のプロジェクト"
        )
        #expect(
            NewSessionMenuModel.make(projectName: "", descriptors: []).destinationText
                == "作成先: 名称未設定のプロジェクト"
        )
        #expect(
            NewSessionMenuModel.make(projectName: "   ", descriptors: []).destinationText
                == "作成先: 名称未設定のプロジェクト"
        )
    }

    @Test("primary は descriptors の順で最初の supportsStructuredChat == true。id/title/systemImage/backend は契約どおり")
    func primaryIsFirstChatCapableDescriptorInOrder() {
        let claude = AgentRegistry.allDescriptors[0]
        let cursorOnly = terminalOnlyCopy(AgentRegistry.allDescriptors[2])
        let model = NewSessionMenuModel.make(
            projectName: "UI検証A",
            descriptors: [cursorOnly] + AgentRegistry.allDescriptors
        )

        #expect(model.primary != nil)
        #expect(model.primary?.id == "primary")
        #expect(model.primary?.title == "新しいチャット（Claude Code）")
        #expect(model.primary?.systemImage == "plus.bubble")
        #expect(model.primary?.backend == .appServer)
        #expect(model.primary?.ref == claude.ref)
    }

    @Test("チャット非対応のみなら primary は nil かつチャット節なし")
    func chatIncapableOnlyHasNoPrimaryAndNoChatSection() {
        let claudeOnly = terminalOnlyCopy(AgentRegistry.allDescriptors[0])
        let codexOnly = terminalOnlyCopy(AgentRegistry.allDescriptors[1])
        let model = NewSessionMenuModel.make(
            projectName: "UI検証A",
            descriptors: [claudeOnly, codexOnly]
        )

        #expect(model.primary == nil)
        #expect(model.sections.count == 1)
        #expect(model.sections[0].title == "ターミナル — CLI をそのまま端末で操作")
        #expect(!model.sections.contains { $0.title == "チャット — 会話形式で応答を読む" })
        #expect(model.sections[0].items.map(\.id) == ["terminal:claudeCode", "terminal:codex"])
        #expect(model.sections[0].items.map(\.title) == ["Claude Code", "Codex"])
        #expect(model.sections[0].items.map(\.systemImage) == ["terminal", "terminal"])
        #expect(model.sections[0].items.map(\.backend) == [.pty, .pty])
        #expect(model.sections[0].items.map(\.ref) == [claudeOnly.ref, codexOnly.ref])
    }

    @Test("全 descriptor にターミナル項目、チャット対応 descriptor にチャット項目が descriptors の順序どおり存在する")
    func chatAndTerminalItemsFollowDescriptorOrder() {
        let cursorOnly = terminalOnlyCopy(AgentRegistry.allDescriptors[2])
        let claude = AgentRegistry.allDescriptors[0]
        let codex = AgentRegistry.allDescriptors[1]
        let model = NewSessionMenuModel.make(
            projectName: "UI検証A",
            descriptors: [cursorOnly, claude, codex]
        )

        #expect(model.sections.count == 2)

        let chat = model.sections[0]
        #expect(chat.title == "チャット — 会話形式で応答を読む")
        #expect(chat.items.map(\.id) == ["chat:claudeCode", "chat:codex"])
        #expect(chat.items.map(\.title) == ["Claude Code", "Codex"])
        #expect(chat.items.map(\.systemImage) == ["bubble.left.and.bubble.right", "bubble.left.and.bubble.right"])
        #expect(chat.items.map(\.backend) == [.appServer, .appServer])
        #expect(chat.items.map(\.ref) == [claude.ref, codex.ref])

        let terminal = model.sections[1]
        #expect(terminal.title == "ターミナル — CLI をそのまま端末で操作")
        #expect(terminal.items.map(\.id) == ["terminal:cursor", "terminal:claudeCode", "terminal:codex"])
        #expect(terminal.items.map(\.title) == ["Cursor", "Claude Code", "Codex"])
        #expect(terminal.items.map(\.systemImage) == ["terminal", "terminal", "terminal"])
        #expect(terminal.items.map(\.backend) == [.pty, .pty, .pty])
        #expect(terminal.items.map(\.ref) == [cursorOnly.ref, claude.ref, codex.ref])
    }

    @Test("primary と全節の item id は一意")
    func itemIDsAreUnique() {
        let model = NewSessionMenuModel.make(
            projectName: "UI検証A",
            descriptors: AgentRegistry.allDescriptors
        )
        var ids: [String] = []
        if let primary = model.primary {
            ids.append(primary.id)
        }
        ids.append(contentsOf: model.sections.flatMap { $0.items.map(\.id) })

        #expect(ids.contains("primary"))
        #expect(ids.contains("chat:claudeCode"))
        #expect(ids.contains("chat:codex"))
        #expect(ids.contains("chat:cursor"))
        #expect(ids.contains("terminal:claudeCode"))
        #expect(ids.contains("terminal:codex"))
        #expect(ids.contains("terminal:cursor"))
        #expect(Set(ids).count == ids.count)
    }

    @Test("descriptors が空なら primary は nil、sections は空、destinationText は出る")
    func emptyDescriptorsYieldNoPrimaryAndNoSections() {
        let named = NewSessionMenuModel.make(projectName: "UI検証A", descriptors: [])
        #expect(named.primary == nil)
        #expect(named.sections == [])
        #expect(named.destinationText == "作成先: UI検証A")

        let unnamed = NewSessionMenuModel.make(projectName: nil, descriptors: [])
        #expect(unnamed.primary == nil)
        #expect(unnamed.sections == [])
        #expect(unnamed.destinationText == "作成先: 名称未設定のプロジェクト")
    }

    @Test("節タイトル定数は契約どおり")
    func sectionTitleConstants() {
        #expect(NewSessionMenuModel.chatSectionTitle == "チャット — 会話形式で応答を読む")
        #expect(NewSessionMenuModel.terminalSectionTitle == "ターミナル — CLI をそのまま端末で操作")

        let model = NewSessionMenuModel.make(
            projectName: "UI検証A",
            descriptors: AgentRegistry.allDescriptors
        )
        #expect(model.sections.map(\.title) == [
            "チャット — 会話形式で応答を読む",
            "ターミナル — CLI をそのまま端末で操作",
        ])
    }
}

private func terminalOnlyCopy(_ source: AgentDescriptor) -> AgentDescriptor {
    AgentDescriptor(
        kind: source.kind,
        displayName: source.displayName,
        binaryName: source.binaryName,
        symbolName: source.symbolName,
        colorRGB: source.colorRGB,
        bypassKey: source.bypassKey,
        usageProviderKind: source.usageProviderKind,
        launchSpec: source.launchSpec,
        supportsStructuredChat: false
    )
}
