import SwiftUI
import AgentConfigKit
import DesignSystem

/// Claude Code の skill（`~/.claude/skills` と `<project>/.claude/skills`）を一覧・編集する。
struct ClaudeSkillsPane: View {
    @Bindable var model: ClaudeConsoleModel

    @State private var searchText = ""
    @State private var selectedSkillID: String?
    @State private var draft = ""
    @State private var loadedSkillID: String?
    @State private var skillPendingDeletion: ClaudeSkill?

    private var selectedSkill: ClaudeSkill? {
        filteredSkills.first { $0.id == selectedSkillID } ?? filteredSkills.first
    }

    private var isDirty: Bool {
        guard let selectedSkill else { return false }
        return draft != model.readSkill(selectedSkill)
    }

    var body: some View {
        AgentConsolePane(
            title: "スキル",
            subtitle: "Claude Code が読み込む skill（SKILL.md）を一覧・編集します。",
            toolbar: AnyView(toolbar),
            controls: AnyView(controls)
        ) {
            if filteredSkills.isEmpty {
                emptyState
            } else {
                editorLayout
                    .onAppear(perform: loadSelectedSkillIfNeeded)
                    .onChange(of: selectedSkillID) { _, _ in
                        loadedSkillID = nil
                        loadSelectedSkillIfNeeded()
                    }
                    .onChange(of: model.skills.map(\.id)) { _, _ in
                        if let selectedSkillID,
                           !model.skills.contains(where: { $0.id == selectedSkillID }) {
                            self.selectedSkillID = model.skills.first?.id
                            loadedSkillID = nil
                            loadSelectedSkillIfNeeded()
                        }
                    }
            }
        }
        .confirmationDialog(
            "スキルを削除しますか？",
            isPresented: Binding(
                get: { skillPendingDeletion != nil },
                set: { if !$0 { skillPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("ゴミ箱へ移す", role: .destructive) {
                guard let skill = skillPendingDeletion else { return }
                skillPendingDeletion = nil
                model.deleteSkill(skill)
                if selectedSkillID == skill.id {
                    selectedSkillID = nil
                    draft = ""
                    loadedSkillID = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                skillPendingDeletion = nil
            }
        } message: {
            if let skill = skillPendingDeletion {
                Text("「\(skill.name)」をゴミ箱へ移します。完全には削除されず、必要なら Finder から復元できます。")
            }
        }
    }

    // MARK: - 見出し右

    private var toolbar: some View {
        HStack(spacing: DSSpacing.s) {
            if isDirty {
                Text("未保存")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.statusAwaitingApproval)
            }
            Button("元に戻す") {
                loadedSkillID = nil
                loadSelectedSkillIfNeeded()
            }
            .buttonStyle(AgentConsoleActionButtonStyle())
            .disabled(!isDirty)

            Button("保存") {
                guard let selectedSkill else { return }
                model.writeSkill(draft, to: selectedSkill)
                loadedSkillID = selectedSkill.id
            }
            .buttonStyle(AgentConsoleActionButtonStyle(isProminent: true))
            .keyboardShortcut("s", modifiers: .command)
            .disabled(selectedSkill == nil || !isDirty)

            AgentConsoleIconButton(systemName: "arrow.clockwise", help: "再読み込み") {
                model.loadSkills()
                loadedSkillID = nil
                loadSelectedSkillIfNeeded()
            }
            .accessibilityIdentifier("ClaudeSkillsPane.reload")
        }
    }

    // MARK: - 見出し下

    private var controls: some View {
        HStack(spacing: DSSpacing.m) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: DSIconSize.m))
                    .foregroundStyle(DSColor.textTertiary)
                TextField("絞り込み", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DSFont.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DSIconSize.m))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .fill(DSColor.fillSubtle)
            }
            .frame(maxWidth: 220)
            .accessibilityIdentifier("ClaudeSkillsPane.search")

            Spacer(minLength: 0)
        }
    }

    // MARK: - 本文

    private var emptyState: some View {
        AgentConsoleEmptyState(
            symbolName: "books.vertical",
            message: searchText.isEmpty ? "skill が見つかりません。" : "該当する skill はありません。"
        )
        .agentConsoleScrollBody()
    }

    private var editorLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            skillList
                .frame(width: 320)
            Divider()
            skillEditor
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var skillList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                AgentConsoleGroupHeader(
                    title: "登録済み",
                    systemImage: "books.vertical.fill",
                    detail: countLabel(filteredSkills.count, of: model.skills.count)
                )
                ForEach(filteredSkills) { skill in
                    SkillRow(
                        skill: skill,
                        isSelected: selectedSkill?.id == skill.id,
                        onSelect: { selectedSkillID = skill.id },
                        onDelete: { skillPendingDeletion = skill }
                    )
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
        }
        .scrollContentBackground(.hidden)
    }

    private var skillEditor: some View {
        Group {
            if let selectedSkill {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    HStack(spacing: DSSpacing.s) {
                        Text(selectedSkill.displayPath)
                            .font(DSFont.monoCaption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button("削除") {
                            skillPendingDeletion = selectedSkill
                        }
                        .buttonStyle(AgentConsoleActionButtonStyle())
                        .accessibilityIdentifier("ClaudeSkillsPane.delete")
                    }
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.top, DSSpacing.s)

                    TextEditor(text: $draft)
                        .font(DSFont.mono)
                        .scrollContentBackground(.hidden)
                        .background(DSColor.background)
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.bottom, DSSpacing.s)
                        .accessibilityIdentifier("ClaudeSkillsPane.editor")
                }
            } else {
                AgentConsoleEmptyState(
                    symbolName: "doc.text",
                    message: "skill を選ぶと SKILL.md を編集できます。"
                )
            }
        }
    }

    private var filteredSkills: [ClaudeSkill] {
        guard !searchText.isEmpty else { return model.skills }
        return model.skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
                || $0.directoryName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func countLabel(_ shown: Int, of total: Int) -> String {
        shown == total ? "\(total) 件" : "\(shown) / \(total) 件"
    }

    private func loadSelectedSkillIfNeeded() {
        guard let selectedSkill, loadedSkillID != selectedSkill.id else { return }
        draft = model.readSkill(selectedSkill)
        loadedSkillID = selectedSkill.id
    }
}

// MARK: - 行

private struct SkillRow: View {
    let skill: ClaudeSkill
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            AgentConsoleCard(isHighlighted: isSelected) {
                HStack(alignment: .top, spacing: DSSpacing.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                            .fill(isSelected ? DSColor.accent.opacity(0.18) : DSColor.fillSubtle)
                            .frame(width: 32, height: 32)
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: DSIconSize.l, weight: .semibold))
                            .foregroundStyle(isSelected ? DSColor.accent : DSColor.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(skill.name)
                            .font(DSFont.body.weight(.medium))
                            .foregroundStyle(DSColor.textPrimary)
                        HStack(spacing: DSSpacing.xs) {
                            ClaudeSkillScopeChip(scope: skill.scope)
                            if skill.directoryName != skill.name {
                                AgentConsoleMetaChip(text: skill.directoryName)
                            }
                        }
                        if !skill.description.isEmpty {
                            Text(skill.description)
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: DSSpacing.s)
                }
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityIdentifier("ClaudeSkillsPane.row.\(skill.id)")
        .contextMenu {
            Button("削除", role: .destructive, action: onDelete)
        }
    }
}

/// user / project を色で見分けるチップ。
private struct ClaudeSkillScopeChip: View {
    let scope: AgentMemoryFile.Scope

    var body: some View {
        let tint = scope == .project ? DSColor.statusRunning : DSColor.textSecondary
        Text(scope.displayName)
            .font(DSFont.monoCaption)
            .foregroundStyle(tint)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, 1)
            .background(tint.opacity(0.14), in: Capsule(style: .continuous))
    }
}
