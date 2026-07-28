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
    @Binding var focusedID: SessionID?
    let onRemove: (SessionNode) -> Void
    let onRename: (SessionNode) -> Void
    let onChangeWorkspace: (SessionViewModel) -> Void
    let onLayoutAction: (PaneLayoutAction) -> Void
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    public init(
        sessions: [SessionNode],
        paneLayout: PaneTree,
        focusedID: Binding<SessionID?>,
        onRemove: @escaping (SessionNode) -> Void,
        onRename: @escaping (SessionNode) -> Void,
        onChangeWorkspace: @escaping (SessionViewModel) -> Void,
        onLayoutAction: @escaping (PaneLayoutAction) -> Void
    ) {
        self.sessions = sessions
        self.paneLayout = paneLayout
        self._focusedID = focusedID
        self.onRemove = onRemove
        self.onRename = onRename
        self.onChangeWorkspace = onChangeWorkspace
        self.onLayoutAction = onLayoutAction
    }

    public var body: some View {
        PaneLayoutView(
            sessions: sessions,
            tree: paneLayout,
            focusedID: $focusedID,
            onRemove: onRemove,
            onRename: onRename,
            onChangeWorkspace: onChangeWorkspace,
            onLayoutAction: onLayoutAction
        )
        // 上余白だけ詰めてトップバーとの隙間を無くす（左右下は通常マージン）。
        .padding(.horizontal, DSSpacing.s)
        .padding(.bottom, DSSpacing.s)
        .padding(.top, DSSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
    }
}
