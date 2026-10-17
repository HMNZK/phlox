import SwiftUI

public enum GlassSurfaceRole: Sendable {
    case waitingBar
    case inputField
    case card
    case roundButton
}

private struct GlassSurfaceModifier: ViewModifier {
    let role: GlassSurfaceRole

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26, *) {
            switch role {
            case .roundButton:
                content
                    .frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
                    .glassEffect(.regular, in: glassShape)
            default:
                content.glassEffect(.regular, in: glassShape)
            }
        } else {
            legacySurface(content)
        }
#else
        legacySurface(content)
#endif
    }

    @ViewBuilder
    private func legacySurface(_ content: Content) -> some View {
        switch role {
        case .waitingBar:
            content.background(.regularMaterial, in: shape)
        case .inputField:
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(IOSColor.bg.separator, lineWidth: 1))
        case .card:
            content
                .background(IOSColor.bg.card, in: shape)
                .overlay(shape.stroke(IOSColor.bg.separator, lineWidth: 1))
        case .roundButton:
            content.frame(minWidth: DSTouch.minSize, minHeight: DSTouch.minSize)
        }
    }

    private var shape: AnyShape {
        switch role {
        case .waitingBar:
            AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .inputField:
            AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        case .card:
            AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .roundButton:
            AnyShape(Circle())
        }
    }

    private var glassShape: AnyShape {
        switch role {
        case .waitingBar:
            AnyShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        case .inputField:
            AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        case .card:
            AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        case .roundButton:
            AnyShape(Circle())
        }
    }
}

public extension View {
    /// 自前で描く操作面の iOS 26 ガラスと iOS 18 素材面を切り替える。
    func glassSurface(_ role: GlassSurfaceRole) -> some View {
        modifier(GlassSurfaceModifier(role: role))
    }
}
