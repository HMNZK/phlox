import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import AgentDomain
import DesignSystem

struct DraggedSession: Codable, Transferable {
    let id: SessionID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// 複数セッションを分割ツリー（`PaneTree`）のとおりに並べる。
/// 旧 k×k 等分グリッド（`GridColumns` / `SessionGridArrangement`）は撤去した。
/// 等分でしか割れないモデルでは「左半分に1枚・右半分を上下に2枚」のような比率を表現できず、
/// 表現力の不足がそのまま UI の制約になっていたため。
public struct SessionGridView: View {
    let sessions: [SessionNode]
    let paneLayout: PaneTree
    let canvasSize: CGSize?
    let onViewportChange: (CGSize) -> Void
    let onLiveResizeChange: (Bool) -> Void
    @State private var windowReference = GridWindowReader.Reference()
    @Binding var focusedID: SessionID?
    let onRemove: (SessionNode) -> Void
    let onRename: (SessionNode) -> Void
    let onChangeWorkspace: (SessionViewModel) -> Void
    let onLayoutAction: (PaneLayoutAction) -> Void
    let projectNames: [ProjectID: String]
    let onRemoveFromGrid: (SessionNode) -> Void
    let onOpenSingle: (SessionID) -> Void
    let parentNames: [SessionID: String]
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    public init(
        sessions: [SessionNode],
        paneLayout: PaneTree,
        canvasSize: CGSize? = nil,
        onViewportChange: @escaping (CGSize) -> Void = { _ in },
        onLiveResizeChange: @escaping (Bool) -> Void = { _ in },
        focusedID: Binding<SessionID?>,
        onRemove: @escaping (SessionNode) -> Void,
        onRename: @escaping (SessionNode) -> Void,
        onChangeWorkspace: @escaping (SessionViewModel) -> Void,
        onLayoutAction: @escaping (PaneLayoutAction) -> Void,
        projectNames: [ProjectID: String] = [:],
        onRemoveFromGrid: @escaping (SessionNode) -> Void = { _ in },
        onOpenSingle: @escaping (SessionID) -> Void = { _ in },
        parentNames: [SessionID: String] = [:]
    ) {
        self.sessions = sessions
        self.paneLayout = paneLayout
        self.canvasSize = canvasSize
        self.onViewportChange = onViewportChange
        self.onLiveResizeChange = onLiveResizeChange
        self._focusedID = focusedID
        self.onRemove = onRemove
        self.onRename = onRename
        self.onChangeWorkspace = onChangeWorkspace
        self.onLayoutAction = onLayoutAction
        self.projectNames = projectNames
        self.onRemoveFromGrid = onRemoveFromGrid
        self.onOpenSingle = onOpenSingle
        self.parentNames = parentNames
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                PaneLayoutView(
                    sessions: sessions,
                    tree: paneLayout,
                    focusedID: $focusedID,
                    onRemove: onRemove,
                    onRename: onRename,
                    onChangeWorkspace: onChangeWorkspace,
                    onLayoutAction: onLayoutAction,
                    projectNames: projectNames,
                    onRemoveFromGrid: onRemoveFromGrid,
                    onOpenSingle: onOpenSingle,
                    parentNames: parentNames
                )
                .frame(width: canvasSize?.width ?? geometry.size.width, height: canvasSize?.height ?? geometry.size.height)
            }
            .onGeometryChange(for: CGSize.self, of: \.size, action: onViewportChange)
            .background(GridWindowReader { windowReference.window = $0 })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willStartLiveResizeNotification)) { notification in
                if let window = notification.object as? NSWindow, window === windowReference.window { onLiveResizeChange(true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { notification in
                if let window = notification.object as? NSWindow, window === windowReference.window { onLiveResizeChange(false) }
            }
            .onDisappear { onLiveResizeChange(false) }
        }
        // 上余白だけ詰めてトップバーとの隙間を無くす（左右下は通常マージン）。
        .padding(.horizontal, DSSpacing.s)
        .padding(.bottom, DSSpacing.s)
        .padding(.top, DSSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.gridAreaBackground)
    }
}

private struct GridWindowReader: NSViewRepresentable {
    final class Reference { weak var window: NSWindow? }
    let attach: (NSWindow) -> Void
    func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.attach = attach
        return view
    }
    func updateNSView(_ view: Reader, context: Context) { view.attach = attach }
    final class Reader: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { attach?(window) }
        }
    }
}
