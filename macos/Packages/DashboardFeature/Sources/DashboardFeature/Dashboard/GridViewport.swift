import AppKit
import Observation
import SwiftUI

@MainActor @Observable
public final class GridViewport {
    public private(set) var size = CGSize(width: 540, height: 440)
    @ObservationIgnored private var pendingSize = CGSize(width: 540, height: 440)
    @ObservationIgnored private var isLiveResizing = false

    public init() {}

    public func update(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        pendingSize = size
        if !isLiveResizing { self.size = size }
    }

    public func liveResizeChanged(_ resizing: Bool) {
        isLiveResizing = resizing
        if !resizing { size = pendingSize }
    }
}

private struct GridViewportKey: FocusedValueKey { typealias Value = GridViewport }

extension FocusedValues {
    public var gridViewport: GridViewport? {
        get { self[GridViewportKey.self] }
        set { self[GridViewportKey.self] = newValue }
    }
}
