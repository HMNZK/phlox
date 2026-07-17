import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import AgentDomain
import DesignSystem
import TerminalUI

struct DraggedSession: Codable, Transferable {
    let id: SessionID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// 複数セッションを画面いっぱいに等分割で並べる。
/// auto モードは従来の可変行列、固定モードは空きマスを含む k×k 盤として描画する。
public struct SessionGridView: View {
    let sessions: [SessionNode]
    let gridColumns: GridColumns
    let arrangement: SessionGridArrangement?
    @Binding var focusedID: SessionID?
    let onRemove: (SessionNode) -> Void
    let onRename: (SessionNode) -> Void
    let onChangeWorkspace: (SessionViewModel) -> Void
    let onReorder: (_ moved: SessionID, _ target: SessionID) -> Void
    let onGridAction: (SessionGridAction) -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    public init(
        sessions: [SessionNode],
        gridColumns: GridColumns,
        arrangement: SessionGridArrangement?,
        focusedID: Binding<SessionID?>,
        onRemove: @escaping (SessionNode) -> Void,
        onRename: @escaping (SessionNode) -> Void,
        onChangeWorkspace: @escaping (SessionViewModel) -> Void,
        onReorder: @escaping (_ moved: SessionID, _ target: SessionID) -> Void,
        onGridAction: @escaping (SessionGridAction) -> Void
    ) {
        self.sessions = sessions
        self.gridColumns = gridColumns
        self.arrangement = arrangement
        self._focusedID = focusedID
        self.onRemove = onRemove
        self.onRename = onRename
        self.onChangeWorkspace = onChangeWorkspace
        self.onReorder = onReorder
        self.onGridAction = onGridAction
    }

    private var dimensions: (cols: Int, rows: Int) {
        sessionGridDimensions(columns: gridColumns, sessionCount: sessions.count)
    }

    /// 行 row に実在するセッションの index 配列。末尾行がコマ不足のときは、その行の
    /// タイルが maxWidth:.infinity で横いっぱいに広がる（旧実装の Color.clear 空セルを
    /// 置かない）。これにより 3 セッション時などに右下へ「壊れて見える」空白象限を残さない。
    private func rowSessionIndices(row: Int, cols: Int) -> [Int] {
        let start = row * cols
        let end = min(start + cols, sessions.count)
        return start < end ? Array(start..<end) : []
    }

    public var body: some View {
        gridContent
            // 上余白だけ詰めてトップバーとの隙間を無くす（左右下は通常マージン）。
            .padding(.horizontal, DSSpacing.s)
            .padding(.bottom, DSSpacing.s)
            .padding(.top, DSSpacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.background)
    }

    @ViewBuilder
    private var gridContent: some View {
        if let arrangement {
            fixedGrid(arrangement: arrangement)
        } else {
            autoGrid
        }
    }

    private var autoGrid: some View {
        let dims = dimensions
        return VStack(spacing: DSSpacing.s) {
            ForEach(0..<dims.rows, id: \.self) { row in
                HStack(spacing: DSSpacing.s) {
                    ForEach(rowSessionIndices(row: row, cols: dims.cols), id: \.self) { index in
                        let session = sessions[index]
                        SessionGridTile(
                            session: session,
                            isFocused: focusedID == session.id,
                            onSelect: { focusedID = session.id },
                            onRemove: { onRemove(session) },
                            onRename: { onRename(session) },
                            onChangeWorkspace: {
                                if let pty = session.pty {
                                    onChangeWorkspace(pty)
                                }
                            },
                            onDrop: { moved in
                                guard moved != session.id else { return false }
                                onReorder(moved, session.id)
                                return true
                            },
                            fixedGridMenuActions: nil
                        )
                        // grid 構造 (cols/rows) が変わるとき、同じ index でも中身の
                        // session が入れ替わる。SwiftUI が view 再利用すると内部の
                        // NSViewRepresentable が同じ coordinator.hostingView を別
                        // SwiftUI parent で扱おうとして attach 競合し、空白タイルが
                        // 発生するため、session.id でビュー identity を固定する。
                        .id(session.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fixedGrid(arrangement: SessionGridArrangement) -> some View {
        GeometryReader { geometry in
            let spacing = DSSpacing.s
            let frames = sessionGridCellFrames(
                size: arrangement.size,
                bounds: geometry.size,
                spacing: spacing
            )

            ZStack(alignment: .topLeading) {
                ForEach(0..<frames.count, id: \.self) { cell in
                    if let placement = arrangement.placement(at: cell) {
                        if placement.region.anchor == cell,
                           let session = sessions.first(where: { $0.id == placement.id }) {
                            let frame = sessionGridRegionRect(
                                region: placement.region,
                                size: arrangement.size,
                                bounds: geometry.size,
                                spacing: spacing
                            )
                            SessionGridTile(
                                session: session,
                                isFocused: focusedID == session.id,
                                onSelect: { focusedID = session.id },
                                onRemove: { onRemove(session) },
                                onRename: { onRename(session) },
                                onChangeWorkspace: {
                                    if let pty = session.pty {
                                        onChangeWorkspace(pty)
                                    }
                                },
                                onDrop: { moved in
                                    guard moved != session.id else { return false }
                                    onGridAction(.swap(moved, session.id))
                                    return true
                                },
                                fixedGridMenuActions: FixedGridMenuActions(
                                    canMergeRight: arrangement.canMergeRight(session.id),
                                    canMergeDown: arrangement.canMergeDown(session.id),
                                    canUnmerge: placement.region.rowSpan > 1 || placement.region.colSpan > 1,
                                    onMergeRight: { onGridAction(.mergeRight(session.id)) },
                                    onMergeDown: { onGridAction(.mergeDown(session.id)) },
                                    onUnmerge: { onGridAction(.unmerge(session.id)) }
                                )
                            )
                            .id(session.id)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                        }
                    } else {
                        EmptySessionGridCell(
                            cell: cell,
                            onDrop: { moved in
                                onGridAction(.moveToCell(moved, cell: cell))
                            }
                        )
                        .frame(width: frames[cell].width, height: frames[cell].height)
                        .position(x: frames[cell].midX, y: frames[cell].midY)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct FixedGridMenuActions {
    let canMergeRight: Bool
    let canMergeDown: Bool
    let canUnmerge: Bool
    let onMergeRight: () -> Void
    let onMergeDown: () -> Void
    let onUnmerge: () -> Void
}

private struct SessionGridTile: View {
    let session: SessionNode
    @State private var isDropTargeted = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    let isFocused: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onRename: () -> Void
    let onChangeWorkspace: () -> Void
    let onDrop: (_ moved: SessionID) -> Bool
    let fixedGridMenuActions: FixedGridMenuActions?

    var body: some View {
        tileShell
            .dropDestination(
                for: DraggedSession.self,
                action: { items, _ in
                    guard let moved = items.first?.id else { return false }
                    return onDrop(moved)
                },
                isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isDropTargeted = targeted
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.m)
                    .fill(tileBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.m)
                    .fill(DSColor.fillSelected)
                    .opacity(isDropTargeted ? 1 : 0)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m)
                    .strokeBorder(tileBorderColor, lineWidth: tileBorderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
            .dsShadow(.gridTile)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { onSelect() })
            .contextMenu { contextMenuContent }
    }

    private var tileShell: some View {
        VStack(spacing: 0) {
            header
            tileContent
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        switch session {
        case .pty(let session):
            TerminalView(coordinator: session.terminalCoordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        case .appServer(let session):
            GridChatColumn(viewModel: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("名前を変更") { onRename() }
        if session.pty != nil {
            Button("プロジェクトを変更") { onChangeWorkspace() }
        }
        Button("削除", role: .destructive) { onRemove() }
        if let fixedGridMenuActions {
            Divider()
            Button("右のマスと結合") { fixedGridMenuActions.onMergeRight() }
                .disabled(!fixedGridMenuActions.canMergeRight)
            Button("下のマスと結合") { fixedGridMenuActions.onMergeDown() }
                .disabled(!fixedGridMenuActions.canMergeDown)
            if fixedGridMenuActions.canUnmerge {
                Button("結合を解除") { fixedGridMenuActions.onUnmerge() }
            }
        }
    }

    private var tileBackground: Color {
        session.hasUnseenCompletion ? DSColor.stoppedHighlightGrid : DSColor.surfaceElevated
    }

    private var tileBorderColor: Color {
        if isDropTargeted {
            return Color.white.opacity(0.35)
        }
        // 未確認の停止（完了/承認待ち/エラー等でユーザーの番になった）は赤枠で強く示す。
        // クリック選択で markCompletionSeen が走ってラッチが解除され、通常の選択枠へ戻る。
        if session.hasUnseenCompletion {
            return DSColor.stoppedHighlightGridBorder
        }
        // フォーカス時のみ 100%、非フォーカスは 40% へ落として
        // どのタイルがアクティブかを一目で分かるようにする。
        return isFocused ? DSColor.textSecondary : DSColor.textSecondary.opacity(0.4)
    }

    private var tileBorderWidth: CGFloat {
        if isDropTargeted {
            return 2
        }
        if session.hasUnseenCompletion {
            return 3
        }
        return isFocused ? 2 : 1
    }

    private var header: some View {
        HStack(spacing: DSSpacing.s) {
            AgentSessionIcon(descriptor: session.agentDescriptor, status: session.status, size: 24)
            StatusDot(status: session.status)
            Text(session.displayName)
                .font(DSFont.heroTitle)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if !session.workspaceName.isEmpty {
                Text(session.workspaceName)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help("セッションを閉じる")
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.clear)
        .help(session.workspacePath)
        .draggable(DraggedSession(id: session.id)) {
            Text(session.displayName)
                .font(DSFont.heroTitle)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.s)
                .padding(.vertical, DSSpacing.xs)
        }
    }
}

private struct EmptySessionGridCell: View {
    let cell: Int
    let onDrop: (SessionID) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: DSRadius.m)
            .fill(DSColor.surfaceElevated.opacity(isDropTargeted ? 0.35 : 0.08))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.m)
                    .strokeBorder(
                        DSColor.textSecondary.opacity(isDropTargeted ? 0.5 : 0.18),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5, 5])
                    )
            }
            .contentShape(Rectangle())
            .dropDestination(
                for: DraggedSession.self,
                action: { items, _ in
                    guard let moved = items.first?.id else { return false }
                    onDrop(moved)
                    return true
                },
                isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isDropTargeted = targeted
                    }
                }
            )
            .accessibilityLabel("空のグリッドセル \(cell + 1)")
    }
}
