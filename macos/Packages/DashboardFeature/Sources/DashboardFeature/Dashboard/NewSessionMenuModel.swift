import Foundation
import AgentDomain
import SessionFeature

/// サイドバー「＋」メニューの作成先と起動候補。SwiftUI 非依存の純粋値型。
struct NewSessionMenuModel: Equatable {
    struct Item: Equatable, Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let ref: AgentRef
        let backend: SessionBackend
    }

    struct Section: Equatable {
        let title: String
        let items: [Item]
    }

    static let chatSectionTitle = "チャット — 会話形式で応答を読む"
    static let terminalSectionTitle = "ターミナル — CLI をそのまま端末で操作"

    let destinationText: String
    let primary: Item?
    let sections: [Section]

    static func make(projectName: String?, descriptors: [AgentDescriptor]) -> NewSessionMenuModel {
        let trimmed = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let destinationText = "作成先: " + (trimmed.isEmpty ? "名称未設定のプロジェクト" : trimmed)

        var chatItems: [Item] = []
        var terminalItems: [Item] = []
        for descriptor in descriptors {
            for mode in AgentStartCardsModel.modes(for: descriptor) {
                switch mode {
                case .chat:
                    chatItems.append(
                        Item(
                            id: "chat:\(descriptor.ref.id)",
                            title: descriptor.displayName,
                            systemImage: "bubble.left.and.bubble.right",
                            ref: descriptor.ref,
                            backend: mode.backend
                        )
                    )
                case .terminal:
                    terminalItems.append(
                        Item(
                            id: "terminal:\(descriptor.ref.id)",
                            title: descriptor.displayName,
                            systemImage: "terminal",
                            ref: descriptor.ref,
                            backend: mode.backend
                        )
                    )
                }
            }
        }

        let primary: Item?
        if let firstChat = chatItems.first {
            primary = Item(
                id: "primary",
                title: "新しいチャット（\(firstChat.title)）",
                systemImage: "plus.bubble",
                ref: firstChat.ref,
                backend: firstChat.backend
            )
        } else {
            primary = nil
        }

        var sections: [Section] = []
        if !chatItems.isEmpty {
            sections.append(Section(title: chatSectionTitle, items: chatItems))
        }
        if !terminalItems.isEmpty {
            sections.append(Section(title: terminalSectionTitle, items: terminalItems))
        }

        return NewSessionMenuModel(
            destinationText: destinationText,
            primary: primary,
            sections: sections
        )
    }
}
