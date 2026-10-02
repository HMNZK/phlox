import Foundation

public enum SimulatorInputMapper {
    public static func displayRect(in bounds: CGRect, pixelSize: CGSize) -> CGRect? {
        guard bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
              pixelSize.width.isFinite, pixelSize.height.isFinite, pixelSize.width > 0, pixelSize.height > 0
        else { return nil }
        let scale = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// AppKitの左下原点から、縦向き端末の左上原点へ変換する。倍率はここでは扱わない。
    /// 画面内で始めた接触の移動・解放にはcontinuingTouchを渡し、余白の点を端へ寄せる。
    public static func normalizedPoint(
        _ point: CGPoint, in bounds: CGRect, pixelSize: CGSize,
        orientation: SimulatorOrientation, surfaceIsRotated: Bool, continuingTouch: Bool = false
    ) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite,
              let rect = displayRect(in: bounds, pixelSize: pixelSize),
              continuingTouch || (point.x >= rect.minX && point.x <= rect.maxX &&
                                  point.y >= rect.minY && point.y <= rect.maxY) else { return nil }
        let x = (min(max(point.x, rect.minX), rect.maxX) - rect.minX) / rect.width
        let y = (rect.maxY - min(max(point.y, rect.minY), rect.maxY)) / rect.height
        guard surfaceIsRotated else { return CGPoint(x: x, y: y) }
        switch orientation {
        case .portrait: return CGPoint(x: x, y: y)
        case .portraitUpsideDown: return CGPoint(x: 1 - x, y: 1 - y)
        case .landscapeLeft: return CGPoint(x: 1 - y, y: x)
        case .landscapeRight: return CGPoint(x: y, y: 1 - x)
        }
    }
}
