import SwiftUI
import AgentConfigKit
import DesignSystem

/// `/permissions` 相当。`~/.claude/settings.json` の `permissions` を直接編集する。
struct ClaudePermissionsPane: View {
    @Bindable var model: ClaudeConsoleModel

    @State private var draftRule = ""
    @State private var draftBucket: ClaudePermissionBucket = .allow

    private var rules: ClaudePermissionRules {
        ClaudePermissionRules.extract(from: model.settings)
    }

    var body: some View {
        AgentConsolePane(
            title: "権限",
            subtitle: "対話 TUI の /permissions に相当します。~/.claude/settings.json の permissions を編集します。",
            controls: AnyView(editor)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                ForEach(ClaudePermissionBucket.allCases) { bucket in
                    bucketSection(bucket)
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private var editor: some View {
        HStack(spacing: DSSpacing.s) {
            Picker("", selection: $draftBucket) {
                ForEach(ClaudePermissionBucket.allCases) { bucket in
                    Label(bucket.displayName, systemImage: bucket.symbolName).tag(bucket)
                }
            }
            .labelsHidden()
            .frame(width: 132)

            TextField("例: Bash(git status:*)", text: $draftRule)
                .textFieldStyle(.roundedBorder)
                .font(DSFont.monoCaption)
                .onSubmit(addRule)

            Button("追加", action: addRule)
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                .disabled(draftRule.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func bucketSection(_ bucket: ClaudePermissionBucket) -> some View {
        let entries = rules[bucket]
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            AgentConsoleGroupHeader(
                title: bucket.displayName,
                systemImage: bucket.symbolName,
                tint: tint(for: bucket),
                detail: "\(entries.count) 件"
            )
            Text(bucket.explanation)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textTertiary)

            if entries.isEmpty {
                AgentConsoleEmptyState(symbolName: bucket.symbolName, message: "ルールはありません。")
            } else {
                // 枠も罫線も引かない。行はホバー時だけ淡く浮かせる。
                VStack(spacing: 1) {
                    ForEach(entries, id: \.self) { rule in
                        PermissionRuleRow(
                            rule: rule,
                            bucket: bucket,
                            onMove: { move(rule, from: bucket, to: $0) },
                            onRemove: { remove(rule, from: bucket) }
                        )
                    }
                }
            }
        }
    }

    private func tint(for bucket: ClaudePermissionBucket) -> Color {
        switch bucket {
        case .allow: return DSColor.statusCompleted
        case .ask: return DSColor.statusAwaitingApproval
        case .deny: return DSColor.statusError
        }
    }

    // MARK: - 操作

    private func addRule() {
        var updated = rules
        guard updated.add(draftRule, to: draftBucket) else { return }
        let rule = draftRule.trimmingCharacters(in: .whitespacesAndNewlines)
        draftRule = ""
        model.applySettings(updated.apply(to:), successMessage: "「\(rule)」を\(draftBucket.displayName)に追加しました。")
    }

    private func remove(_ rule: String, from bucket: ClaudePermissionBucket) {
        var updated = rules
        updated.remove(rule, from: bucket)
        model.applySettings(updated.apply(to:), successMessage: "「\(rule)」を削除しました。")
    }

    private func move(_ rule: String, from source: ClaudePermissionBucket, to destination: ClaudePermissionBucket) {
        var updated = rules
        updated.move(rule, from: source, to: destination)
        model.applySettings(updated.apply(to:), successMessage: "「\(rule)」を\(destination.displayName)へ移しました。")
    }
}

/// 権限ルール1行。ホバーしたときだけ操作メニューを目立たせる。
private struct PermissionRuleRow: View {
    let rule: String
    let bucket: ClaudePermissionBucket
    let onMove: (ClaudePermissionBucket) -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            Text(rule)
                .font(DSFont.monoCaption)
                .foregroundStyle(DSColor.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DSSpacing.s)
            Menu {
                ForEach(ClaudePermissionBucket.allCases.filter { $0 != bucket }) { destination in
                    Button("「\(destination.displayName)」へ移す") { onMove(destination) }
                }
                Divider()
                Button("削除", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: DSIconSize.m, weight: .bold))
                    .foregroundStyle(isHovering ? DSColor.textSecondary : DSColor.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .pointingHandCursor()
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.s)
        .background(isHovering ? DSColor.fillSubtle : .clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
        }
    }
}
