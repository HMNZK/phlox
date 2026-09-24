import Foundation
import SwiftUI
import DesignSystem
import SessionFeature

// task-15 契約の PM スタブ。API 表面は受け入れテスト
// SessionInfoPanelAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-15.md

/// セッション開始からの経過時間ラベル。
enum SessionElapsedFormat {
    /// 1時間未満 `MM:SS` / 以上 `H:MM:SS`（H はゼロ詰めなし）。負値は 0 に丸める。
    static func label(from: Date, to: Date) -> String {
        let totalSeconds = max(0, Int(to.timeIntervalSince(from)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// インスペクタの「セッション」（07 I1・I2）。見出し（タイトルと種類）と、状態・経過時間・総コスト・ブランチ・
/// プロジェクト・作業ディレクトリの行。ターミナル型で取れない値は「—」。
struct SessionInfoPanel: View {
    let session: SessionNode
    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: session.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)
                Text(verbatim: subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                row("状態") {
                    TimelineView(.periodic(from: .now, by: session.isStalled ? 1 : 60)) { context in
                        value(GridTileText.stateLabel(
                            state: session.gridDisplayState,
                            since: session.statusEnteredAt,
                            silence: session.stalledSilence(now: context.date),
                            now: context.date,
                            locale: locale
                        ))
                    }
                }
                row("経過時間") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        value(SessionElapsedFormat.label(from: session.startedAt, to: context.date))
                    }
                }
                row("総コスト") { value(formattedCost) }
                row("ブランチ") {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        value(resolvedBranch ?? "—", mono: true)
                    }
                }
                row("プロジェクト") { value(session.workspaceName.isEmpty ? "—" : session.workspaceName) }
                row("作業ディレクトリ") { value(session.workspacePath.isEmpty ? "—" : session.workspacePath, mono: true) }
            }

            if session.pty != nil {
                Text("ターミナル型のセッションはコストを取得できないため「—」と表示します。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「Claude Code · チャット型 · プロジェクト · a3f9」。
    private var subtitle: String {
        let kind = AppLocalizedString.string(session.pty == nil ? "チャット型" : "ターミナル型", locale: locale)
        return [session.agentDescriptor.displayName, kind, session.workspaceName, SessionViewModel.shortID(for: session.id)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var formattedCost: String {
        guard let cost = session.appServer?.sessionTotalCostUSD, cost > 0 else { return "—" }
        return String(format: "$%.4f", cost)
    }

    private var resolvedBranch: String? {
        let expanded = (session.workspacePath as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return nil }
        return GitBranchReader.currentBranch(at: expanded)
    }

    private func row<Value: View>(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize()
            Spacer(minLength: 0)
            value()
        }
        .font(.system(size: 12))
        .padding(.vertical, 7)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String, mono: Bool = false) -> some View {
        Text(verbatim: text)
            .font(mono ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
            .foregroundStyle(text == "—" ? DSColor.textTertiary : DSColor.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
