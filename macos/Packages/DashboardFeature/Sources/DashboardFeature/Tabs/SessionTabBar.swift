import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// 上段のプロジェクトタブ。並びはサイドバーの `viewModel.projects` と同じ。
struct SessionTabBar: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter

    private var selectedProjectID: ProjectID? {
        router.selectedProjectID ?? router.selectedSession.flatMap { viewModel.sessionNode(id: $0)?.projectID }
    }

    var body: some View {
        GeometryReader { geometry in
            let selectedIndex = selectedProjectID.flatMap { id in viewModel.projects.firstIndex { $0.id == id } }
            let layout = TabBarOverflowLayout.make(
                itemCount: viewModel.projects.count,
                selectedIndex: selectedIndex,
                availableWidth: max(0, geometry.size.width - 12),
                maxItemWidth: 180,
                minItemWidth: 96,
                addButtonWidth: 30,
                overflowButtonWidth: 70
            )
            HStack(spacing: 0) {
                ForEach(layout.visibleIndices, id: \.self) { index in
                    let project = viewModel.projects[index]
                    ProjectTabButton(
                        project: project,
                        isSelected: project.id == selectedProjectID,
                        onSelect: { router.selectProjectFromSidebar(project.id) },
                        onClose: { _ = router.requestClose(.project(project.id)) },
                        onRename: { rename(project.id) }
                    )
                    .frame(width: layout.itemWidth, height: 30)
                    .offset(y: 1)
                    .accessibilityIdentifier(TabAccessibilityIdentifier.project(index + 1))
                }
                if layout.overflowCount > 0 {
                    let hidden = hiddenProjects(in: layout)
                    SelectablePopoverButton(
                        options: hidden.map { project in
                            SelectablePopoverOption(
                                id: project.id.description,
                                value: project.id.description,
                                title: project.name,
                                isSelected: project.id == selectedProjectID
                            )
                        },
                        selectedID: selectedProjectID?.description,
                        accessibilityLabel: "ほか \(layout.overflowCount)",
                        accessibilityValue: "",
                        accessibilityIdentifier: TabAccessibilityIdentifier.overflow,
                        help: "ほかのタブ",
                        width: 248,
                        onSelect: { option in
                            if let project = hidden.first(where: { $0.id.description == option.id }) {
                                router.selectProjectFromSidebar(project.id)
                            }
                        }
                    ) { _ in
                        (Text("ほか \(layout.overflowCount)") + Text(verbatim: " ⌄"))
                            .font(DSFont.auxiliary)
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(width: 70, height: 26)
                            .contentShape(Rectangle())
                    }
                }
                projectAddButton
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: DSLayout.tabBarHeight)
        .background(DSColor.tabBarBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("プロジェクトのタブ"))
    }

    private var projectAddButton: some View {
        Button { router.addProjectRequested = true } label: {
            Image(systemName: "plus")
                .font(.system(size: DSIconSize.m, weight: .regular))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .padding(.leading, 4)
        .padding(.vertical, 4)
        .help(Text("プロジェクトを追加"))
        .accessibilityLabel(Text("プロジェクトを追加"))
        .accessibilityIdentifier(TabAccessibilityIdentifier.projectAdd)
    }

    private func hiddenProjects(in layout: TabBarOverflowLayout) -> [Project] {
        let visible = Set(layout.visibleIndices)
        return viewModel.projects.enumerated().compactMap { index, project in visible.contains(index) ? nil : project }
    }

    private func rename(_ id: ProjectID) {
        let isShowing = router.sidebarVisible && (!router.sidebarLacksRoom || router.sidebarPeeking)
        if !isShowing { router.toggleSidebar() }
        router.projectRenameRequest = id
    }
}

/// 画面に入る範囲でタブを縮め、最小幅でも入らない項目を overflow にまとめる。
struct TabBarOverflowLayout: Equatable {
    let visibleIndices: [Int]
    let itemWidth: CGFloat
    let overflowCount: Int
    private let itemWidths: [CGFloat]

    init(visibleIndices: [Int], itemWidth: CGFloat, overflowCount: Int, itemWidths: [CGFloat] = []) {
        self.visibleIndices = visibleIndices
        self.itemWidth = itemWidth
        self.overflowCount = overflowCount
        self.itemWidths = itemWidths
    }

    func width(for index: Int) -> CGFloat {
        itemWidths.indices.contains(index) ? itemWidths[index] : itemWidth
    }

    static func make(
        itemCount: Int,
        selectedIndex: Int?,
        availableWidth: CGFloat,
        maxItemWidth: CGFloat,
        minItemWidth: CGFloat,
        addButtonWidth: CGFloat,
        overflowButtonWidth: CGFloat
    ) -> Self {
        guard itemCount > 0 else { return Self(visibleIndices: [], itemWidth: 0, overflowCount: 0) }

        let widthWithoutOverflow = max(0, availableWidth - addButtonWidth)
        let fullWidth = widthWithoutOverflow / CGFloat(itemCount)
        if fullWidth >= minItemWidth {
            return Self(
                visibleIndices: Array(0..<itemCount),
                itemWidth: min(maxItemWidth, fullWidth),
                overflowCount: 0
            )
        }
        if itemCount == 1 {
            return Self(visibleIndices: [0], itemWidth: widthWithoutOverflow, overflowCount: 0)
        }

        for visibleCount in stride(from: itemCount - 1, through: 1, by: -1) {
            let width = max(0, availableWidth - addButtonWidth - overflowButtonWidth) / CGFloat(visibleCount)
            guard width >= minItemWidth else { continue }
            var indices = Array(0..<visibleCount)
            if let selectedIndex, (0..<itemCount).contains(selectedIndex), !indices.contains(selectedIndex) {
                indices[visibleCount - 1] = selectedIndex
                indices.sort()
            }
            return Self(visibleIndices: indices, itemWidth: min(maxItemWidth, width), overflowCount: itemCount - visibleCount)
        }

        let selected = selectedIndex.flatMap { (0..<itemCount).contains($0) ? $0 : nil } ?? 0
        let width = max(0, availableWidth - addButtonWidth - overflowButtonWidth)
        return Self(visibleIndices: [selected], itemWidth: width, overflowCount: itemCount - 1)
    }

    static func make(
        contentWidths: [CGFloat],
        selectedIndex: Int?,
        availableWidth: CGFloat,
        maxItemWidth: CGFloat,
        addButtonWidth: CGFloat,
        overflowButtonWidth: CGFloat
    ) -> Self {
        guard !contentWidths.isEmpty else { return Self(visibleIndices: [], itemWidth: 0, overflowCount: 0) }

        var widths = contentWidths.map { min(max(0, $0), maxItemWidth) }
        let allIndices = Array(widths.indices)
        if widths.reduce(addButtonWidth, +) <= availableWidth {
            return Self(visibleIndices: allIndices, itemWidth: 0, overflowCount: 0, itemWidths: widths)
        }

        let selected = selectedIndex.flatMap { widths.indices.contains($0) ? $0 : nil } ?? 0
        var visible = Array(Set([0, selected])).sorted()
        let itemsWidth = max(0, availableWidth - addButtonWidth - overflowButtonWidth)
        let visibleWidth = visible.reduce(CGFloat.zero, { $0 + widths[$1] })
        if visibleWidth > itemsWidth {
            visible = [selected]
            widths[selected] = min(widths[selected], itemsWidth)
        } else {
            for index in allIndices where !visible.contains(index) {
                let nextWidth = visible.reduce(CGFloat.zero, { $0 + widths[$1] }) + widths[index]
                guard nextWidth <= itemsWidth else { break }
                visible.append(index)
            }
            visible.sort()
        }
        return Self(
            visibleIndices: visible,
            itemWidth: 0,
            overflowCount: widths.count - visible.count,
            itemWidths: widths
        )
    }
}

enum TabAccessibilityIdentifier {
    static func project(_ index: Int) -> String { "tabs.project.\(index)" }
    static let projectAdd = "tabs.project.add"
    static func item(_ index: Int) -> String { "tabs.item.\(index)" }
    static let itemAdd = "tabs.item.add"
    static let overflow = "tabs.overflow"
}

private struct ProjectTabButton: View {
    let project: Project
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            Text(verbatim: project.name)
                .font(DSFont.auxiliary.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 28)
                .background(
                    isSelected ? DSColor.windowBackground : (isHovering ? DSColor.fillSubtle : .clear),
                    in: RoundedRectangle(cornerRadius: DSRadius.row)
                )
                .overlay(alignment: .top) {
                    if isSelected { Rectangle().fill(DSColor.separator).frame(height: 1) }
                }
                .overlay(alignment: .leading) {
                    if isSelected { Rectangle().fill(DSColor.separator).frame(width: 1) }
                }
                .overlay(alignment: .trailing) {
                    if isSelected { Rectangle().fill(DSColor.separator).frame(width: 1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if isSelected || isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverableIconButtonStyle())
                .help(Text("プロジェクトを削除…"))
                .accessibilityLabel(Text("プロジェクトを削除…"))
            }
        }
        // ✕ に乗ってもホバー中のままにする（タブのボタンだけに付けると、✕ へ移った時点で ✕ が消えて押せない）。
        .onHover { isHovering = $0 }
        .help(Text(verbatim: project.name))
        .contextMenu {
            Button("プロジェクト名を変更…", action: onRename)
        }
        .accessibilityLabel(Text(verbatim: project.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
