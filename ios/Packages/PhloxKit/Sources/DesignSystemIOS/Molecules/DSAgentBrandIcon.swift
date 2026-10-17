import AgentDomain
import DesignSystem
import SwiftUI

/// 共有ロゴを iOS の配色に合わせて表示する。
public struct DSAgentBrandIcon: View {
    public let kind: AgentKind
    public let size: CGFloat

    public init(kind: AgentKind, size: CGFloat) {
        self.kind = kind
        self.size = size
    }

    @ViewBuilder
    public var body: some View {
        if kind == .cursor {
            AgentBrandIcon(kind: kind, size: size)
                // Cursor のロゴは黒い背景を含むため、暗色面でも外形を識別できるようにする。
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.239, style: .continuous)
                        .stroke(IOSColor.bg.separator, lineWidth: 1)
                }
        } else {
            AgentBrandIcon(kind: kind, size: size)
        }
    }
}
