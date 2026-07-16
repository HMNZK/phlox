import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// 空状態カードで選べる起動モード（task-1 契約面）。
enum AgentStartCardMode: Equatable {
    case chat
    case terminal

    var backend: SessionBackend {
        self == .chat ? .appServer : .pty
    }

    var label: String {
        switch self {
        case .chat: "チャット"
        case .terminal: "ターミナル"
        }
    }
}

/// 空状態のエージェント選択カードのモデル（task-1 契約面）。
struct AgentStartCard: Equatable, Identifiable {
    let kind: AgentKind
    var id: AgentKind { kind }
}

enum AgentStartCardsModel {
    /// 利用可能な CLI（`DashboardViewModel.availableAgentKinds`）からカード列を作る（順序保持）。
    static func cards(available: [AgentKind]) -> [AgentStartCard] {
        available.map { AgentStartCard(kind: $0) }
    }

    static func modes(for descriptor: AgentDescriptor) -> [AgentStartCardMode] {
        descriptor.supportsStructuredChat ? [.chat, .terminal] : [.terminal]
    }
}

/// カード選択から `spawnNewSessionUsingDefaultProject` への配線。
enum AgentStartCardSelection {
    @MainActor
    static func spawnNewSession(
        kind: AgentKind,
        viewModel: DashboardViewModel,
        selectedSessionID: SessionID?,
        selectedProjectID: ProjectID? = nil
    ) async throws -> SessionID {
        try await viewModel.spawnNewSessionUsingDefaultProject(
            kind: kind,
            selectedSessionID: selectedSessionID,
            selectedProjectID: selectedProjectID
        )
    }
}

struct AgentStartCardsView: View {
    let cards: [AgentStartCard]
    let isCreating: Bool
    let onSelect: (AgentKind, SessionBackend) -> Void
    var onLayoutDecision: ((Bool) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            content(availableWidth: proxy.size.width)
        }
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat) -> some View {
        let stackVertically = AgentStartCardsLayoutPolicy.shouldStackVertically(
            availableWidth: availableWidth,
            cardCount: cards.count
        )

        VStack(spacing: DSSpacing.l) {
            Text("エージェントを選んでセッションを開始")
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.textSecondary)

            cardRow(stackVertically: stackVertically)
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LayoutDecisionReporter(
                stacksVertically: stackVertically,
                onLayoutDecision: onLayoutDecision
            )
        }
    }

    @ViewBuilder
    private func cardRow(stackVertically: Bool) -> some View {
        if stackVertically {
            ScrollView {
                VStack(spacing: DSSpacing.m) {
                    ForEach(cards) { card in
                        AgentStartCardButton(
                            card: card,
                            isDisabled: isCreating,
                            onSelect: onSelect
                        )
                    }
                }
            }
        } else {
            HStack(spacing: DSSpacing.m) {
                ForEach(cards) { card in
                    AgentStartCardButton(
                        card: card,
                        isDisabled: isCreating,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

/// 白箱テスト用: レイアウト判定を ImageRenderer 描画時に報告する（表示に影響なし）。
private struct LayoutDecisionReporter: View {
    let stacksVertically: Bool
    var onLayoutDecision: ((Bool) -> Void)?

    var body: some View {
        if let onLayoutDecision {
            let _ = onLayoutDecision(stacksVertically)
        }
        Color.clear.frame(width: 0, height: 0)
    }
}

private struct AgentStartCardButton: View {
    let card: AgentStartCard
    let isDisabled: Bool
    let onSelect: (AgentKind, SessionBackend) -> Void

    private var descriptor: AgentDescriptor {
        AgentRegistry.descriptor(for: card.kind)
    }

    private var modes: [AgentStartCardMode] {
        AgentStartCardsModel.modes(for: descriptor)
    }

    private var agentTint: Color {
        DSColor.agentColor(for: card.kind)
    }

    var body: some View {
        VStack(spacing: DSSpacing.s) {
            VStack(spacing: DSSpacing.s) {
                AgentBrandIcon(descriptor: descriptor, size: 48)
                Text(descriptor.displayName)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
            }

            HStack(spacing: DSSpacing.xs) {
                ForEach(modes, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .frame(minWidth: 148, minHeight: 156)
        .padding(DSSpacing.m)
        .background(agentTint.opacity(0.08), in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(agentTint.opacity(0.18), lineWidth: 1)
        }
        .opacity(isDisabled ? 0.5 : 1)
    }

    @ViewBuilder
    private func modeButton(_ mode: AgentStartCardMode) -> some View {
        switch mode {
        case .chat:
            Button {
                onSelect(card.kind, mode.backend)
            } label: {
                Text(mode.label)
                    .font(DSFont.captionStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, DSSpacing.s)
                    .padding(.vertical, DSSpacing.xs)
            }
            .buttonStyle(
                HoverableSurfaceButtonStyle(
                    cornerRadius: DSRadius.s,
                    baseFill: agentTint.opacity(0.16),
                    hoverFill: agentTint.opacity(0.22),
                    pressedFill: agentTint.opacity(0.28),
                    borderColor: agentTint.opacity(0.28),
                    hoverBorderColor: agentTint.opacity(0.42)
                )
            )
            .disabled(isDisabled)
        case .terminal:
            Button {
                onSelect(card.kind, mode.backend)
            } label: {
                Text(mode.label)
                    .font(DSFont.captionStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, DSSpacing.s)
                    .padding(.vertical, DSSpacing.xs)
            }
            .buttonStyle(HoverableSoftButtonStyle())
            .disabled(isDisabled)
        }
    }
}
