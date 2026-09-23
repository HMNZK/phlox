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
    let projectNames: [ProjectID: String]
    /// 06: タイルの ✕・右クリックの「グリッドから外す」。
    let onRemoveFromGrid: (SessionNode) -> Void
    /// 06: 小さいタイルの「開く」（単体表示へ）。
    let onOpenSingle: (SessionID) -> Void
    /// 子セッションの親の名前（「↳ 親: …」）。
    let parentNames: [SessionID: String]
    let tileTabs: GridTileTabs?

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
        onLayoutAction: @escaping (PaneLayoutAction) -> Void,
        projectNames: [ProjectID: String] = [:],
        onRemoveFromGrid: @escaping (SessionNode) -> Void = { _ in },
        onOpenSingle: @escaping (SessionID) -> Void = { _ in },
        parentNames: [SessionID: String] = [:],
        tileTabs: GridTileTabs? = nil
    ) {
        self.sessions = sessions
        self.tree = tree
        self._focusedID = focusedID
        self.onRemove = onRemove
        self.onRename = onRename
        self.onChangeWorkspace = onChangeWorkspace
        self.onLayoutAction = onLayoutAction
        self.projectNames = projectNames
        self.onRemoveFromGrid = onRemoveFromGrid
        self.onOpenSingle = onOpenSingle
        self.parentNames = parentNames
        self.tileTabs = tileTabs
    }

    public var body: some View {
        GeometryReader { geometry in
            let spacing = DSSpacing.s
            let frames = tree.frames(in: geometry.size, spacing: spacing)
            // ⌘1–9 と見出しの番号（DashboardViewModel.gridTileOrder と同じ並び）。
            let numbers = Dictionary(uniqueKeysWithValues: tree.readingOrder().enumerated().map { ($1, $0 + 1) })

            ZStack(alignment: .topLeading) {
                // ①タイル。ツリーの入れ子ではなく「セッション ID → 矩形」の絶対配置。
                ForEach(frames.tiles, id: \.session) { tile in
                    if let session = sessions.first(where: { $0.id == tile.session }) {
                        PaneTileView(
                            session: session,
                            projectName: session.projectID.flatMap { projectNames[$0] },
                            size: tile.rect.size,
                            isFocused: focusedID == session.id,
                            number: numbers[session.id],
                            parentName: parentNames[session.id],
                            canRemoveFromGrid: frames.tiles.count > 1,
                            tileTabs: tileTabs,
                            onSelect: { focusedID = session.id },
                            onRemove: { onRemove(session) },
                            onRemoveFromGrid: { onRemoveFromGrid(session) },
                            onOpenSingle: { onOpenSingle(session.id) },
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
                    PaneDropIndicatorView(target: dropHighlight.target)
                        .frame(width: indicator.rect.width, height: indicator.rect.height)
                        .position(x: indicator.rect.midX, y: indicator.rect.midY)
                        .allowsHitTesting(false)
                    if let line = indicator.splitLine {
                        Rectangle()
                            .fill(DSColor.accent)
                            .frame(width: line.width, height: line.height)
                            .position(x: line.midX, y: line.midY)
                            .allowsHitTesting(false)
                    }
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
            // S8: ドラッグ中はドロップ位置の説明を下端に出す。
            .overlay(alignment: .bottom) {
                if dropHighlight != nil {
                    PaneDropLegend()
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                }
            }
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
    /// 分割して差し込むときの、新しい分割線の位置（S8「分割線の位置を線で先に見せる」）。
    var splitLine: CGRect? {
        guard rect.size != tileSize else { return nil }
        if rect.width < tileSize.width {
            return CGRect(x: tileOrigin.x + tileSize.width / 2 - 1, y: tileOrigin.y, width: 2, height: tileSize.height)
        }
        return CGRect(x: tileOrigin.x, y: tileOrigin.y + tileSize.height / 2 - 1, width: tileSize.width, height: 2)
    }
    private let tileOrigin: CGPoint
    private let tileSize: CGSize

    init(target: PaneDropTarget, in tile: CGRect) {
        tileOrigin = tile.origin
        tileSize = tile.size
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

/// 分割ツリー用のタイル（06）。見出しに状態の文字、対応待ちの 4 状態だけ見出しと内側の縁を状態の色にし、
/// フォーカスは accent の外輪で示す。本文は大きさで入れ替える（`GridTileSize`）。
/// ドロップは位置で「入れ替え / 分割して差し込む」を切り替えるため、位置を受け取れる `DropDelegate` を使う。
private struct PaneTileView: View {
    let session: SessionNode
    let projectName: String?
    /// タイルの矩形サイズ。ドロップ位置の判定に使う（`DropInfo.location` と同じ座標系）。
    let size: CGSize
    let isFocused: Bool
    let number: Int?
    let parentName: String?
    let canRemoveFromGrid: Bool
    let tileTabs: GridTileTabs?
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onRemoveFromGrid: () -> Void
    let onOpenSingle: () -> Void
    let onRename: () -> Void
    let onChangeWorkspace: () -> Void
    let onDropHighlightChange: (PaneDropTarget?) -> Void
    let onDrop: (_ moved: SessionID, _ target: PaneDropTarget) -> Void

    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale
    @State private var clickObserver: PaneTileClickObserver?
    @State private var clickFrameSource = PaneTileWindowFrameSource()

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
                RoundedRectangle(cornerRadius: 9)
                    .fill(DSColor.surfaceElevated)
            }
            .overlay { tileBorder }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .dsShadow(.gridTile)
            // フォーカスは状態の縁とは別の、外側の accent の輪（06 論点 4）。
            .overlay {
                if borderAppearance.showsFocusHighlight {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(DSColor.accent, lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .background {
                PaneTileWindowFrameReader { view in
                    clickFrameSource.update(view: view)
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                guard clickObserver == nil else { return }
                let observer = PaneTileClickObserver(
                    tileFrameInWindow: { [clickFrameSource] in clickFrameSource.frameInWindow },
                    tileWindow: { [clickFrameSource] in clickFrameSource.window },
                    isFocused: isFocused,
                    onSelect: onSelect
                )
                clickObserver = observer
                observer.start()
            }
            .onChange(of: isFocused) { _, focused in
                clickObserver?.update(isFocused: focused)
            }
            .onDisappear {
                clickObserver?.stop()
                clickObserver = nil
            }
            // 本文は TapGesture のみ。TerminalView / NSTextView の選択・スクロールを含む
            // AppKit のマウストラッキングへゼロ距離 DragGesture を渡さない。
            .simultaneousGesture(TapGesture().onEnded { onSelect() })
            .contextMenu { contextMenuContent }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var tileShell: some View {
        VStack(spacing: 0) {
            header
            if let parentName {
                GridTileParentRow(parentName: parentName)
            }
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
        case .appServer(let chat):
            let tab = tileTabs?.selected(session.id) ?? .conversation
            if tab != .conversation, let tileTabs, GridTileSize.showsChildTabs(size) {
                tileTabs.content(session.id, tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if GridTileSize.showsConversationColumn(size) {
                GridChatColumn(viewModel: chat, projectName: projectName, onFocusGained: onSelect)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                GridTileCompactBody(viewModel: chat, tileSize: size, onOpen: onOpenSingle)
                    .clipped()
            }
        }
    }

    /// サイドバーの行と同じ操作に「グリッドから外す」を足す（06 対応表）。「右に分割 / 下に分割」は置かない。
    @ViewBuilder
    private var contextMenuContent: some View {
        Button("グリッドから外す") { onRemoveFromGrid() }
            .disabled(!canRemoveFromGrid)
        Divider()
        Button("名前を変更") { onRename() }
        if session.pty != nil {
            Button("プロジェクトを変更") { onChangeWorkspace() }
        }
        Button("削除", role: .destructive) { onRemove() }
    }

    private var state: SessionDisplayState { session.gridDisplayState }

    private var borderAppearance: GridTileBorderAppearance {
        GridTileBorderPolicy.appearance(
            isFocused: isFocused,
            requiresAttention: state.attentionKind != nil,
            isDropTargeted: false
        )
    }

    /// 状態は内側の縁。対応待ちの 4 状態だけ状態の色、ほかは区切り線の色（太さで状態を分けない）。
    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 9)
            .strokeBorder(
                borderAppearance.showsAttention ? state.attentionKind.map { DSColor.attentionMark($0) } ?? DSColor.separator : DSColor.separator,
                lineWidth: borderAppearance.showsAttention ? 1.5 : 1
            )
    }

    private var accessibilityText: String {
        let elapsed = session.statusEnteredAt.map {
            SessionRelativeTime.label(from: $0, to: Date(), locale: locale)
        }
        return GridTileText.accessibilityLabel(
            title: session.displayName,
            state: state.localizedLabel(locale: locale),
            elapsed: elapsed,
            isFocused: isFocused,
            locale: locale
        )
    }

    private func selectImmediately() {
        guard !isFocused else { return }
        onSelect()
    }

    private var header: some View {
        GridTileHeader(
            session: session,
            tileSize: size,
            number: number,
            isInternal: session.launchContext == .orchestration,
            canRemoveFromGrid: canRemoveFromGrid,
            tabs: tileTabs,
            onRemoveFromGrid: onRemoveFromGrid,
            onSelect: onSelect
        )
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

/// ドロップ先の塗り（S8）。入れ替えはタイル全体を淡く、分割は差し込む側の半分を塗って説明を出す。
private struct PaneDropIndicatorView: View {
    let target: PaneDropTarget

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(DSColor.accent.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DSColor.accent, lineWidth: 2))
            .overlay {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSColor.accentInk)
            }
            .padding(4)
    }

    private var label: LocalizedStringKey {
        switch target {
        case .swap: "入れ替え"
        case .split(.leading): "左に分割して挿入"
        case .split(.trailing): "右に分割して挿入"
        case .split(.top): "上に分割して挿入"
        case .split(.bottom): "下に分割して挿入"
        }
    }
}

/// ドラッグ中の説明（S8）。
private struct PaneDropLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("ドロップ位置").fontWeight(.semibold).foregroundStyle(DSColor.textPrimary)
            Text("中央 = 入れ替え")
            Text("上下左右の端 = 50:50 で分割して挿入")
            Text("Esc = 取り消し")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(DSColor.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(DSColor.surfaceElevated, in: Capsule())
        .dsShadow(.popover)
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
