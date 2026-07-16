import Foundation
import SwiftUI
import DesignSystem

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

/// 表示中チャットセッションのメタ情報（経過時間・コスト・ブランチ・ワークスペース）。
struct SessionInfoPanel: View {
    let startedAt: Date
    let sessionTotalCostUSD: Double
    let workspacePath: String
    let workspaceName: String
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            infoRow(label: "経過時間") { elapsedValue }
            infoRow(label: "総コスト") { costValue }
            infoRow(label: "ブランチ") { branchValue }
            if !workspaceName.isEmpty {
                infoRow(label: "プロジェクト") {
                    Text(workspaceName)
                        .font(DSFont.captionStrong)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.m))
    }

    private var elapsedValue: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(SessionElapsedFormat.label(from: startedAt, to: context.date))
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textPrimary)
                .monospacedDigit()
        }
    }

    private var costValue: some View {
        Text(formattedCost)
            .font(DSFont.captionStrong)
            .foregroundStyle(DSColor.textPrimary)
            .monospacedDigit()
    }

    private var branchValue: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Text(resolvedBranch ?? "—")
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var formattedCost: String {
        guard sessionTotalCostUSD > 0 else { return "—" }
        return String(format: "$%.4f", sessionTotalCostUSD)
    }

    private var resolvedBranch: String? {
        let expanded = (workspacePath as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return nil }
        return GitBranchReader.currentBranch(at: expanded)
    }

    private func infoRow<Value: View>(label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(label)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)
            value()
        }
    }
}
