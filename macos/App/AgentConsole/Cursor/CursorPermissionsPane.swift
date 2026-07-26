import SwiftUI
import AgentConfigKit
import DesignSystem

/// `cli-config.json` の `permissions`（許可・拒否）を編集する。
///
/// Claude Code と違い「毎回たずねる」バケットは無い。許可リスト外をどう扱うかは
/// 「設定」ペインの承認モードが決める。
struct CursorPermissionsPane: View {
    @Bindable var model: CursorConsoleModel

    @State private var draftRule = ""
    @State private var draftBucket: CursorPermissionBucket = .allow

    private var rules: CursorPermissionRules {
        CursorPermissionRules.extract(from: model.settings)
    }

    var body: some View {
        AgentConsolePane(
            title: "権限",
            subtitle: "~/.cursor/cli-config.json の permissions を編集します。拒否は許可より優先されます。",
            controls: AnyView(editor)
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                ForEach(CursorPermissionBucket.allCases) { bucket in
                    bucketSection(bucket)
                }
            }
            .agentConsoleScrollBody()
        }
    }

    private var editor: some View {
        HStack(spacing: DSSpacing.s) {
            Picker("", selection: $draftBucket) {
                ForEach(CursorPermissionBucket.allCases) { bucket in
                    Label(bucket.displayName, systemImage: bucket.symbolName).tag(bucket)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            TextField("例: Shell(git status)", text: $draftRule)
                .textFieldStyle(.roundedBorder)
                .font(DSFont.monoCaption)
                .onSubmit(addRule)

            Button("追加", action: addRule)
                .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
                .disabled(draftRule.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func bucketSection(_ bucket: CursorPermissionBucket) -> some View {
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
                VStack(spacing: 1) {
                    ForEach(entries, id: \.self) { rule in
                        CursorPermissionRuleRow(
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

    private func tint(for bucket: CursorPermissionBucket) -> Color {
        switch bucket {
        case .allow: return DSColor.statusCompleted
        case .deny: return DSColor.statusError
        }
    }

    // MARK: - 操作

    private func addRule() {
        var updated = rules
        guard updated.add(draftRule, to: draftBucket) else { return }
        let rule = draftRule.trimmingCharacters(in: .whitespacesAndNewlines)
        draftRule = ""
        model.applySettings(
            updated.apply(to:),
            successMessage: "「\(rule)」を\(draftBucket.displayName)に追加しました。"
        )
    }

    private func remove(_ rule: String, from bucket: CursorPermissionBucket) {
        var updated = rules
        updated.remove(rule, from: bucket)
        model.applySettings(updated.apply(to:), successMessage: "「\(rule)」を削除しました。")
    }

    private func move(_ rule: String, from source: CursorPermissionBucket, to destination: CursorPermissionBucket) {
        var updated = rules
        updated.move(rule, from: source, to: destination)
        model.applySettings(
            updated.apply(to:),
            successMessage: "「\(rule)」を\(destination.displayName)へ移しました。"
        )
    }
}

/// 権限ルール1行。ホバーしたときだけ操作メニューを目立たせる。
private struct CursorPermissionRuleRow: View {
    let rule: String
    let bucket: CursorPermissionBucket
    let onMove: (CursorPermissionBucket) -> Void
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
                ForEach(CursorPermissionBucket.allCases.filter { $0 != bucket }) { destination in
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
