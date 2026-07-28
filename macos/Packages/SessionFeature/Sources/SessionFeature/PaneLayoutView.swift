import SwiftUI
import UniformTypeIdentifiers
import AgentDomain
import DesignSystem
import TerminalUI

/// 分割ツリー（`PaneTree`）を描くビュー。
///
/// **描画はフラットな ZStack ＋ 絶対配置**（D3）。ツリーは `frames(in:spacing:)` で矩形を
/// 計算するためだけに使い、`HStack` / `VStack` の入れ子には**しない**。入れ子にすると
/// レイアウトを変えるたびにタイルのビュー階層上の位置が変わり、`NSViewRepresentable` の
/// `coordinator.hostingView` が別の SwiftUI parent へ attach され直してタイルが空白になる
/// （`SessionGridView.autoGrid` に同じ理由のコメントがある）。同じ理由でタイルには
/// `.id(session.id)` を付け、レイアウトが変わってもビュー identity を保つ。
///
/// 重ね順は「タイル → ドロップのインジケータ → 分割線ハンドル」。後ろの要素ほど前面に来る。
/// `.pty` タイルの中身は AppKit の `NSView`（SwiftTerm）で、`.overlay` で重ねたものは
/// その裏に隠れて操作を受け取れないため、掴みしろとインジケータは ZStack の後ろ側へ置く。
public struct PaneLayoutView: View {
    /// D12: 分割線ドラッグのクランプに使う最小ペイン長。ヘッダー・transcript・composer が
    /// 最低限収まる目安（実機確認で調整しうる暫定値）。
    static let minimumPaneWidth: CGFloat = 240
    static let minimumPaneHeight: CGFloat = 160

    let sessions: [SessionNode]
    let tree: PaneTree
    @Binding var focusedID: SessionID?
    let onRemove: (SessionNode) -> Void
    let onRename: (SessionNode) -> Void
    let onChangeWorkspace: (SessionViewModel) -> Void
    let onLayoutAction: (PaneLayoutAction) -> Void

    /// ドロップ中に出すインジケータ（どのタイルの・どの操作か）。ドロップの判定そのものは
    /// `PaneDropZone` が持ち、ここはその結果を描くためだけに保持する。
    @State private var dropHighlight: PaneDropHighlight?

    public init(
        sessions: [SessionNode],
        tree: PaneTree,
        focusedID: Binding<SessionID?>,
        onRemove: @escaping (SessionNode) -> Void,
        onRename: @escaping (SessionNode) -> Void,
        onChangeWorkspace: @escaping (SessionViewModel) -> Void,
        onLayoutAction: @escaping (PaneLayoutAction) -> Void
    ) {
        self.sessions = sessions
        self.tree = tree
        self._focusedID = focusedID
        self.onRemove = onRemove
        self.onRename = onRename
        self.onChangeWorkspace = onChangeWorkspace
        self.onLayoutAction = onLayoutAction
    }

    public var body: some View {
        GeometryReader { geometry in
            let spacing = DSSpacing.s
            let frames = tree.frames(in: geometry.size, spacing: spacing)

            ZStack(alignment: .topLeading) {
                // ①タイル。ツリーの入れ子ではなく「セッション ID → 矩形」の絶対配置。
                ForEach(frames.tiles, id: \.session) { tile in
                    if let session = sessions.first(where: { $0.id == tile.session }) {
                        PaneTileView(
                            session: session,
                            size: tile.rect.size,
                            isFocused: focusedID == session.id,
                            onSelect: { focusedID = session.id },
                            onRemove: { onRemove(session) },
                            onRename: { onRename(session) },
                            onChangeWorkspace: {
                                if let pty = session.pty {
                                    onChangeWorkspace(pty)
                                }
                            },
                            onDropHighlightChange: { target in
                                updateDropHighlight(target, on: tile.session)
                            },
                            onDrop: { moved, target in
                                dropHighlight = nil
                                perform(target, moved: moved, onto: tile.session)
                            }
                        )
                        .id(session.id)
                        .frame(width: tile.rect.width, height: tile.rect.height)
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                    }
                }

                // ②ドロップのインジケータ。タイル（AppKit の NSView を含む）より後に置く。
                if let dropHighlight,
                   let rect = frames.tiles.first(where: { $0.session == dropHighlight.session })?.rect {
                    let indicator = PaneDropIndicator(target: dropHighlight.target, in: rect)
                    RoundedRectangle(cornerRadius: DSRadius.m)
                        .fill(DSColor.fillSelected.opacity(0.55))
                        .frame(width: indicator.rect.width, height: indicator.rect.height)
                        .position(x: indicator.rect.midX, y: indicator.rect.midY)
                        .allowsHitTesting(false)
                }

                // ③分割線ハンドル。最前面に置かないと `.pty` タイルの境界で掴めない。
                ForEach(frames.dividers, id: \.id) { divider in
                    PaneDividerHandleView(
                        divider: divider,
                        minimumPaneWidth: PaneLayoutView.minimumPaneWidth,
                        minimumPaneHeight: PaneLayoutView.minimumPaneHeight,
                        onLayoutAction: onLayoutAction
                    )
                    .frame(width: divider.rect.width, height: divider.rect.height)
                    .position(x: divider.rect.midX, y: divider.rect.midY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// インジケータの更新。値が変わったときだけ `@State` を書く（ドロップのホバーは
    /// マウス移動のたびに届くため、素直に代入するとレイアウト全体の body が毎フレーム走る）。
    private func updateDropHighlight(_ target: PaneDropTarget?, on session: SessionID) {
        guard let target else {
            // 隣のタイルへ移ったあとに古いタイルの離脱が届くことがある。
            // 自分が出しているインジケータのときだけ消す（次のタイルの表示を巻き込まない）。
            if dropHighlight?.session == session {
                dropHighlight = nil
            }
            return
        }
        let next = PaneDropHighlight(session: session, target: target)
        guard dropHighlight != next else { return }
        dropHighlight = next
    }

    /// ドロップ判定（`PaneDropZone` の結果）を操作へ写す。閾値はここには無い。
    private func perform(_ target: PaneDropTarget, moved: SessionID, onto session: SessionID) {
        guard moved != session else { return }
        switch target {
        case .swap:
            onLayoutAction(.swap(moved, session))
        case .split(let edge):
            onLayoutAction(.insertBySplitting(session: moved, target: session, edge: edge))
        }
    }
}

/// 出しているインジケータの対象。
private struct PaneDropHighlight: Equatable {
    let session: SessionID
    let target: PaneDropTarget
}

/// インジケータの矩形。`.split` は差し込み後に新しいペインが占める側（半分）を示す
/// （`PaneTree.inserting` が既存ペインを 50:50 で分けるため、見た目と結果が一致する）。
private struct PaneDropIndicator {
    let rect: CGRect

    init(target: PaneDropTarget, in tile: CGRect) {
        switch target {
        case .swap:
            rect = tile
        case .split(.leading):
            rect = CGRect(x: tile.minX, y: tile.minY, width: tile.width / 2, height: tile.height)
        case .split(.trailing):
            rect = CGRect(x: tile.midX, y: tile.minY, width: tile.width / 2, height: tile.height)
        case .split(.top):
            rect = CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height / 2)
        case .split(.bottom):
            rect = CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2)
        }
    }
}

// MARK: - タイル

/// 分割ツリー用のタイル。旧グリッドの `SessionGridTile` と見た目は揃えつつ、
/// ドロップだけが違う——位置で「入れ替え / 分割して差し込む」を切り替えるため、
/// 位置を受け取れる `DropDelegate` を使う（旧タイルの `dropDestination` は位置を渡さない）。
private struct PaneTileView: View {
    let session: SessionNode
    /// タイルの矩形サイズ。ドロップ位置の判定に使う（`DropInfo.location` と同じ座標系）。
    let size: CGSize
    let isFocused: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onRename: () -> Void
    let onChangeWorkspace: () -> Void
    let onDropHighlightChange: (PaneDropTarget?) -> Void
    let onDrop: (_ moved: SessionID, _ target: PaneDropTarget) -> Void

    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        tileShell
            .onDrop(
                of: [.json],
                delegate: PaneTileDropDelegate(
                    size: size,
                    onHighlightChange: onDropHighlightChange,
                    onDrop: onDrop
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.m)
                    .fill(tileBackground)
            }
            .overlay { tileBorder }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
            .dsShadow(.gridTile)
            .contentShape(Rectangle())
            // 本文は TapGesture のみ。TerminalView / NSTextView の選択・スクロールを含む
            // AppKit のマウストラッキングへゼロ距離 DragGesture を渡さない。
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
            GridChatColumn(viewModel: session, onFocusGained: onSelect)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    /// 「右に分割 / 下に分割」は置かない（分割は既存セッションの移動でだけ起きる）。
    @ViewBuilder
    private var contextMenuContent: some View {
        Button("名前を変更") { onRename() }
        if session.pty != nil {
            Button("プロジェクトを変更") { onChangeWorkspace() }
        }
        Button("削除", role: .destructive) { onRemove() }
    }

    private var requiresAttention: Bool {
        SessionAttentionPolicy.requiresAttention(
            status: session.status,
            hasUnseenCompletion: session.hasUnseenCompletion
        )
    }

    private var tileBackground: Color {
        requiresAttention ? DSColor.stoppedHighlightGrid : DSColor.surfaceElevated
    }

    private var borderAppearance: GridTileBorderAppearance {
        GridTileBorderPolicy.appearance(
            isFocused: isFocused,
            requiresAttention: requiresAttention,
            isDropTargeted: false
        )
    }

    @ViewBuilder
    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: DSRadius.m)
            .strokeBorder(tileBorderColor, lineWidth: tileBorderWidth)

        // 注意喚起は太い赤の外枠で維持し、選択中だけ内側に独立したリングを重ねる。
        if borderAppearance.showsAttention, borderAppearance.showsFocusHighlight {
            RoundedRectangle(cornerRadius: DSRadius.m - 4)
                .strokeBorder(DSColor.textSecondary, lineWidth: 2)
                .padding(4)
        }
    }

    private var tileBorderColor: Color {
        if borderAppearance.showsAttention {
            return DSColor.stoppedHighlightGridBorder
        }
        return borderAppearance.showsFocusHighlight
            ? DSColor.textSecondary
            : DSColor.textSecondary.opacity(0.4)
    }

    private var tileBorderWidth: CGFloat {
        if borderAppearance.showsAttention { return 3 }
        return borderAppearance.showsFocusHighlight ? 2 : 1
    }

    private func selectImmediately() {
        guard !isFocused else { return }
        onSelect()
    }

    private var header: some View {
        HStack(spacing: DSSpacing.s) {
            StatusDot(status: session.status)
            AgentSessionIcon(descriptor: session.agentDescriptor, status: session.status, size: 24)
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
        .contentShape(Rectangle())
        .help(session.workspacePath)
        .draggable(DraggedSession(id: session.id)) {
            Text(session.displayName)
                .font(DSFont.heroTitle)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.s)
                .padding(.vertical, DSSpacing.xs)
        }
        // ヘッダーはテキスト選択・スクロールを持たないため、mouseDown 時点で選択する。
        // **`.draggable` より後に適用すること**。先に適用するとゼロ距離の DragGesture が
        // マウスダウンを取り切ってしまい、`.draggable` のドラッグセッションが一切開始しない
        // （最小の SwiftUI アプリで A/B 実測。順序を入れ替えるだけで開始する）。
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in selectImmediately() }
        )
    }
}

/// タイルへのドロップ。判定は必ず `PaneDropZone.target(for:in:)` を通す——
/// インジケータ（ホバー中）と実際に起きる操作（ドロップ時）が同じ関数から出るので、
/// 見た目と結果がずれない。ビュー側に端の閾値は書かない。
private struct PaneTileDropDelegate: DropDelegate {
    let size: CGSize
    let onHighlightChange: (PaneDropTarget?) -> Void
    let onDrop: (_ moved: SessionID, _ target: PaneDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.json])
    }

    func dropEntered(info: DropInfo) {
        onHighlightChange(PaneDropZone.target(for: info.location, in: size))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHighlightChange(PaneDropZone.target(for: info.location, in: size))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onHighlightChange(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = PaneDropZone.target(for: info.location, in: size)
        onHighlightChange(nil)
        guard let provider = info.itemProviders(for: [.json]).first else { return false }
        // ドラッグ中の荷物は非同期にしか取り出せない。取り出せた時点で操作を1回だけ流す。
        Task {
            guard let dragged = await Self.loadDraggedSession(from: provider) else { return }
            onDrop(dragged.id, target)
        }
        return true
    }

    private static func loadDraggedSession(from provider: NSItemProvider) async -> DraggedSession? {
        await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: DraggedSession.self) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }
}
